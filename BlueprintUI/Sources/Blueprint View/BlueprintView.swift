import UIKit

/// A view that is responsible for displaying an `Element` hierarchy.
///
/// A view controller that renders content via Blueprint might look something
/// like this:
///
/// ```
/// final class HelloWorldViewController: UIViewController {
///
///    private var blueprintView = BlueprintView(element: nil)
///
///    override func viewDidLoad() {
///        super.viewDidLoad()
///
///        let rootElement = Label(text: "Hello, world!")
///        blueprintView.element = rootElement
///        view.addSubview(blueprintView)
///     }
///
///     override func viewDidLayoutSubviews() {
///         super.viewDidLayoutSubviews()
///         blueprintView.frame = view.bounds
///     }
///
/// }
/// ```
public final class BlueprintView: UIView {

    private var needsViewHierarchyUpdate: Bool = true
    private var hasUpdatedViewHierarchy: Bool = false
    private var lastViewHierarchyUpdateBounds: CGRect = .zero

    /// Used to detect reentrant updates
    private var isInsideUpdate: Bool = false

    private let rootController: NativeViewController

    /// The root element that is displayed within the view.
    public var element: Element? {
        didSet {
            setNeedsViewHierarchyUpdate()
            invalidateIntrinsicContentSize()
        }
    }
    
    public static var globalDebugging : Debugging = Debugging() {
        didSet {
            NotificationCenter.default.post(name: .BlueprintGlobalDebuggingSettingsChanged, object: nil)
        }
    }
    
    public var debugging : Debugging = Debugging() {
        didSet {
            self.setNeedsViewHierarchyUpdate()
            //self.layoutIfNeeded()
            //self.apply3DTransform()
        }
    }

    /// Instantiates a view with the given element
    ///
    /// - parameter element: The root element that will be displayed in the view.
    public required init(element: Element?) {
        
        self.element = element
        
        rootController = NativeViewController(
            node: NativeViewNode(
                content: UIView.describe() { _ in },
                layoutAttributes: LayoutAttributes(),
                children: []))
    
        super.init(frame: CGRect.zero)
        
        self.backgroundColor = .white
        
        addSubview(rootController.view)
        
        setContentHuggingPriority(.defaultHigh, for: .horizontal)
        setContentHuggingPriority(.defaultHigh, for: .vertical)
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(globalDebuggingSettingsChanged),
            name: .BlueprintGlobalDebuggingSettingsChanged,
            object: nil
        )
    }

    public override convenience init(frame: CGRect) {
        self.init(element: nil)
        self.frame = frame
    }

    @available(*, unavailable)
    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Forwarded to the `measure(in:)` implementation of the root element.
    override public func sizeThatFits(_ size: CGSize) -> CGSize {
        guard let element = element else { return .zero }
        let constraint: SizeConstraint
        if size == .zero {
            constraint = SizeConstraint(width: .unconstrained, height: .unconstrained)
        } else {
            constraint = SizeConstraint(size)
        }
        return element.content.measure(in: constraint)
    }

    /// Returns the size of the element bound to the current width (mimicking
    /// UILabel’s `intrinsicContentSize` behavior)
    public override var intrinsicContentSize: CGSize {
        guard let element = element else { return .zero }
        let constraint: SizeConstraint

        // Use unconstrained when
        // a) we need a view hierarchy update to force a loop through an
        //    unconstrained width so we don’t end up “caching” the previous
        //    element’s width
        // b) the current width is zero, since constraining by zero is
        //    nonsensical
        if bounds.width == 0 || needsViewHierarchyUpdate {
            constraint = .unconstrained
        } else {
            constraint = SizeConstraint(width: bounds.width)
        }
        return element.content.measure(in: constraint)
    }
    
    override public func layoutSubviews() {
        super.layoutSubviews()
        invalidateIntrinsicContentSize()
        performUpdate()
    }
    
    private func performUpdate() {
        updateViewHierarchyIfNeeded()
    }
    
    private func setNeedsViewHierarchyUpdate() {
        guard !needsViewHierarchyUpdate else { return }
        needsViewHierarchyUpdate = true
        
        /// We currently rely on CA's layout pass to actually perform a hierarchy update.
        setNeedsLayout()
    }
    
    private func updateViewHierarchyIfNeeded() {
        guard needsViewHierarchyUpdate || bounds != lastViewHierarchyUpdateBounds else { return }

        assert(!isInsideUpdate, "Reentrant updates are not supported in BlueprintView. Ensure that view events from within the hierarchy are not synchronously triggering additional updates.")
        isInsideUpdate = true

        needsViewHierarchyUpdate = false
        lastViewHierarchyUpdateBounds = bounds
        
        /// Grab view descriptions
        let viewNodes = element?
            .layout(frame: bounds)
            .resolve(debugging: self.debugging) ?? []
        
        rootController.view.frame = bounds
        
        let rootNode = NativeViewNode(
            content: UIView.describe() { _ in },
            layoutAttributes: LayoutAttributes(frame: bounds),
            children: viewNodes
        )
        
        rootController.update(node: rootNode, appearanceTransitionsEnabled: hasUpdatedViewHierarchy)
        hasUpdatedViewHierarchy = true

        isInsideUpdate = false
    }

    var currentNativeViewControllers: [(path: ElementPath, node: NativeViewController)] {

        /// Perform an update if needed so that the node hierarchy is fully populated.
        updateViewHierarchyIfNeeded()

        /// rootViewNode always contains a simple UIView – its children represent the
        /// views that are actually generated by the root element.
        return rootController.children
    }
    
    @objc private func globalDebuggingSettingsChanged() {
        self.setNeedsViewHierarchyUpdate()
    }
    
}

