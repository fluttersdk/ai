# Forms & Validation

Comprehensive guide to handling form state, validation rules, and server-side error mapping in the Magic framework.


## MagicFormData

The central manager for form state. It automatically infers the correct controller type based on the initial value provided in the map.

- `String` -> `TextEditingController`
- `bool`, `MagicFile?`, or other types -> `ValueNotifier<T>`

```dart
late final form = MagicFormData({
  'name': 'John Doe',          // String → TextEditingController
  'email': '',                  // String → TextEditingController
  'accept_terms': false,        // bool → ValueNotifier<bool>
  'avatar': null as MagicFile?, // MagicFile? → ValueNotifier<MagicFile?>
}, controller: controller);
```

### API Surface

| Method | Signature | Purpose |
|--------|-----------|---------|
| `form['field']` | `TextEditingController` | Get text controller (String fields only) |
| `form.value<T>('field')` | `T` | Get typed value from ValueNotifier (non-text) |
| `form.setValue('field', value)` | `void` | Set value for a non-text field |
| `form.get('field')` | `String` | Get trimmed text from controller |
| `form.set('field', 'text')` | `void` | Set text value in controller |
| `form.data` | `Map<String, dynamic>` | Export all values (text fields are auto-trimmed) |
| `form.validate()` | `bool` | Run client-side validation (clears server errors first) |
| `form.validated()` | `Map<String, dynamic>` | Returns `data` if valid, otherwise empty Map |
| `form.fieldNames` | `Set<String>` | All registered field names |
| `form.hasRelevantErrors` | `bool` | True if controller has server errors matching these fields |
| `form.dispose()` | `void` | Dispose all internal controllers and notifiers |

**Auto-clear behavior:** When a user types into a field managed by `MagicFormData`, any existing server-side error for that specific field is automatically cleared from the controller.

## MagicForm Widget

A wrapper around Flutter's `Form` that integrates with `MagicFormData`. It automatically handles form keys and controller scoping.

```dart
MagicForm(
  formData: form,  // Extracts formKey + controller automatically
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

**Smart Autovalidation:** `MagicForm` automatically switches its `AutovalidateMode` to `always` when the associated controller contains relevant server-side errors (checked via `form.hasRelevantErrors`).

## rules() Helper

Available inside `MagicStatefulViewState`. It bridges Magic's `Rule` objects to Flutter's `FormField.validator` signature.

```dart
String? Function(R?) rules<R>(
  List<Rule> validationRules, {
  required String field,
  Map<String, dynamic>? extraData,
})
```

It automatically checks the controller for server-side errors and overlays them on the field if client-side validation passes or isn't triggered yet. Use this for the `validator:` property of `WFormInput`, `WFormSelect`, etc.

## Validator.make()

The core engine for manual validation, typically used within controllers or services.

```dart
final validator = Validator.make(
  {'email': 'test', 'password': ''},
  {'email': [Required(), Email()], 'password': [Required(), Min(8)]},
);

if (validator.fails()) {
  print(validator.errors()); // {email: "The email format is invalid.", password: "The password field is required."}
}

// Or validate and throw:
// validator.validate(); // Throws ValidationException on failure
```

### API Surface

| Method | Returns | Notes |
|--------|---------|-------|
| `fails()` | `bool` | Returns true if any rule fails |
| `passes()` | `bool` | Returns true if all rules pass |
| `errors()` | `Map<String, String>` | Map of field names to their first error message |
| `validate()` | `Map<String, dynamic>` | Returns data if pass, throws `ValidationException` if fail |

## Built-in Rules

| Rule | Constructor | Validates |
|------|-------------|-----------|
| **Required** | `Required()` | Not null, and if String, not empty |
| **Email** | `Email()` | Valid RFC email format |
| **Min** | `Min(int n)` | Min length (String) or min value (num) |
| **Max** | `Max(int n)` | Max length (String) or max value (num) |
| **Confirmed** | `Confirmed()` | Value must match `{field}_confirmation` in data |
| **Same** | `Same(String other)` | Value must match specific `other` field in data |
| **Accepted** | `Accepted()` | Value must be `true`, `'yes'`, or `1` |

**Nullable fields:** If a field is optional but needs validation when present, check for null/empty in your logic or allow the value to be empty if the rule allows it.

## Custom Rules

Extend the `Rule` base class to create domain-specific validation.

```dart
class Lowercase extends Rule {
  @override
  bool passes(String attribute, dynamic value, Map<String, dynamic> data) {
    return value is String && value == value.toLowerCase();
  }

  @override
  String message() => 'validation.lowercase'; // Translation key

  @override
  Map<String, dynamic> params() => {}; // Placeholders for the message
}
```

## Server Error Mapping

Magic seamlessly handles Laravel-style 422 error responses.

1. **API Call:** A request fails with 422 and JSON errors: `{"errors": {"email": ["Taken"]}}`.
2. **Handle Error:** Call `handleApiError(response)` inside your controller (using `ValidatesRequests` mixin).
3. **Auto-Mapping:**
   - For 422: `setErrorsFromResponse(response)` is called.
   - For others: `setError(msg)` is called.
4. **UI Update:** `MagicForm` detects `hasRelevantErrors` and enables autovalidate.
5. **Rule Bridge:** The `rules()` helper finds the error in `controller.validationErrors` for the field.
6. **Display:** The error message appears automatically under the form field.

## Message i18n

Messages are resolved via the `Translator`.

- **Key pattern:** `validation.{rule_name}` (e.g., `validation.required`).
- **Placeholders:** `:attribute` (humanized field name), `:min`, `:max`, etc.
- **Attribute Humanization:** `first_name` becomes "first name". Overrides go in `validation.json` under the `attributes` key.

Example `assets/lang/en/validation.json`:
```json
{
  "required": "The :attribute field is required.",
  "attributes": {
    "email": "email address"
  }
}
```

## Full Form Example

```dart
class RegisterView extends MagicStatefulView<AuthController> {
  const RegisterView({super.key});

  @override
  State<RegisterView> createState() => _RegisterViewState();
}

class _RegisterViewState extends MagicStatefulViewState<AuthController, RegisterView> {
  late final form = MagicFormData({
    'name': '',
    'email': '',
    'password': '',
    'password_confirmation': '',
    'accept_terms': false,
  }, controller: controller);

  @override
  void onClose() => form.dispose();

  @override
  Widget build(BuildContext context) {
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
            validator: rules([Required(), Confirmed()], field: 'password_confirmation'),
          ),
          WFormCheckbox(
            value: form.value<bool>('accept_terms'),
            onChanged: (v) => form.setValue('accept_terms', v),
          ),
          WButton(
            onTap: controller.isLoading ? null : _submit,
            isLoading: controller.isLoading,
            child: WText(trans('auth.register')),
          ),
        ],
      ),
    );
  }

  void _submit() {
    if (!form.validate()) return;
    controller.doRegister(form.data);
  }
}
```

## Gotchas

- `form['field']` **only** returns `TextEditingController`. For bools/files, use `form.value<T>('field')`.
- `form.validate()` manually clears existing server-side errors before running client-side checks.
- `hasRelevantErrors` is critical for avoiding error leakage when multiple forms share one controller.
- `rules()` helper is bound to `MagicStatefulViewState`. Use `FormValidator.rules()` if working in a standard `State`.
- The `Confirmed` rule specifically looks for a field named `{field}_confirmation` in the form data.
- Always call `form.dispose()` in `onClose()` to prevent memory leaks from controllers/notifiers.
