# Controllers & Views Reference

Laravel-inspired UI architecture. Controllers manage state and business logic; Views observe and render.


## MagicController

Base class for business logic, extending `ChangeNotifier`.

| Method | Purpose |
| :--- | :--- |
| `onInit()` | Called on first creation. Use for async data fetching. |
| `onClose()` | Called before dispose. Clean up resources (timers, streams). |
| `refreshUI()` | Shorthand for `notifyListeners()`. |
| `initialized` | `bool` — whether `onInit` has completed. |
| `isDisposed` | `bool` — whether the controller has been disposed. |

## MagicStateMixin<T>

Reactive state management mixed into `MagicController`.

| Property/Method | Type | Purpose |
| :--- | :--- | :--- |
| `rxState` | `T?` | Current state data. |
| `rxStatus` | `RxStatus` | Current status (loading/success/error/empty). |
| `isLoading` | `bool` | Quick check for loading status. |
| `isSuccess` | `bool` | Quick check for success status. |
| `isError` | `bool` | Quick check for error status. |
| `isEmpty` | `bool` | Quick check for empty status. |
| `setLoading()` | `void` | Transition to loading status. |
| `setSuccess(T data)` | `void` | Transition to success with data. |
| `setError(String msg)`| `void` | Transition to error with message. |
| `setEmpty()` | `void` | Transition to empty status. |
| `setState(...)` | `void` | Low-level state/status update with optional notification. |

### renderState
Declarative UI dispatcher for handling different state statuses:

```dart
controller.renderState(
  (data) => MonitorListView(data),    // onSuccess — required
  onLoading: const CircularProgressIndicator(),
  onError: (msg) => ErrorWidget(msg),
  onEmpty: const WText('No data available'),
)
```

## Controller Pattern

Standard production example for a resource controller:

```dart
class MonitorController extends MagicController
    with MagicStateMixin<bool>, ValidatesRequests {
  static MonitorController get instance => Magic.findOrPut(MonitorController.new);

  final monitorsNotifier = ValueNotifier<List<Monitor>>([]);

  Future<void> loadMonitors() async {
    setLoading();
    try {
      final monitors = await Monitor.all();
      monitorsNotifier.value = monitors;
      setSuccess(true);
    } catch (e) {
      Log.error('Failed to load monitors: $e', e);
      setError(trans('errors.network_error'));
    }
  }

  Future<void> store(Map<String, dynamic> data) async {
    setLoading();
    clearErrors();
    
    final response = await Http.post('/monitors', data: data);
    
    if (response.successful) {
      Magic.toast(trans('monitors.created'));
      MagicRoute.to('/monitors');
      return;
    }
    
    handleApiError(response, fallback: trans('monitors.create_failed'));
  }
}
```

## ValidatesRequests Mixin

API for handling form validation and server-side errors.

| Method | Signature | Purpose |
| :--- | :--- | :--- |
| `validate` | `Map<String, dynamic> validate(Map data, Map<String, List<Rule>> rules)` | Validate + throw on fail. |
| `setErrorsFromResponse` | `void setErrorsFromResponse(MagicResponse response)` | Map 422 errors to fields. |
| `handleApiError` | `void handleApiError(MagicResponse res, {String? fallback})` | Auto-handle 422 + other errors. |
| `hasError` | `bool hasError(String field)` | Check if field has an error. |
| `getError` | `String? getError(String field)` | Get field error message. |
| `firstError` | `String?` | Get the very first available error. |
| `hasErrors` | `bool` | Check if any errors exist. |
| `clearErrors` | `void clearErrors()` | Clear all validation errors. |
| `clearFieldError` | `void clearFieldError(String field)` | Clear error for specific field. |
| `validationErrors` | `Map<String, String>` | Direct access to field error map. |

## MagicView<T>

Stateless view that auto-resolves its controller.

```dart
class MonitorListView extends MagicView<MonitorController> {
  const MonitorListView({super.key});

  @override
  Widget build(BuildContext context) {
    return controller.renderState(
      (data) => ListView.builder(
        itemCount: controller.monitorsNotifier.value.length,
        itemBuilder: (context, index) => MonitorTile(controller.monitorsNotifier.value[index]),
      ),
      onLoading: const CircularProgressIndicator(),
      onError: (msg) => WText(msg),
    );
  }
}
```

## MagicStatefulView<T>

Stateful view with lifecycle and auto-controller management.

```dart
class LoginView extends MagicStatefulView<AuthController> {
  const LoginView({super.key});

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends MagicStatefulViewState<AuthController, LoginView> {
  late final form = MagicFormData({
    'email': '',
    'password': '',
  }, controller: controller);

  @override
  void onInit() {
    // Controller is available here as 'controller'
  }

  @override
  void onClose() {
    form.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MagicForm(
      formData: form,
      child: Column(
        children: [
          WFormInput(
            controller: form['email'],
            validator: rules([Required(), Email()], field: 'email'),
          ),
          WFormInput(
            controller: form['password'],
            type: InputType.password,
            validator: rules([Required(), Min(8)], field: 'password'),
          ),
          WButton(
            onTap: _submit,
            child: const WText('Login'),
          ),
        ],
      ),
    );
  }

  void _submit() {
    if (!form.validate()) return;
    controller.doLogin(form.data);
  }
}
```

## MagicBuilder<T>

Thin wrapper around `ValueListenableBuilder` for reactive UI sections.

```dart
MagicBuilder<List<Monitor>>(
  listenable: controller.monitorsNotifier,
  builder: (context, monitors, _) => ListView.builder(
    itemCount: monitors.length,
    itemBuilder: (context, i) => MonitorTile(monitors[i]),
  ),
)
```

## Authorization Widgets

Declarative permission checking in the UI.

```dart
MagicCan(
  ability: 'edit-monitor',
  arguments: {'monitor': monitor},
  child: const EditButton(),
)

MagicCannot(
  ability: 'delete-monitor',
  arguments: {'monitor': monitor},
  child: const DisabledButton(),
)
```

## Gotchas

- **Registration**: Controller MUST be registered in the IoC container (via `Magic.put`) before `MagicView` attempts to build.
- **Async `onInit`**: `onInit()` is async. The first build usually fires before it completes; ensure your view handles the initial state (typically by rendering `onLoading`).
- **Notification Cycles**: `setSuccess()` and other status setters call `notifyListeners()`. NEVER call them inside a constructor or a build method.
- **Singleton Pattern**: Prefer the accessor pattern for controllers: `static X get instance => Magic.findOrPut(X.new);`.
- **View Choice**: Use `MagicView` for simple displays. Use `MagicStatefulView` when you need local state or form controllers.
- **Server Errors**: The `rules()` helper auto-injects the controller to allow the validator to check for server-side validation errors mapped to fields.
