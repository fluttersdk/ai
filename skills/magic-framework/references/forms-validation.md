# Forms & Validation

Comprehensive guide to handling form state, validation rules, and server-side error mapping in the Magic framework.


## MagicFormData

The central manager for form state. It automatically infers the correct controller type based on the initial value provided in the map.

- `String` -> `TextEditingController`
- `bool`, `MagicFile?`, or other types -> `ValueNotifier<dynamic>`

```dart
late final form = MagicFormData({
  'name': 'John Doe',          // String → TextEditingController
  'email': '',                  // String → TextEditingController
  'accept_terms': false,        // bool → ValueNotifier<dynamic>
  'avatar': null as MagicFile?, // MagicFile? → ValueNotifier<dynamic>
}, controller: controller);
```

Constructor signature:

```dart
MagicFormData(Map<String, dynamic> fields, {MagicController? controller})
```

The optional `controller` param enables two side-effects:
1. Auto-clears the field's server-side error from the controller whenever the user types or changes a value.
2. Allows `validate()` to call `clearErrors()` on the controller before running client-side rules.

### API Surface

| Member | Signature | Purpose |
|--------|-----------|---------|
| `form['field']` | `TextEditingController` | Get text controller (String fields only) |
| `form.value<T>('field')` | `T` | Get typed value from ValueNotifier (non-text) |
| `form.setValue<T>('field', value)` | `void` | Set value for a non-text field |
| `form.get('field')` | `String` | Get trimmed text from a text controller |
| `form.set('field', 'text')` | `void` | Set text value in a text controller |
| `form.data` | `Map<String, dynamic>` | Export all values (text fields are auto-trimmed) |
| `form.validate()` | `bool` | Run client-side validation (clears server errors first) |
| `form.validated()` | `Map<String, dynamic>` | Returns `data` if valid, otherwise empty `{}` |
| `form.process<T>(action)` | `Future<T>` | Execute async action with automatic processing state management |
| `form.isProcessing` | `bool` | Whether `process()` is currently executing |
| `form.processingListenable` | `ValueListenable<bool>` | Listenable for granular rebuilds of processing-dependent UI |
| `form.fieldNames` | `Set<String>` | All registered field names (text + value fields) |
| `form.hasRelevantErrors` | `bool` | True if controller has server errors matching this form's fields |
| `form.dispose()` | `void` | Dispose all internal controllers and notifiers |

**Auto-clear behavior:** When a user types into a field managed by `MagicFormData`, any existing server-side error for that specific field is automatically cleared from the controller.

### process()

Wraps an async action with automatic `isProcessing` toggling. Throws `StateError` if called while already processing. Always resets processing state on completion, including on error.

```dart
// In the view submit handler:
Future<void> _submit() async {
  if (!form.validate()) return;

  await form.process(() => controller.doRegister(form.data));
}
```

Use `processingListenable` for efficient, form-scoped loading indicators without full-page rebuilds:

```dart
MagicBuilder<bool>(
  listenable: form.processingListenable,
  builder: (isProcessing) => WButton(
    isLoading: isProcessing,
    onTap: _submit,
    child: WText(trans('common.save')),
  ),
)
```


## MagicForm Widget

A wrapper around Flutter's `Form` widget that integrates with `MagicFormData`. It automatically handles form keys and controller scoping.

```dart
const MagicForm({
  Key? key,
  MagicFormData? formData,        // Recommended: extracts formKey + controller
  GlobalKey<FormState>? formKey,  // Legacy: explicit key
  MagicController? controller,    // Legacy: explicit controller
  required Widget child,
  AutovalidateMode? autovalidateMode,
  VoidCallback? onChanged,
  WillPopCallback? onWillPop,
  String? restorationId,
})
```

Either `formData` or `controller` must be provided.

```dart
MagicForm(
  formData: form,
  child: Column(children: [
    WFormInput(
      controller: form['email'],
      validator: rules([Required(), Email()], field: 'email'),
    ),
    WFormCheckbox(
      value: form.value<bool>('accept_terms'),
      onChanged: (val) => form.setValue('accept_terms', val),
    ),
  ]),
)
```

**Smart Autovalidation:** `MagicForm` automatically switches its `AutovalidateMode` to `always` when the associated controller contains server-side errors relevant to this form (checked via `form.hasRelevantErrors`). When using the legacy path without `formData`, it falls back to `controller.hasErrors`.


## rules() Helper (MagicStatefulViewState)

Available inside `MagicStatefulViewState`. Bridges Magic `Rule` objects to Flutter's `FormField.validator` signature. Automatically overlays server-side errors from the controller.

```dart
String? Function(R?) rules<R>(
  List<Rule> validationRules, {
  required String field,
  Map<String, dynamic>? extraData,
})
```

Use this for the `validator:` property of `WFormInput`, `WFormSelect`, etc.


## FormValidator.rules() (standalone)

