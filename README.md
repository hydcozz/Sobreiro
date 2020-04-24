# Sobreiro

A simple way to use sum types to guarantee your view models are always in a valid state **Sobreiro** helps binding views to models in a lightweight manner.

## Requirements

* macOS 10.12+ / iOS 10+ / tvOS  10+
* Xcode 11+

## Installation

Besides dragging the sources, **Sobreiro** can be included via [Swift Package Manager](https://swift.org/package-manager/). A tool for automating distribution of Swift code, and is integrated into the swift compiler.

Go to File > Swift Packages > Add Package Dependency and enter

```
https://github.com/hydcozz/Sobreiro
```

## How to use in three steps

Firstly, define possible states with a tagged union, conforming to `ViewState`.

```swift
enum ListViewState: ViewState {
    case loading
    case loaded(Results)
    case error(Error)
}
```

Secondly, implement your view model and its update commands, inheriting `ViewModel` .

```swift
class ListViewModel: ViewModel<ListViewState> {
    func startLoading() {
        write {
            switch state {
            case .loading: return
            case .loaded(let results): state = .loading(results)
            case .error: state = .loading(nil)
            }
        }
    }
    
    func didLoad(results: Results) {
        write {
            state = .loaded(results)
        }
    }
    
    func didFail(with error: Error) {
        write {
            switch state {
            case .loading(let results): state = .error(error, results)
            case .loaded(let results): state = .error(error, results)
            case .error(_, let results): state = .error(error, results)
            }
        }
    }
}
```

**View model's `state` must be updated with a call to `write(_ transaction: () -> Void)`.**

Finally, implement your views and/or view controllers, conforming to `StatefulView` and subscribing to the view model.

```swift
class ListViewController: ViewController, StatefulView {
    override func viewDidLoad() {
        super.viewDidLoad()
        viewModel.subscribe(view: self)
    }
    
    func render(state: ListViewState) {
        // render state
    }
}
```

### Working without enumerations

Not all situations call for sum types. No reason to make your view state an enumeration if there's only one case to contemplate. However, it should not be a reference type.

Albeit not enforcing it, **Sobreiro** expects value types as view states. This guarantees the view model knows of any update.

```swift
struct MiniUserViewState: ViewState {
    let image: Image?
    let name: String
    let role: Role
    
    enum Role {
        case sales
        case support
        case development
    }
}
```

### Composed view models

**Sobreiro** provides subscription methods, allowing you to break view models in reusable or shared components.

```swift
struct FrontRunnerViewState: ViewState {
    let image: Image
    let name: String
    let points: Int
}

class FrontRunnerViewModel: ViewModel<FrontRunnerViewState> {
    let miniUserViewModel: MiniUserViewModel
    
    init(initialState: FrontRunnerViewState, miniUserViewModel: MiniUserViewModel) {
        self.miniUserViewModel = miniUserViewModel
        super.init(initialState: initialState)
        
        self.subscribe(to: miniUserViewModel, onChange: miniUserDidChange)
    }
    
    private func miniUserDidChange(_ newState: MiniUserViewState) {
        update {
            FrontRunnerViewState(
                image: newState.image ?? .noUserImage,
                name: newState.name,
                points: state.points
            )
        }
    }
}
```

## What's what (aka, documentation is lacking)

`StatefulView` can be conformed by any class, but **Sobreiro** offers default render policies for native views and controller; so it may be easier to use them.

```swift
#if os(OSX)
typealias Image = NSImage
#elseif os(iOS) || os(tvOS)
typealias Image = UIImage
#endif

enum ProfilePhotoViewState: ViewState {
    case online(Image)
    case offline(Image)
}

class ProfilePhotoViewModel: ViewModel<ProfilePhotoViewState> {
    // Implement commands…
}

#if os(OSX)
class ProfilePhotoView: NSView {
    // Don't for get to subscribe!
    // viewModel.subscribe(view: self)
}
#elseif os(iOS) || os(tvOS)
class ProfilePhotoView: UIView {
    // Don't for get to subscribe!
    // viewModel.subscribe(view: self)
}
#endif

extension ProfilePhotoView: StatefulView {
    func render(state: ProfilePhotoViewState) {
        // render state
    }
}
```

### Change view state

The state must be set via a write or an update. In writes you'll set the state, if needed. Updates will set the state for you, via a builder you provide. All mutating transaction are run atomically, so you're guaranteed the state won't be changed while they're executing.

```swift
// inside your view model

func animate() {
    write {
        guard !state.isAnimating() else {
            return
        }
        state = state.copyAnimating()
    }
}

func setColour(_ colour: Colour) {
    update {
        return state.copyColoured(with: colour)
    }
}
```

### View subscription

Stateful views subscribe to view models for their rendering to be trigger by state changes.

```swift
// inside your stateful view
viewModel.subscribe(view: self)
```

There's no need for unsubscribing stateful views when they're removed from memory, it's done automatically. You may nonetheless unsubscribe them yourself.

```swift
// inside your stateful view
var viewModel: ViewModel? {
    willSet { viewModel?.unsubscribe(view: self) }
    didSet { viewModel?.subscribe(view: self) }
}
```

When the view state changes, it'll trigger the rendering of all subscribed stateful views.

```swift
// inside your stateful view
func render(state: ViewState) {
    // state has changed
}
```

### Model subscription

You may wish to break a view model in reusable or shared components. If so, model subscription methods help binding view models to other view models.

```swift
// subscribe to a component
viewModel.subscribe(to: componentViewModel) { componentViewState in
    // handle component change
}
```

There's no need for unsubscribing when your model's removed from memory, it's done automatically. You may nonetheless unsubscribe them yourself.

```swift
// unsubscribe from a component
viewModel.unsubscribe(from: componentViewModel)
```

## Improve your view's model–state

This are a couple of recommendation to help you out:

* Use queries — particularly useful for complex models, where states overlap
* Avoid unnecessary rendering — if a command results in the same state, why render it again?

### Use queries

Add queries to your state.

```swift
extension ListViewState {
    func isLoading() -> Bool {
        switch self {
        case .loading: return true
        case .loaded, .error: return false
        }
    }
    
    func results() -> Results? {
        switch self {
        case .loading(let results): return results
        case .loaded(let results): return results
        case .error(_, let results): return results
        }
    }
    
    func error() -> Error? {
        switch self {
        case .error(let error, _): return error
        case .loaded, .loading: return nil
        }
    }
}
```

They can be used to assist rendering.

```swift
class ListViewController: ViewController, StatefulView {
    func render(state: ListViewState) {
        renderLoading(state.isLoading())
        renderResults(state.results())
        renderError(state.error())
    }
    
    func renderLoading(_ isLoading: Bool) {
        if isLoading {
            // animate activity indicator
        } else {
            // stop activity indicator
        }
    }
    
    func renderResults(_ results: Results?) {
        if let results = results {
            // present results
        } else {
            // clear results
        }
    }
    
    func renderError(_ error: Error?) {
        if let error = error {
            // present error
        } else {
            // clear error
        }
    }
}
```

### Avoid unnecessary rendering

Avoid rendering equal states by implementing the `==`  operator.

```swift
extension ListViewState {
    static func == (lhs: ListViewState, rhs: ListViewState) -> Bool {
        switch (lhs, rhs) {
        case (.loading(let lhs), .loading(let rhs)): return lhs == rhs
        case (.loaded(let lhs), .loaded(let rhs)): return lhs == rhs
        default: return false
        }
    }
}
```

## To Do

Proper documentation, maybe?

## Author

* Tiago Rodrigues

## Acknowledgements

This work was inspired by an article, written by [Luis Recuenco](https://github.com/luisrecuenco) at [Jobandtalent Engineering](jobandtalent.engineering), and titled [iOS Architecture: A State Container based approach](https://jobandtalent.engineering/ios-architecture-an-state-container-based-approach-4f1a9b00b82e).

This work adapts Jobandtalent's for exclusive use with views, and thus making it a tad lighter.

## License

Copyright (c) 2020 Tiago Rodrigues

Licensed under [MIT License](https://opensource.org/licenses/MIT).
