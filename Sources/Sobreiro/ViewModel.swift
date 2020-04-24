import Foundation

public protocol ViewState: Equatable {}

open class ViewModel<State: ViewState> {
    private var identifier: String {
        "\(State.self)::\(type(of: self))::\(String(describing: Unmanaged.passUnretained(self).toOpaque()))"
    }
    
    private var views = Set<AnyStatefulView<State>>()
    
    private var subscriptions = [String: AnyObject]()
    private var observers = NSHashTable<StateObserver<State>>.weakObjects()
    
    private lazy var stateTransactionQueue = DispatchQueue(label: "\(type(of: self)).state-transaction-queue")
    private lazy var stateBuildQueue = DispatchQueue(label: "\(type(of: self)).state-build-queue")
    
    public var state: State {
        didSet(oldState) {
            dispatchPrecondition(condition: .onQueue(stateTransactionQueue))
            stateDidChange(oldState: oldState, newState: state)
        }
    }
    
    public init(initialState: State) {
        self.state = initialState
    }
    
    private func sync(on queue: DispatchQueue, execute: () -> Void) {
        queue.sync {
            objc_sync_enter(self)
            defer { objc_sync_exit(self) }
            execute()
        }
    }
    
    // MARK: State Change
    
    public func write(_ transaction: () -> Void) {
        sync(on: stateTransactionQueue, execute: transaction)
    }
    
    public func update(_ builder: () -> State) {
        sync(on: stateBuildQueue) {
            let newState = builder()
            write { state = newState }
        }
    }
    
    private func stateDidChange(oldState: State, newState: State) {
        guard oldState != newState else { return }
        
        renderViews()
        fireObservers()
    }
    
    // MARK: View Rendering
    
    public func subscribe<View: StatefulView>(view: View) where View.State == State {
        let anyView = AnyStatefulView(view)
        if views.insert(anyView).inserted {
            handleRendering(of: state, in: anyView)
        } else {
            assert(true, "Trying to subscribe an already subscribed view.")
        }
    }
    
    public func unsubscribe<View: StatefulView>(view: View) where View.State == State {
        if views.remove(AnyStatefulView(view)) == nil {
            assert(true, "Trying to unsubscribe a not subscribed view.")
        }
    }
    
    private func renderViews() {
        views.forEach {
            handleRendering(of: state, in: $0)
        }
    }
    
    private func handleRendering(of state: State, in view: AnyStatefulView<State>) {
        switch view.renderPolicy {
        case .possible:
            handlePossiblePolicy(state: state, view: view)
        case .notPossible(let renderError):
            handleNotPossiblePolicy(error: renderError, view: view)
        }
    }
    
    private func handlePossiblePolicy(state: State, view: AnyStatefulView<State>) {
        let renderBlock = { view.render(state: state) }
        
        if Thread.isMainThread {
            renderBlock()
        } else {
            DispatchQueue.main.async(execute: renderBlock)
        }
    }
    
    private func handleNotPossiblePolicy(error: RenderPolicy.RenderError, view: AnyStatefulView<State>) {
        switch error {
        case .viewNotReady:
            fatalError("""
            View is not ready to be rendered.
            This usually happens when trying to render a view controller that is not ready yet (viewDidLoad
            hasn't been called yet and outlets are not ready) or a view that is not on the screen yet. To avoid
            this problem, try using `viewModel.subscribe(view: self)` from the view layer when the view or
            view controller are ready to be rendered.
            """)
        case .viewDeallocated:
            views.remove(view)
        }
    }
    
    // MARK: View Model subscription
    
    public func subscribe<S>(to other: ViewModel<S>, onChange block: @escaping (S) -> Void) {
        assert(subscriptions[other.identifier] == nil, "Trying to subscribe to an already subscribed view model.")
        subscriptions[other.identifier] = other.subscribe(block)
    }
    
    public func unsubscribe<S>(from other: ViewModel<S>) {
        assert(subscriptions[other.identifier] != nil, "Trying to unsubscribe from a not subscribed view model.")
        subscriptions[other.identifier] = nil
    }
    
    private func subscribe(_ block: @escaping (State) -> Void) -> StateObserver<State> {
        let observer = StateObserver(block)
        observers.add(observer)
        observer.fire(state)
        return observer
    }
    
    private func fireObservers() {
        observers.allObjects.forEach {
            $0.fire(state)
        }
    }
}

class StateObserver<State: ViewState> {
    private(set) var block: ((State) -> Void)?
    
    public var isValid: Bool {
        return block != nil
    }
    
    init(_ block: @escaping (State) -> Void) {
        self.block = block
    }
    
    func fire(_ state: State) {
        block?(state)
    }
    
    public func invalidate() {
        block = nil
    }
    
    deinit {
        invalidate()
    }
}

// MARK: - Default Equatable

public extension Equatable where Self: ViewState {
    static func == (lhs: Self, rhs: Self) -> Bool {
        false
    }
}
