# Controllers & Views Reference

Laravel-inspired UI architecture. Controllers manage state and business logic; Views observe and render.


## MagicController

Base class for all controllers. Extends `ChangeNotifier`.

```dart
abstract class MagicController extends ChangeNotifier
```

| Member | Type | Purpose |
| :--- | :--- | :--- |
| `onInit()` | `void` | Called on first creation. Override to fetch data or init resources. `@mustCallSuper`. |
| `onClose()` | `void` | Called before dispose. Override to clean up timers, streams, etc. `@mustCallSuper`. |
| `refreshUI()` | `void` | Calls `notifyListeners()` safely (no-op if disposed). |
| `initialized` | `bool` | Whether `onInit()` has been called. |
| `isDisposed` | `bool` | Whether the controller has been disposed. |

`dispose()` automatically calls `onClose()` if not already called.

### SimpleMagicController

For controllers that do not need `MagicStateMixin`. Calls `onInit()` in the constructor so no view lifecycle is required.

```dart
abstract class SimpleMagicController extends MagicController
```


## MagicStateMixin\<T\>

Reactive state management mixed into `MagicController`. Tracks a single typed value alongside a status enum.

```dart
mixin MagicStateMixin<T> on MagicController
```

| Member | Type | Purpose |
| :--- | :--- | :--- |
| `rxState` | `T?` | Current state data. |
| `rxStatus` | `RxStatus` | Current status value (`RxStatus.empty()` initially). |
| `isLoading` | `bool` | True when status is loading. |
| `isSuccess` | `bool` | True when status is success. |
| `isError` | `bool` | True when status is error. |
| `isEmpty` | `bool` | True when status is empty. |
| `setLoading()` | `void` | Transition to loading, clears state. |
| `setSuccess(T data)` | `void` | Transition to success with data. |
| `setError(String msg)` | `void` | Transition to error with message, clears state. |
| `setEmpty()` | `void` | Transition to empty, clears state. |
| `setState(T? s, {RxStatus? status, bool notify = true})` | `void` | Low-level update. Pass `notify: false` to avoid "setState during build" in `initState`. |

### renderState

Declarative dispatcher that wraps the current status into a widget tree. Internally uses `AnimatedBuilder` so no explicit listener wiring is needed.

```dart
Widget renderState(
  Widget Function(T state) onSuccess, {
  Widget? onLoading,
  Widget Function(String message)? onError,
  Widget? onEmpty,
})
```

`onSuccess` is required. All other callbacks have sensible Wind-themed defaults (spinner, error icon, inbox icon).

```dart
controller.renderState(
  (data) => MonitorList(data),
  onLoading: const CircularProgressIndicator(),
  onError: (msg) => WText(msg),
  onEmpty: const WText('No monitors yet'),
)
```

### RxStatus

Immutable value class. Constructors: `RxStatus.loading()`, `RxStatus.success()`, `RxStatus.error(String message)`, `RxStatus.empty()`.


## Singleton Accessor Pattern

Register once, access anywhere without passing the instance around.

```dart
class MonitorController extends MagicController
    with MagicStateMixin<bool>, ValidatesRequests {
  static MonitorController get instance =>
      Magic.findOrPut(MonitorController.new);
}

// Caller:
MonitorController.instance.loadMonitors();
```

`Magic.findOrPut` resolves from the container or creates and registers a new instance.


## ValidatesRequests Mixin

Laravel-style validation on the controller side. Import from `package:magic/magic.dart`.

```dart
mixin ValidatesRequests on MagicController implements HasValidationErrors
```