Use outside `MagicStatefulViewState` — in standard `State` classes or anywhere a controller reference must be passed explicitly.

```dart
static String? Function(T?) rules<T>(
  List<Rule> rules, {
  String field = 'field',
  Map<String, dynamic>? extraData,
  MagicController? controller,
})
```

```dart
WFormInput(
  controller: _email,
  validator: FormValidator.rules(
    [Required(), Email()],
    field: 'email',
    controller: controller,
  ),
)
```


## Validator.make()

The core engine for imperative validation, typically used inside controllers or services.

```dart
static Validator make(
  Map<String, dynamic> data,
  Map<String, List<Rule>> rules,
)
```

```dart
final validator = Validator.make(
  {'email': 'test', 'password': ''},
  {'email': [Required(), Email()], 'password': [Required(), Min(8)]},
);

if (validator.fails()) {
  print(validator.errors()); // {'email': '...', 'password': '...'}
}

// Or validate and throw:
try {
  final validated = validator.validate(); // returns only fields with rules
} on ValidationException catch (e) {
  print(e.errors);
}
```

### API Surface

| Method | Returns | Notes |
|--------|---------|-------|
| `fails()` | `bool` | Runs validation; returns true if any rule fails |
| `passes()` | `bool` | Inverse of `fails()` |
| `errors()` | `Map<String, String>` | Map of field name to first error message |
| `validate()` | `Map<String, dynamic>` | Returns only validated fields on success; throws `ValidationException` on failure |


## ValidatesRequests Mixin

Mix into a `MagicController` to gain controller-side validation and server error handling.

```dart
class AuthController extends MagicController with ValidatesRequests { ... }
```

| Member | Signature | Purpose |
|--------|-----------|---------|
| `validationErrors` | `Map<String, String>` | Current validation errors, keyed by field name |
| `validate(data, rules)` | `Map<String, dynamic>` | Run rules; throws `ValidationException` and populates `validationErrors` |
| `setErrorsFromResponse(response)` | `void` | Populate field errors from a `MagicResponse` (Laravel 422 format) |
| `handleApiError(response, {fallback})` | `void` | Handles 422 (sets field errors) and other errors (sets generic error) automatically |
| `hasError(field)` | `bool` | True if `field` has a validation error |
| `getError(field)` | `String?` | Returns error message for `field`, or null |
| `firstError` | `String?` | First error message in the bag, or null |
| `hasErrors` | `bool` | True if there are any validation errors |
| `clearErrors()` | `void` | Clear all validation errors and notify listeners |
| `clearFieldError(field)` | `void` | Clear a single field's error and notify listeners |

### setErrorsFromResponse

Parses the Laravel 422 JSON format `{"errors": {"field": ["message"]}}` from a `MagicResponse` and populates `validationErrors`.

```dart
final response = await Http.post('/register', data: form.data);
if (response.isValidationError) {
  setErrorsFromResponse(response);
  return;
}
```


## Built-in Rules

| Rule | Constructor | Validates |
|------|-------------|-----------|
| `Required` | `Required()` | Not null; non-empty string/list/map; `true` for bools |
| `Email` | `Email()` | Valid email format (`local@domain.tld`) |
| `Min` | `Min(num n)` | String length >= n, num value >= n, or list size >= n |
| `Max` | `Max(num n)` | String length <= n, num value <= n, or list size <= n |
| `Confirmed` | `Confirmed()` | Value matches `{field}_confirmation` key in data |
| `Same` | `Same(String other, {String Function()? valueGetter})` | Value matches `other` field; use `valueGetter` for live Flutter controller values |
| `Accepted` | `Accepted()` | Value is `true`, `1`, `'1'`, `'yes'`, `'on'`, or `'true'` (case-insensitive) |

**Same with valueGetter (recommended for Flutter forms):**

```dart
WFormInput(
  controller: _passwordConfirm,
  validator: FormValidator.rules(
    [Required(), Same('password', valueGetter: () => _password.text)],
    field: 'password confirmation',
  ),
)
```

**Nullable fields:** Rules skip null/empty values unless `Required` is also in the list — `Email`, `Min`, `Max` all return `true` for null or empty inputs, deferring to `Required`.


## Custom Rules

Extend the abstract `Rule` class. Implement `passes()` and `message()`. Override `params()` if your message has placeholders beyond `:attribute`.

```dart
abstract class Rule {
  bool passes(String attribute, dynamic value, Map<String, dynamic> data);
  String message();
  Map<String, dynamic> params() => {};
}
```

```dart
class Lowercase extends Rule {
  @override
  bool passes(String attribute, dynamic value, Map<String, dynamic> data) {
    return value is String && value == value.toLowerCase();
  }

  @override
  String message() => 'validation.lowercase'; // translation key or raw string

  @override
  Map<String, dynamic> params() => {}; // placeholders beyond :attribute
}
```

