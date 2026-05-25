# Magic Framework: Code Templates

Full annotated templates for common Magic framework patterns. Use as copy-paste starting points.

## Contents

- [Model](#model)
- [Controller](#controller)
- [View (Stateless)](#view-stateless)
- [View (Stateful with Form)](#view-stateful-with-form)
- [Responsive View](#responsive-view)
- [MagicFormData API](#magicformdata-api)
- [Service Provider](#service-provider)
- [Middleware](#middleware)

---

## Model

```dart
import 'package:magic/magic.dart';

class User extends Model with HasTimestamps, InteractsWithPersistence {
    @override String get table => 'users';
    @override String get resource => 'users';

    @override
    List<String> get fillable => [
        'name',
        'email',
        'avatar_url',
    ];

    @override
    Map<String, String> get casts => {
        'settings': 'json',
        'is_active': 'bool',
        'created_at': 'datetime',
        'updated_at': 'datetime',
    };

    @override
    Map<String, Model Function()> get relations => {
        'company': Company.new,
        'posts': Post.new,
    };

    // Typed getters/setters
    int? get id => get<int>('id');
    String? get name => get<String>('name');
    set name(String? v) => set('name', v);
    String? get email => get<String>('email');
    set email(String? v) => set('email', v);
    String? get avatarUrl => get<String>('avatar_url');
    Carbon? get createdAt => get<Carbon>('created_at');

    // Relations
    Company? get company => getRelation<Company>('company');
    List<Post> get posts => getRelations<Post>('posts');

    // Static query methods
    static User fromMap(Map<String, dynamic> map) {
        return User()..setRawAttributes(map, sync: true)..exists = true;
    }

    static Future<User?> find(dynamic id) =>
        InteractsWithPersistence.findById<User>(id, User.new);

    static Future<List<User>> all() =>
        InteractsWithPersistence.allModels<User>(User.new);
}
```

**Supported casts**: `datetime` (Carbon), `json` (Map), `bool`, `int`, `double`.

**Hybrid persistence**: `save()` calls API first, then syncs to local SQLite. `find()` checks local first, falls back to API, syncs result to local.

---

## Controller

```dart
import 'package:magic/magic.dart';

class UserController extends MagicController
    with MagicStateMixin<bool>, ValidatesRequests {
    static UserController get instance =>
        Magic.findOrPut(UserController.new);

    final usersNotifier = ValueNotifier<List<User>>([]);

    @override
    void onInit() {
        super.onInit();
        loadUsers();
    }

    Future<void> loadUsers() async {
        setLoading();
        try {
            final users = await User.all();
            usersNotifier.value = users;
            setSuccess(true);
        } catch (e) {
            Log.error('Failed to load users', e);
            setError(trans('errors.network_error'));
        }
    }

    Future<void> store(Map<String, dynamic> data) async {
        setLoading();
        clearErrors();
        final response = await Http.post('/users', data: data);
        if (response.successful) {
            Magic.toast(trans('users.created'));
            MagicRoute.to('/users');
            return;
        }
        handleApiError(response, fallback: trans('users.create_failed'));
    }
}
```

**renderState**: Declarative UI based on controller status:
```dart
controller.renderState(
    (data) => SuccessWidget(data),
    onLoading: LoadingWidget(),
    onError: (msg) => ErrorWidget(msg),
    onEmpty: EmptyWidget(),
)
```

**fetchList/fetchOne**: Auto-manages loading/success/error state transitions:
```dart
class ProjectController extends MagicController with MagicStateMixin<List<Project>> {
    Future<void> load() => fetchList('projects', Project.fromMap);
}
```

---

## View (Stateless)

```dart
import 'package:magic/magic.dart';

class UserListView extends MagicView<UserController> {
    const UserListView({super.key});

    @override
    Widget build(BuildContext context) {
        return Scaffold(
            body: controller.renderState(
                (_) => MagicBuilder<List<User>>(
                    listenable: controller.usersNotifier,
                    builder: (users) => ListView.builder(
                        itemCount: users.length,
                        itemBuilder: (_, i) => WText(users[i].name ?? ''),
                    ),
                ),
                onLoading: const Center(child: CircularProgressIndicator()),
                onError: (msg) => Center(child: WText(msg)),
            ),
        );
    }
}
```

---

## View (Stateful with Form)

```dart
import 'package:magic/magic.dart';

class LoginView extends MagicStatefulView<AuthController> {
    const LoginView({super.key});

    @override
    State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState
    extends MagicStatefulViewState<AuthController, LoginView> {
    late final form = MagicFormData({
        'email': '',
        'password': '',
    }, controller: controller);

    @override
    void onClose() => form.dispose();

    @override
    Widget build(BuildContext context) {
        return Scaffold(
            body: MagicForm(
                formData: form,
                child: Column(
                    children: [
                        WFormInput(
                            controller: form['email'],
                            validator: rules(
                                [Required(), Email()],
                                field: 'email',
                            ),
                        ),
                        WFormInput(
                            controller: form['password'],
                            type: WFormInputType.password,
                            validator: rules(
                                [Required(), Min(8)],
                                field: 'password',
                            ),
                        ),
                        MagicBuilder<bool>(
                            listenable: form.processingListenable,
                            builder: (isProcessing) => WButton(
                                isLoading: isProcessing,
                                onTap: _submit,
                                child: WText(trans('auth.login')),
                            ),
                        ),
                    ],
                ),
            ),
        );
    }

    void _submit() {
        if (!form.validate()) return;
        form.process(() => controller.login(
            email: form.get('email'),
            password: form.get('password'),
        ));
    }
}
```

---

## Responsive View

```dart
import 'package:magic/magic.dart';

class DashboardView extends MagicResponsiveView<DashboardController> {
    const DashboardView({super.key});

    @override
    Widget phone(BuildContext context) => const MobileDashboard();

    @override
    Widget tablet(BuildContext context) => const TabletDashboard();

    @override
    Widget desktop(BuildContext context) => const DesktopDashboard();

    @override
    Widget watch(BuildContext context) => const WatchDashboard();
}
```

Breakpoints: watch < 320px, phone < sm (640px), tablet < lg (1024px), desktop >= lg.

`MagicResponsiveViewExtended<T>` provides all Wind breakpoints: `xs()`, `sm()`, `md()`, `lg()`, `xl()`, `xxl()`.

---

## MagicFormData API

```dart
late final form = MagicFormData({
    'name': 'John Doe',           // String -> TextEditingController
    'email': '',                  // String -> TextEditingController
    'accept_terms': false,        // bool -> ValueNotifier<bool>
    'avatar': null as MagicFile?, // Other -> ValueNotifier<MagicFile?>
}, controller: controller);

// Access text fields
form['email']                     // TextEditingController
form.get('email')                 // String (trimmed)
form.set('email', 'new@val.com') // Set text value

// Access value fields
form.value<bool>('accept_terms')        // Read
form.setValue('accept_terms', true)      // Write

// Collect all data
form.data                         // Map<String, dynamic> (all fields, texts trimmed)
form.validated()                  // Validates first, returns {} if invalid

// Processing state
form.isProcessing                 // bool getter
form.processingListenable         // ValueListenable<bool> for MagicBuilder
await form.process(() => controller.submit(form.data)); // Auto-manages processing state

// Cleanup
form.dispose()                    // Always call in onClose()
```

---

## Service Provider

```dart
import 'package:magic/magic.dart';

class PaymentServiceProvider extends ServiceProvider {
    PaymentServiceProvider(super.app);

    @override
    void register() {
        // Sync IoC bindings only. No async, no resolving other services.
        app.singleton('payment', () => StripePaymentService());
    }

    @override
    Future<void> boot() async {
        // Async. May resolve other services.
        final payment = Magic.make<PaymentService>('payment');
        await payment.initialize();
    }
}
```

---

## Middleware

```dart
import 'package:magic/magic.dart';

class EnsureAuthenticated extends MagicMiddleware {
    @override
    Future<void> handle(void Function() next) async {
        if (Auth.check()) {
            next(); // Proceed to next middleware or route
        } else {
            MagicRouter.instance.setIntendedUrl(
                MagicRouter.instance.currentLocation ?? '/',
            );
            MagicRoute.replace('/login');
            // Do NOT call next() -- halts pipeline
        }
    }
}
```
