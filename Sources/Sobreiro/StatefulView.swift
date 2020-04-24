
public enum RenderPolicy {
    case possible
    case notPossible(RenderError)
    
    public enum RenderError {
        case viewNotReady
        case viewDeallocated
    }
}

public protocol StatefulView: class {
    associatedtype State: ViewState
    var renderPolicy: RenderPolicy { get }
    
    // Never call it directly. Always call viewModel's `subscribe(from:)`. Some advantages:
    //
    // 1. We have "arrow consistency", always being rendered by viewModel's command, minimizing
    // view logic. View only decides when it's ready to subscribe, depending on its lifecycle.
    //
    // 2. Avoid rendering the view when not appropriate, such as when trying to render in a thread
    // different from the main one, when the view is not yet on the screen or trying to render the
    // very same state.
    func render(state: State)
}

// MARK: Wrapper

class AnyStatefulView<State: ViewState>: StatefulView {
    private let identifier: String
    
    private let _render: (State) -> Void
    private let _renderPolicy: () -> RenderPolicy
    
    init<View: StatefulView>(_ statefulView: View) where View.State == State {
        _render = { [weak statefulView] in statefulView?.render(state: $0) }
        _renderPolicy = { [weak statefulView] in statefulView?.renderPolicy ?? .notPossible(.viewDeallocated) }
        identifier = "\(State.self)::\(type(of: statefulView))::\(String(describing: Unmanaged.passUnretained(statefulView).toOpaque()))"
    }
    
    func render(state: State) { _render(state) }
    var renderPolicy: RenderPolicy { _renderPolicy() }
}

extension AnyStatefulView: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine("AnyStatefulView")
        hasher.combine(identifier)
    }
    
    static func == (lhs: AnyStatefulView, rhs: AnyStatefulView) -> Bool {
        lhs.identifier == rhs.identifier
    }
}

// MARK: - Default Render Policy

#if os(OSX)
import AppKit

// MARK: NSWindowController
public extension StatefulView where Self: NSWindowController {
    var renderPolicy: RenderPolicy { isWindowLoaded ? .possible : .notPossible(.viewNotReady) }
}

// MARK: NSViewController
public extension StatefulView where Self: NSViewController {
    var renderPolicy: RenderPolicy { isViewLoaded ? .possible : .notPossible(.viewNotReady) }
}

// MARK: NSView
public extension StatefulView where Self: NSView {
    var renderPolicy: RenderPolicy {
        if superview != nil { return .possible }
        guard let root = window?.contentView else { return .notPossible(.viewNotReady) }
        return root === self ? .possible : .notPossible(.viewNotReady)
    }
}

#elseif os(iOS) || os(tvOS)
import UIKit

// MARK: UIViewController
public extension StatefulView where Self: UIViewController {
    var renderPolicy: RenderPolicy { isViewLoaded ? .possible : .notPossible(.viewNotReady) }
}

// MARK: UIView
public extension StatefulView where Self: UIView {
    var renderPolicy: RenderPolicy { superview != nil ? .possible : .notPossible(.viewNotReady) }
}

#elseif os(watchOS)
#endif