| Member | Signature | Purpose |
| :--- | :--- | :--- |
| `validationErrors` | `Map<String, String>` | Field → first error message. Mutable. |
| `validate` | `Map<String, dynamic> validate(Map<String, dynamic> data, Map<String, List<Rule>> rules)` | Runs rules, populates `validationErrors`, throws `ValidationException` on failure. |
| `setErrorsFromResponse` | `void setErrorsFromResponse(MagicResponse response)` | Maps 422 response errors to `validationErrors` and notifies listeners. |
| `handleApiError` | `void handleApiError(MagicResponse response, {String? fallback})` | Auto-dispatch: 422 → `setErrorsFromResponse`; other errors → `setError(msg)`. Returns nothing — use an early return after calling it. |
| `hasError` | `bool hasError(String field)` | True if `field` has an error. |
| `getError` | `String? getError(String field)` | First error for field, or `null`. |
| `firstError` | `String?` | First error across all fields. |
| `hasErrors` | `bool` | True if any errors exist. |
| `clearErrors` | `void clearErrors()` | Clears all errors and notifies. |
| `clearFieldError` | `void clearFieldError(String field)` | Clears one field's error and notifies. |

### Server-side error flow

```dart
// Controller
Future<void> register(Map<String, dynamic> data) async {
  setLoading();
  clearErrors();

  final response = await Http.post('/register', data: data);

  if (response.successful) {
    setSuccess(true);
    MagicRoute.to('/dashboard');
    return;
  }

  handleApiError(response, fallback: 'Registration failed');
}

// View
if (controller.hasError('email'))
  WText(controller.getError('email')!, className: 'text-red-500 text-xs'),
```


## ValueNotifier Pattern

Use `ValueNotifier` fields on the controller for sections that must rebuild independently of the main `RxStatus`. Pair with `MagicBuilder` in views.

```dart
class MonitorController extends MagicController
    with MagicStateMixin<bool>, ValidatesRequests {
  static MonitorController get instance =>
      Magic.findOrPut(MonitorController.new);

  final monitorsNotifier = ValueNotifier<List<Monitor>>([]);
  final selectedMonitorNotifier = ValueNotifier<Monitor?>(null);

  @override
  void onInit() {
    super.onInit();
    loadMonitors();
  }

  Future<void> loadMonitors() async {
    setLoading();
    try {
      monitorsNotifier.value = await Monitor.all();
      setSuccess(true);
    } catch (e) {
      Log.error('Failed to load monitors: $e', e);
      setError(trans('errors.network_error'));
    }
  }

  @override
  void dispose() {
    monitorsNotifier.dispose();
    selectedMonitorNotifier.dispose();
    super.dispose();
  }
}
```


## MagicView\<T\>

Stateless view that auto-resolves its controller from the Magic container.

```dart
abstract class MagicView<T extends MagicController> extends StatelessWidget
```

| Member | Type | Purpose |
| :--- | :--- | :--- |
| `controller` | `T` | Resolved via `Magic.find<T>()`. Available in `build()`. |

```dart
class MonitorListView extends MagicView<MonitorController> {
  const MonitorListView({super.key});

  @override
  Widget build(BuildContext context) {
    return controller.renderState(
      (_) => MagicBuilder<List<Monitor>>(
        listenable: controller.monitorsNotifier,
        builder: (monitors) => ListView.builder(
          itemCount: monitors.length,
          itemBuilder: (_, i) => MonitorTile(monitors[i]),
        ),
      ),
      onLoading: const CircularProgressIndicator(),
      onError: (msg) => WText(msg),
    );
  }
}
```

`MagicView` does not auto-listen to controller changes — `renderState` handles its own `AnimatedBuilder` internally. For arbitrary controller-driven rebuilds outside `renderState`, use `MagicStatefulView`.


## MagicStatefulView\<T\>

Stateful view with lifecycle hooks and automatic controller listener attachment. The base widget is the thin `StatefulWidget`; all logic lives in the state class.

```dart
abstract class MagicStatefulView<T extends MagicController> extends StatefulWidget
abstract class MagicStatefulViewState<T extends MagicController,
    V extends MagicStatefulView<T>> extends State<V>
```