`message()` can return a translation key (`'validation.required'`) or a raw string with `:attribute` placeholder. If `Lang.has(key)` is true, the key is resolved via `Lang.get(key, params)`; otherwise the string is used as-is with manual placeholder replacement.


## Server Error Mapping

Magic handles Laravel-style 422 error responses end-to-end:

1. **API call** returns 422 with `{"errors": {"email": ["Already taken."]}}`.
2. **Controller** calls `handleApiError(response)` (or `setErrorsFromResponse(response)` directly).
3. **`validationErrors`** is populated and `notifyListeners()` fires.
4. **`MagicForm`** detects `form.hasRelevantErrors` and switches to `AutovalidateMode.always`.
5. **`rules()` / `FormValidator.rules()`** checks `controller.hasError(field)` first; if found, returns the server message directly.
6. Error appears automatically under the form field with no extra widget code.


## Message i18n

Messages are resolved via the `Translator`.

- **Key pattern:** `validation.{rule_name}` (e.g., `validation.required`).
- **Placeholders:** `:attribute` (humanized field name), `:min`, `:max`, `:other`, etc.
- **Attribute humanization:** `first_name` becomes `"first name"`. Override via the `attributes` key in your validation JSON.

Example `assets/lang/en/validation.json`:

```json
{
  "required": "The :attribute field is required.",
  "email": "The :attribute must be a valid email address.",
  "min": {
    "string": "The :attribute must be at least :min characters.",
    "numeric": "The :attribute must be at least :min."
  },
  "attributes": {
    "email": "email address"
  }
}
```


## Full Form Workflow Example

```dart
import 'package:magic/magic.dart';

class RegisterView extends MagicStatefulView<AuthController> {
  const RegisterView({super.key});

  @override
  State<RegisterView> createState() => _RegisterViewState();
}

class _RegisterViewState
    extends MagicStatefulViewState<AuthController, RegisterView> {
  // 1. Init: declare form fields with type-inferred initial values
  late final form = MagicFormData({
    'name': '',
    'email': '',
    'password': '',
    'password_confirmation': '',
    'accept_terms': false,
  }, controller: controller);

  @override
  void onClose() => form.dispose(); // always dispose

  @override
  Widget build(BuildContext context) {
    // 2. Bind: wrap with MagicForm — handles formKey + autovalidation
    return MagicForm(
      formData: form,
      child: WDiv(
        className: 'flex flex-col gap-4',
        children: [
          WFormInput(
            controller: form['name'],
            validator: rules([Required()], field: 'name'),
          ),
          WFormInput(
            controller: form['email'],
            validator: rules([Required(), Email()], field: 'email'),
          ),
          WFormInput(
            controller: form['password'],
            type: InputType.password,
            validator: rules([Required(), Min(8)], field: 'password'),
          ),
          WFormInput(
            controller: form['password_confirmation'],
            type: InputType.password,
            validator: rules(
              [
                Required(),
                Same(
                  'password',
                  valueGetter: () => form.get('password'),
                ),
              ],
              field: 'password_confirmation',
            ),
          ),
          WFormCheckbox(
            value: form.value<bool>('accept_terms'),
            onChanged: (v) => form.setValue('accept_terms', v),
            validator: rules([Accepted()], field: 'accept_terms'),
          ),
          // 5. Handle errors: processingListenable for form-scoped loading
          MagicBuilder<bool>(
            listenable: form.processingListenable,
            builder: (isProcessing) => WButton(
              isLoading: isProcessing,
              onTap: _submit,
              child: WText(trans('auth.register')),
            ),
          ),
        ],
      ),
    );
  }

  // 3. Validate → 4. Process → handle server errors
  Future<void> _submit() async {
    if (!form.validate()) return; // client-side gate

    await form.process(() async {
      final response = await Http.post('/register', data: form.data);

      if (response.successful) {
        Route.to('/dashboard');
        return;
      }

      // 6. Handle errors: maps 422 field errors back to form
      controller.handleApiError(response);
    });
  }
}
```


## Gotchas

- `form['field']` **only** returns `TextEditingController`. For bools and other types, use `form.value<T>('field')`.
- `form.validate()` clears existing server-side errors on the controller before running client-side checks.
- `form.process()` throws `StateError` if called while already processing — guard concurrent submissions.
- `hasRelevantErrors` prevents cross-form error leakage when multiple forms share one controller.
- `rules()` is bound to `MagicStatefulViewState`. Use `FormValidator.rules()` in standard `State` classes.
- `Confirmed` looks for `{field}_confirmation` in form data. `Same` requires an explicit field name and supports `valueGetter` for live values.
- `Accepted` accepts `true`, `1`, `'1'`, `'yes'`, `'on'`, `'true'` — use it for terms checkboxes, not `Required`.
- Always call `form.dispose()` in `onClose()` to prevent memory leaks.
