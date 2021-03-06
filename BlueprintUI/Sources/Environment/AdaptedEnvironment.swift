import CoreGraphics

/// Wraps an element tree with a modified environment.
///
/// By specifying environmental values with this element, all child elements nested
/// will automatically inherit those values automatically. Values can be changed
/// anywhere in a sub-tree by inserting another `AdaptedEnvironment` element.
public struct AdaptedEnvironment: Element {
    var wrappedElement: Element
    var environmentAdapter: (inout Environment) -> Void

    /// Wraps an element with an environment that is modified using the given
    /// configuration block.
    /// - Parameters:
    ///   - by: A block that will set environmental values.
    ///   - wrapping: The element to be wrapped.
    public init(
        by environmentAdapter: @escaping (inout Environment) -> Void,
        wrapping wrappedElement: Element)
    {
        self.wrappedElement = wrappedElement
        self.environmentAdapter = environmentAdapter
    }

    /// Wraps an element with an environment that is modified for a single key and value.
    /// - Parameters:
    ///   - key: The environment key to modify.
    ///   - value: The new environment value to cascade.
    ///   - wrapping: The element to be wrapped.
    public init<Key>(key: Key.Type, value: Key.Value, wrapping child: Element) where Key: EnvironmentKey {
        self.init(by: { $0[key] = value }, wrapping: child)
    }

    /// Wraps an element with an environment that is modified for a single value.
    /// - Parameters:
    ///   - keyPath: The keypath of the environment value to modify.
    ///   - value: The new environment value to cascade.
    ///   - wrapping: The element to be wrapped.
    public init<Value>(keyPath: WritableKeyPath<Environment, Value>, value: Value, wrapping child: Element) {
        self.init(by: { $0[keyPath: keyPath] = value }, wrapping: child)
    }

    public var content: ElementContent {
        return ElementContent(child: wrappedElement, environment: environmentAdapter)
    }

    public func backingViewDescription(bounds: CGRect, subtreeExtent: CGRect?) -> ViewDescription? {
        return nil
    }
}

public extension Element {
    /// Wraps this element in an `AdaptedEnvironment` with the given enviroment key and value.
    func adaptedEnvironment<Key>(key: Key.Type, value: Key.Value) -> Element where Key: EnvironmentKey {
        AdaptedEnvironment(key: key, value: value, wrapping: self)
    }

    /// Wraps this element in an `AdaptedEnvironment` with the given keypath and value.
    func adaptedEnvironment<Value>(keyPath: WritableKeyPath<Environment, Value>, value: Value) -> Element {
        AdaptedEnvironment(keyPath: keyPath, value: value, wrapping: self)
    }

    /// Wraps this element in an `AdaptedEnvironment` with the given configuration block.
    func adaptedEnvironment(by environmentAdapter: @escaping (inout Environment) -> Void) -> Element {
        AdaptedEnvironment(by: environmentAdapter, wrapping: self)
    }
}