`MagicStatefulViewState` wires `_controller.addListener(_rebuild)` in `initState` and removes it in `dispose`. On init it also silently clears any stale validation errors and `RxStatus.error` state (mimicking Laravel's per-request error clearing).

| Member | Type | Purpose |
| :--- | :--- | :--- |
| `controller` | `T` | Auto-resolved via `Magic.find<T>()` in `initState`. |
| `onInit()` | `void` | Called at end of `initState`. Controller is available. |
| `onClose()` | `void` | Called at start of `dispose`. Use to clean up local resources. |
| `rules<R>(List<Rule>, {required String field, Map<String, dynamic>? extraData})` | `String? Function(R?)` | Convenience wrapper around `FormValidator.rules` that auto-injects `controller` for server-side error display. Use inside `MagicForm`. |

```dart
class LoginView extends MagicStatefulView<AuthController> {
  const LoginView({super.key});

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState
    extends MagicStatefulViewState<AuthController, LoginView> {
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  void onClose() {
    _email.dispose();
    _password.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MagicForm(
      controller: controller,
      child: Column(
        children: [
          WFormInput(
            controller: _email,
            validator: rules([Required(), Email()], field: 'email'),
          ),
          if (controller.hasError('email'))
            WText(controller.getError('email')!, className: 'text-red-500 text-xs'),
          WFormInput(
            controller: _password,
            type: InputType.password,
            validator: rules([Required(), Min(8)], field: 'password'),
          ),
          WButton(
            onTap: _submit,
            isLoading: controller.isLoading,
            child: const WText('Login'),
          ),
        ],
      ),
    );
  }

  void _submit() {
    if (Form.of(context).validate()) {
      controller.attemptLogin(
        email: _email.text,
        password: _password.text,
      );
    }
  }
}
```


## MagicResponsiveView\<T\>

Stateless responsive view. Extends `MagicView<T>` — `controller` getter is available.

```dart
abstract class MagicResponsiveView<T extends MagicController>
    extends MagicView<T>
```

| Method | Breakpoint | Default fallback |
| :--- | :--- | :--- |
| `watch(BuildContext)` | `< 320px` | delegates to `phone` |
| `phone(BuildContext)` | `< sm (640px)` | **required** |
| `tablet(BuildContext)` | `>= sm and < lg (1024px)` | delegates to `phone` |
| `desktop(BuildContext)` | `>= lg (1024px)` | delegates to `tablet` |

Breakpoints are read from `WindThemeData.screens`; defaults are used when no `WindTheme` is present.

```dart
class DashboardView extends MagicResponsiveView<DashboardController> {
  const DashboardView({super.key});

  @override
  Widget phone(BuildContext context) => const MobileDashboard();

  @override
  Widget tablet(BuildContext context) => const TabletDashboard();

  @override
  Widget desktop(BuildContext context) => const DesktopDashboard();
}
```

### MagicResponsiveViewExtended\<T\>

Six-breakpoint variant with `xs`, `sm`, `md`, `lg`, `xl`, `xxl` methods, each defaulting to the smaller one. Use when you need distinct layouts at every Wind breakpoint.

### MagicResponsiveContext extension

Available on `BuildContext` after importing `package:magic/magic.dart`:

| Getter | Type | Purpose |
| :--- | :--- | :--- |
| `screenWidth` | `double` | `MediaQuery` width shorthand. |
| `screenHeight` | `double` | `MediaQuery` height shorthand. |
| `isPhone` | `bool` | Width `< sm`. |
| `isTablet` | `bool` | Width `>= sm and < lg`. |
| `isDesktop` | `bool` | Width `>= lg`. |
| `activeBreakpoint` | `String` | Current Wind breakpoint name. |
| `isAtLeast(String bp)` | `bool` | True if screen is at or above the given breakpoint. |


## MagicBuilder\<T\>

Thin, generic wrapper around `ValueListenableBuilder`. Builder receives only the value — no context, no child.

```dart
class MagicBuilder<T> extends StatelessWidget {
  const MagicBuilder({
    super.key,
    required ValueListenable<T> listenable,
    required Widget Function(T value) builder,
  });
}
```

```dart
MagicBuilder<List<Monitor>>(
  listenable: controller.monitorsNotifier,
  builder: (monitors) => ListView.builder(
    itemCount: monitors.length,
    itemBuilder: (_, i) => MonitorTile(monitors[i]),
  ),
)

MagicBuilder<bool>(
  listenable: controller.realTimeEnabledNotifier,
  builder: (enabled) => Switch(value: enabled, onChanged: (_) {}),
)
```

Use `ValueListenableBuilder` directly when you need `BuildContext` or the `child` optimisation inside the builder.


## Complete Lifecycle Example

End-to-end: controller registration, data loading, view rendering, form submission.

```dart
// 1. Controller — registered in a ServiceProvider boot()
class PostController extends MagicController
    with MagicStateMixin<List<Post>>, ValidatesRequests {
  static PostController get instance =>
      Magic.findOrPut(PostController.new);

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    setLoading();
    try {
      setSuccess(await Post.all());
    } catch (e) {
      setError(trans('errors.network_error'));
    }
  }

  Future<void> store(Map<String, dynamic> data) async {
    setLoading();
    clearErrors();
    final response = await Http.post('/posts', data: data);
    if (response.successful) {
      setSuccess(await Post.all());
      MagicRoute.to('/posts');
      return;
    }
    handleApiError(response, fallback: trans('posts.create_failed'));
  }
}

// 2. List view — stateless, no local state needed
class PostIndexView extends MagicView<PostController> {
  const PostIndexView({super.key});

  @override
  Widget build(BuildContext context) {
    return controller.renderState(
      (posts) => ListView.builder(
        itemCount: posts.length,
        itemBuilder: (_, i) => PostTile(posts[i]),
      ),
      onEmpty: const WText('No posts yet'),
      onError: (msg) => WText(msg),
    );
  }
}

// 3. Create view — stateful for TextEditingControllers
class PostCreateView extends MagicStatefulView<PostController> {
  const PostCreateView({super.key});

  @override
  State<PostCreateView> createState() => _PostCreateViewState();
}

class _PostCreateViewState
    extends MagicStatefulViewState<PostController, PostCreateView> {
  final _title = TextEditingController();
  final _body = TextEditingController();

  @override
  void onClose() {
    _title.dispose();
    _body.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MagicForm(
      controller: controller,
      child: Column(
        children: [
          WFormInput(
            controller: _title,
            validator: rules([Required(), Max(255)], field: 'title'),
          ),
          if (controller.hasError('title'))
            WText(controller.getError('title')!, className: 'text-red-500'),
          WFormInput(
            controller: _body,
            validator: rules([Required()], field: 'body'),
          ),
          WButton(
            onTap: _submit,
            isLoading: controller.isLoading,
            child: const WText('Publish'),
          ),
        ],
      ),
    );
  }

  void _submit() {
    if (Form.of(context).validate()) {
      controller.store({'title': _title.text, 'body': _body.text});
    }
  }
}
```


## Gotchas

- **Registration required**: The controller MUST be in the IoC container before `MagicView` builds. Register via `Magic.put(MyController())` or the singleton accessor (`Magic.findOrPut`).
- **onInit is synchronous at the call site**: `MagicStatefulView` calls `onInit()` synchronously. Async work inside it fires off but the first build runs before it completes — always handle the initial empty/loading state.
- **No notifyListeners in build**: `setSuccess`, `setError`, etc. call `notifyListeners`. Never call them inside `build()` or a constructor.
- **Dispose ValueNotifiers**: If you declare `ValueNotifier` fields, override `dispose()` and call `.dispose()` on each before `super.dispose()`.
- **rules() lives on the state, not the controller**: The `rules()` helper is a method on `MagicStatefulViewState`. It auto-injects the controller so server-side field errors surface through the form validator.
- **MagicView vs MagicStatefulView**: Use `MagicView` when `renderState` covers all rebuild needs. Use `MagicStatefulView` when you need `TextEditingController`, local state, or full Flutter lifecycle hooks.
- **ValidatesRequests import**: Import `package:magic/magic.dart` — the mixin is re-exported from the barrel, not from `concerns/`.