extension BlueprintView {
    
    final class NativeViewController {

        private var viewDescription: ViewDescription

        private var layoutAttributes: LayoutAttributes
        
        private (set) var children: [(ElementPath, NativeViewController)]
        
        let view: UIView
        
        init(node: NativeViewNode) {
            self.viewDescription = node.viewDescription
            self.layoutAttributes = node.layoutAttributes
            self.children = []
            self.view = node.viewDescription.build()
            update(node: node, appearanceTransitionsEnabled: false)
        }

        fileprivate func canUpdateFrom(node: NativeViewNode) -> Bool {
            return node.viewDescription.viewType == type(of: view)
        }

        fileprivate func update(node: NativeViewNode, appearanceTransitionsEnabled: Bool) {
            
            assert(node.viewDescription.viewType == type(of: view))

            viewDescription = node.viewDescription
            layoutAttributes = node.layoutAttributes
            
            viewDescription.apply(to: view)
            
            var oldChildren: [ElementPath: NativeViewController] = [:]
            oldChildren.reserveCapacity(children.count)
            
            for (path, childController) in children {
                oldChildren[path] = childController
            }
            
            var newChildren: [(path: ElementPath, node: NativeViewController)] = []
            newChildren.reserveCapacity(node.children.count)
            
            var usedKeys: Set<ElementPath> = []
            usedKeys.reserveCapacity(node.children.count)
            
            for index in node.children.indices {
                let (path, child) = node.children[index]

                guard usedKeys.contains(path) == false else {
                    fatalError("Duplicate view identifier")
                }
                usedKeys.insert(path)

                let contentView = node.viewDescription.contentView(in: self.view)

                if let controller = oldChildren[path], controller.canUpdateFrom(node: child) {

                    oldChildren.removeValue(forKey: path)
                    newChildren.append((path: path, node: controller))
                    
                    let layoutTransition: LayoutTransition
                    
                    if child.layoutAttributes != controller.layoutAttributes {
                        layoutTransition = child.viewDescription.layoutTransition
                    } else {
                        layoutTransition = .inherited
                    }
                    layoutTransition.perform {
                        child.layoutAttributes.apply(to: controller.view)

                        contentView.insertSubview(controller.view, at: index)

                        controller.update(node: child, appearanceTransitionsEnabled: true)
                    }
                } else {
                    let controller = NativeViewController(node: child)
                    newChildren.append((path: path, node: controller))
                    
                    UIView.performWithoutAnimation {
                        child.layoutAttributes.apply(to: controller.view)
                    }
                    
                    contentView.insertSubview(controller.view, at: index)

                    controller.update(node: child, appearanceTransitionsEnabled: false)
                    
                    if appearanceTransitionsEnabled {
                        child.viewDescription.appearingTransition?.performAppearing(view: controller.view, layoutAttributes: child.layoutAttributes, completion: {})
                    }
                }
            }
            
            for controller in oldChildren.values {
                if let transition = controller.viewDescription.disappearingTransition {
                    transition.performDisappearing(view: controller.view, layoutAttributes: controller.layoutAttributes, completion: {
                        controller.view.removeFromSuperview()
                    })
                } else {
                    controller.view.removeFromSuperview()
                }
            }
            
            children = newChildren
        }
    }
}

