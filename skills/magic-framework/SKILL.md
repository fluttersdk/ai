---
name: magic-framework
description: "Write correct, idiomatic code in a Flutter app that depends on the `magic` framework (Laravel-inspired: IoC container, 18 facades, Eloquent-style ORM, service providers, reactive controllers, GoRouter routing, validation, auth, broadcasting). Use whenever code imports `package:magic/magic.dart` or `package:magic/testing.dart`, or the work touches Magic.init, MagicApp, a facade (Auth/Http/Cache/DB/Echo/Event/Gate/Config/Lang/Launch/Log/Pick/MagicRoute/Schema/Session/Storage/Vault/Crypt), a Model, MagicController, a MagicView, MagicFormData, FormRequest, a ServiceProvider, a migration, or the artisan make:* CLI. UI styling is Wind (separate wind-ui skill). Do NOT use for plain Flutter or Wind-only work with no magic import."
when_to_use: "Use proactively when editing or scaffolding a magic app: Magic.init / a facade / a Model / a MagicController or MagicView / a form (MagicFormData, FormRequest, Validator) / a ServiceProvider / a route or MagicMiddleware / a migration / MagicStateMixin + RxStatus + fetchList / Session flash + old() + trans() / testing with MagicTest + Http.fake/Auth.fake / the artisan make:* CLI / the magic_deeplink, magic_notifications, magic_social_auth, magic_starter, or magic_devtools plugins. Trigger even when the user does not say the word 'magic'. Do NOT trigger for plain Flutter or Wind-only UI with no package:magic import."
version: 0.1.1
---

<!-- magic 0.0.x (master) | Skill v0.1.1 (2026-06-25). API surface verified against lib/src. -->

# Magic Framework

Laravel-inspired Flutter framework: IoC container, 18 facades, Eloquent-style ORM, service providers, reactive controllers, and GoRouter-backed routing. This skill makes an agent write code that an experienced magic developer would write: facade-first, IoC-resolved, reactive, and verified against the real API in `lib/src`. All visual styling is handled by Wind (load the `wind-ui` skill for className work); this skill owns architecture, data, navigation, auth, and testing.

The host app already depends on `package:magic/magic.dart`. The accuracy contract for this skill: every API you write must exist in `lib/src`. When unsure of a signature, open the source or the matching `doc/**` page rather than guessing; magic is pre-1.0 and the surface is exact, not approximate.

## 0. Before writing code in this project

Three checks, each pays off across the whole session.

1. **Read `lib/main.dart` and `lib/config/app.dart`.** Note the `providers` list and its ORDER (AppServiceProvider must precede AuthServiceProvider so `setUserFactory` is set before auth restore runs), and whether `configFactories` or `configs` is used.
2. **Scan one existing controller + view pair in `lib/app/`** for the project's idioms: the singleton accessor shape, how views resolve controllers, how forms are wired. Match the surrounding code, do not invent a dialect.
3. **CLI invocation.** Magic ships an `artisan` executable, so every command runs as `dart run magic:artisan <cmd>` from any app that depends on magic (no package-name placeholder, no global activate).

## 1. Core Laws

Hard constraints for every line of magic code.

1. **`await Magic.init()` first.** It must be awaited in `main()` before any facade call and before `runApp()`. Never `.then()`; providers are not booted until the future completes.
2. **Facade-first.** Reach for `Auth`, `Http`, `Config`, `Cache`, `DB`, `Schema`, `Log`, `Event`, `Echo`, `Lang`, `MagicRoute`, `Gate`, `Session`, `Vault`, `Storage`, `Pick`, `Crypt`, `Launch`. Resolve from the container manually (`Magic.make<T>('key')`) only when extending the framework.
3. **Controllers are singletons.** `static X get instance => Magic.findOrPut(X.new);` is the canonical accessor. Views resolve controllers via `Magic.find<T>()` (automatic in `MagicView`), never through constructors.
4. **IoC over `new` for services.** Bind in a provider's `register()`, resolve via the facade or `Magic.make<T>('key')`. Do not scatter `Service()` construction across the app.
5. **Provider discipline.** `register()` is synchronous and is where routes and bindings go. `boot()` is async and may resolve other services; set `Auth.manager.setUserFactory(...)` here.
6. **Reactive state, not setState.** Controllers extend `MagicController` (a `ChangeNotifier`); state flows through `MagicStateMixin` + `RxStatus`. Use `refreshUI()` (guarded `notifyListeners`), `setLoading/setSuccess/setError/setEmpty`, and `MagicBuilder` for sections. Local `setState` belongs only to genuine widget-local UI state inside a `MagicStatefulView`.
7. **Typed attribute access.** Models use `get<T>('key')` and `set('key', v)`, never raw `getAttribute`. Declare `fillable`; use `fill(validated, strict: true)` after validation so schema drift throws `MassAssignmentException`.
8. **Context-free navigation and feedback.** `MagicRoute.to/back/replace`, `Magic.snackbar/toast/dialog/confirm/loading`. Never depend on a `BuildContext` for navigation or feedback. Never navigate or fetch inside `build()`.
9. **Validate at the boundary.** `MagicFormData` for forms, `FormRequest` for complex payloads, `Validator` for ad hoc checks. Surface server errors with `handleApiError(response)` (from the `ValidatesRequests` mixin).
10. **Trailing commas, multi-line collections.** Always. Match the project's existing style.

## 2. Bootstrap

```dart
import 'package:magic/magic.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Magic.init(
    configFactories: [
      () => appConfig,      // factories: evaluated AFTER Env.load(), so env() works inside them
      () => authConfig,
      () => networkConfig,
    ],
  );
  runApp(MagicApplication(title: 'My App'));
}
```

Real lifecycle (from `lib/src/foundation/magic.dart`): `Env.load()` then `configFactories` evaluate, then `MagicApp.init` (config merge), then the web URL strategy is applied if `routing.url_strategy == 'path'`, then core bindings, then providers `register()` (sync), then `await boot()` (async), then the router pre-builds, then ready.

Use `configFactories` (not `configs`) whenever a config value reads `Env.get()`: `configs` is evaluated before Env is loaded. `MagicApplication` accepts `title`, `titleSuffix`, `windTheme`, `themeMode`, `locale`, `localizationsDelegates`, `onThemeChanged`, `onInit`, `initialRoute`.

## 3. Mental model: Laravel to magic (and where it diverges)

Magic mirrors Laravel's vocabulary; it diverges wherever Dart lacks PHP's runtime reflection or where the target is a Flutter client, not an HTTP server. Internalize the divergences; they fail silently (null, not an exception).

| Laravel | magic | Note |
|---|---|---|
| `Container` autowiring, `__callStatic` facades | string-keyed factory closures + explicit static facade stubs | No reflection, no autowiring; an unregistered key throws at runtime |
| `ServiceProvider::boot()` (sync) | `boot()` is `async` | await it; dropped futures leave a half-booted provider |
| `Router::resource` returns Responses | routes resolve to WIDGETS; middleware runs on NAVIGATION | not an HTTP request cycle |
| controllers = per-request handlers | controllers = reactive `ChangeNotifier` singletons | live for the session, drive UI via `RxStatus` |
| Eloquent lazy load + `with()` eager load | relations cast from nested API Maps, cached on first access | NO lazy load, NO `with()`, NO query-builder relations: if the payload did not nest it, it is null |
| `Gate`/`Policy` server-authoritative | `Gate`/`Policy` run CLIENT-side, advisory only | always re-authorize on the backend |
| server sessions | tokens in `Vault` (secure storage), cache-first restore | `Auth.restore()` on cold start |
| `Encrypter` AES + HMAC/AEAD JSON envelope | AES-256-CBC `iv:ciphertext` (base64), no MAC | not cross-decryptable with Laravel's `Crypt` |

The five assumptions a Laravel developer gets wrong most: (1) the container autowires (it does not, register explicitly); (2) `user.posts` lazy-loads (it does not, embed in the payload); (3) `Gate.allows()` is real security (advisory only); (4) `with()` exists (it does not); (5) `boot()` is sync (it is async). Full mapping with Laravel source citations: `${CLAUDE_SKILL_DIR}/references/bootstrap-lifecycle.md`.

## 4. Facades and the container

### IoC container (the methods an app uses)

| Call | Purpose |
|---|---|
| `Magic.bind('key', () => Svc(), {shared})` | factory binding (new instance per resolve; `shared: true` caches) |
| `Magic.singleton('key', () => Svc())` | lazy shared singleton |
| `Magic.make<T>('key')` | resolve a service (throws if unbound) |
| `Magic.bound('key')` | is the key registered |
| `Magic.put<T>(ctrl)` / `Magic.find<T>()` / `Magic.findOrPut<T>(T.new)` | controller register / resolve / get-or-create |
| `Magic.delete<T>()` / `Magic.isRegistered<T>()` | controller remove / check |
| `Magic.flush()` / `MagicApp.reset()` | clear controllers / full container reset (testing) |

### The 18 facades

`Config` and `Gate` resolve through their managers (no plain IoC key); the rest bind to the key shown.

| Facade | Key | Surface you reach for (all verified in `lib/src/facades/`) |
|---|---|---|
| `Auth` | `auth` | `login(data, user)`, `logout()`, `check()`, `guest` (getter), `user<T>()`, `id()`, `getToken()`, `refreshToken()`, `restore()`, `registerModel<T>(factory)`, `guard([name])`, `stateNotifier`, `manager`, `fake({user})` |
| `Http` | `network` | `get/post/put/delete`, `upload`, RESTful `index/show/store/update/destroy`, `fake([stubs])`, `response([data, code])`, `unfake()`. NO `patch` |
| `Config` | (manager) | `get<T>`, `getOrFail<T>`, `set`, `has`, `all`, `merge`, `prepend`, `push`, `forget`, `flush`, `repository` |
| `Cache` | `cache` | `put(key, value, {ttl})`, `get`, `has`, `forget`, `flush`, `remember<T>(key, ttl, cb)`, `fake()` |
| `DB` | (lazy) | `table(name)` (query builder), `select/statement/insert/update/delete` (raw SQL), `transaction(cb)`, `beginTransaction/commit/rollback` |
| `Schema` | (manager) | `create(table, (b){})`, `table`, `drop`, `dropIfExists`, `hasTable`, `hasColumn`, `getColumns`, `rename` |
| `Log` | `log` | `info/error/warning/debug/notice/critical/alert/emergency`, `log(level, msg)`, `channel(name)`, `fake()` |
| `Event` | (dispatcher) | `dispatch(MagicEvent)`; register listeners with `EventDispatcher.register(Type, [() => Listener()])` |
| `Echo` | `broadcasting` | `channel/private/join`, `listen`, `leave`, `connect/disconnect`, `socketId`, `connectionState`, `onReconnect`, `addInterceptor`, `manager`, `fake()` |
| `MagicRoute` | (router) | `page`, `group`, `layout`, `resource(name, ctrl, {only, except})`, `to`, `toNamed`, `push`, `back({fallback})`, `replace`, `setTitle`, `currentTitle`, `config` |
| `Gate` | (manager) | `define`, `before`, `allows`, `denies`, `allowsAny(list)`, `allowsAll(list)`, `has`, `abilities`, `flush` |
| `Session` | (store) | `flash(map)`, `flashErrors(map)`, `old(field, [fallback])`, `oldRaw`, `error(field)`, `errors(field)`, `hasError`, `hasFlash`, `tick()` |
| `Lang` | (translator) | `get(key, [replace])`, `has`, `current`, `isLoaded`, `supportedLocales`, `setLocale`, `detectLocale`, `detectAndSetLocale`, `setSupportedLocales`, `addListener/removeListener`, `delegate` |
| `Vault` | `vault` | `put(key, value)`, `get`, `delete`, `flush`, `fake([initial])` |
| `Storage` | (manager) | `disk([name])`, `put`, `get`, `getFile`, `exists`, `delete`, `url`, `download`, `setManager`, `flush` |
| `Pick` | (static) | `image`, `images`, `camera`, `media`, `video`, `recordVideo`, `file`, `files`, `directory`, `saveFile` |
| `Crypt` | `encrypter` | `encrypt`, `decrypt`, `encryptWithDeviceKey`, `decryptWithDeviceKey`, `hasDeviceKey`, `generateDeviceKey`, `clearDeviceKey` |
| `Launch` | `launch` | `url(u, {mode})`, `email`, `phone`, `sms`, `canLaunch` |

Global helper functions exist and are idiomatic: `env<T>(key, [default])`, `trans(key, [replace])`, `old(field, [fallback])`, `error(field)`, `carbonNow()`, `carbonToday()`, `carbonParse(s)`. Full per-facade signatures: `${CLAUDE_SKILL_DIR}/references/facades-api.md`.

## 5. Canonical patterns

Full annotated templates: `${CLAUDE_SKILL_DIR}/references/templates.md`.

### Model

```dart
class User extends Model with HasTimestamps, InteractsWithPersistence {
  @override String get table => 'users';
  @override String get resource => 'users';
  @override List<String> get fillable => ['name', 'email'];
  @override bool get useLocal => true;   // OPT IN to SQLite; default is API-only (false)
  @override Map<String, dynamic> get casts => {
    'created_at': 'datetime',                       // Carbon
    'settings': 'json',                             // Map or List
    'status': EnumCast(UserStatus.values),          // class-based cast
    'tags': ListCast(EnumCast(UserTag.values)),     // element-wise list cast
  };
  @override Map<String, Model Function()> get relations => {'company': Company.new};

  int? get id => get<int>('id');
  String? get name => get<String>('name');
  set name(String? v) => set('name', v);
  Company? get company => getRelation<Company>('company');   // from nested payload Map, not a query

  static User fromMap(Map<String, dynamic> map) =>
      User()..setRawAttributes(map, sync: true)..exists = true;
  static Future<User?> find(dynamic id) =>
      InteractsWithPersistence.findById<User>(id, User.new);
  static Future<List<User>> all() =>
      InteractsWithPersistence.allModels<User>(User.new);
}
```

Casts: `datetime`, `json`, `bool`, `int`, `double` (string keys), plus class-based `CastsAttributes<T>` (`EnumCast(values, {strict})`, `ListCast(inner)`). `save()` is API-first then syncs to SQLite when `useLocal` is true. Relations are decoded from nested API Maps and cached on first access: there is no lazy load, no eager load, no `with()`.

### Controller + reactive state

```dart
class UserController extends MagicController
    with MagicStateMixin<List<User>>, ValidatesRequests {
  static UserController get instance => Magic.findOrPut(UserController.new);

  @override void onInit() { super.onInit(); load(); }

  Future<void> load() => fetchList('/users', User.fromMap);   // auto loading/success/error/empty

  Future<void> store(Map<String, dynamic> data) async {
    authorize('create-user');           // throws AuthorizationException if Gate denies
    clearErrors();
    final response = await Http.post('/users', data: data);
    if (response.successful) { Magic.toast(trans('users.created')); MagicRoute.to('/users'); return; }
    handleApiError(response, fallback: trans('users.create_failed'));   // 422 -> field errors
  }
}
```

`fetchList<E>(url, fromMap, {dataKey: 'data', query, headers})` and `fetchOne(...)` drive the `RxStatus` transitions. In the view, `controller.renderState((data) => ..., onLoading: ..., onError: (msg) => ..., onEmpty: ...)` renders per state. `MagicResponse` exposes `.data` (the payload, never `.body`), `.successful`, `.failed`, `.errors` (parses Laravel `{"errors": {field: [..]}}`), `.firstError`, `.dataAs<T>()`.

### Views

```dart
// Stateless: auto-resolves its controller via Magic.find<T>() and rebuilds on controller change
class UserListView extends MagicView<UserController> {
  const UserListView({super.key});
  @override Widget build(BuildContext context) => controller.renderState(
    (users) => ListView(children: [for (final u in users) Text(u.name ?? '')]),
    onLoading: const Center(child: CircularProgressIndicator()),
    onError: (msg) => Center(child: Text(msg)),
  );
}

// Stateful: forms, TextEditingController, animations. Note the type-param ORDER <Controller, View>.
class LoginView extends MagicStatefulView<AuthController> { const LoginView({super.key}); }
class _LoginViewState extends MagicStatefulViewState<AuthController, LoginView> {
  late final form = MagicFormData({'email': '', 'password': ''}, controller: controller);
  @override void onClose() => form.dispose();   // always dispose
  void _submit() => form.process(() => controller.login(form.data));
}

// Responsive
class DashboardView extends MagicResponsiveView<DashboardController> {
  @override Widget phone(BuildContext context) => const MobileDashboard();
  @override Widget tablet(BuildContext context) => const TabletDashboard();
  @override Widget desktop(BuildContext context) => const DesktopDashboard();
}
```

`MagicResponsiveViewExtended` adds `xs/sm/md/lg/xl/xxl`. `MagicCan(ability: 'edit-post', arguments: post, child: ..., placeholder: ...)` and `MagicCannot` gate widgets on `Gate`.

### MagicFormData

```dart
final form = MagicFormData({
  'email': '',           // String  -> TextEditingController
  'accept_terms': false, // non-String -> ValueNotifier<T>
}, controller: controller);

form['email']                       // TextEditingController
form.get('email')                   // trimmed String
form.value<bool>('accept_terms')    // read ValueNotifier
form.setValue('accept_terms', true) // write ValueNotifier
form.data                           // Map<String, dynamic> of all fields
form.validate()                     // bool; on failure auto-flashes form.data (input only) to Session
form.process(() => submit())        // toggles isProcessing/processingListenable; throws if already processing
form.dispose()                      // in onClose()
```

### FormRequest (complex payloads)

```dart
class StoreUserRequest extends FormRequest {
  @override bool authorize() => Gate.allows('create-user');
  @override Map<String, dynamic> prepared(Map<String, dynamic> data) =>
      {...data, 'email': (data['email'] as String?)?.trim().toLowerCase()};
  @override Map<String, List<Rule>> rules() => {
    'name': [Required()],
    'email': [Required(), Email(), Unique('/users', field: 'email')],
    'password': [Required(), Min(8), Confirmed()],
  };
}

final validated = StoreUserRequest().validate(form.data);  // throws Authorization/ValidationException
final user = User()..fill(validated, strict: true);
await user.save();
```

Rules: `Required`, `Email`, `Min(n)`, `Max(n)`, `Confirmed`, `Same(other)`, `Accepted`, `In<T>(values)` (primitives), `InList<T extends Enum>(values, {caseInsensitive, wire})` (enums), `Unique(endpoint, {field, debounce})`. Async rules implement `AsyncRule.passesAsync`; run them with `Validator.make(data, rules).validateAsync()`. `Unique` debounces (400ms default), passes on network error, discards stale calls; swap the backend with `.via(resolver)`.

### Routing + resource

```dart
// In RouteServiceProvider.register() (NOT boot(): the router pre-builds during init)
MagicRoute.page('/dashboard', () => const DashboardPage()).title('Dashboard').middleware(['auth']);
MagicRoute.resource('users', UserRoutes());                 // index/create/show/edit
MagicRoute.resource('posts', PostRoutes(), only: ['index', 'show']);
```

`ResourceController` supplies `index()`, `create()`, `show(id)`, `edit(id)`; `resource()` wires `GET /name`, `/name/create`, `/name/:id`, `/name/:id/edit` with auto names `{name}.{method}`. Middleware extends `MagicMiddleware` (`handle(next)`, call `next()` to allow), registered with `Kernel.register('name', () => Mw())`. Read path/query params via `Request.route('id')` / `Request.query('q')`.

Session flash survives one navigation but `Session.tick()` is NOT automatic: wire it once at bootstrap on a router-delegate listener gated to actual location changes (see `${CLAUDE_SKILL_DIR}/references/routing-navigation.md`).

## 6. Testing

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:magic/testing.dart';   // separate barrel: fakes + MagicTest

void main() {
  MagicTest.init();   // registers setUpAll + setUp(MagicApp.reset + Magic.flush) + tearDown

  test('store creates a user', () async {
    Http.fake({'users': Http.response({'data': {'id': 1}}, 201)});
    final auth = Auth.fake(user: User.fromMap({'id': 1}));
    await UserController.instance.store({'name': 'A', 'email': 'a@b.co'});
    auth.assertLoggedIn();
  });
}
```

Six facades fake without any mock library: `Http.fake` (`FakeNetworkDriver`: `assertSent/assertNotSent/assertSentCount/assertNothingSent`), `Auth.fake` (`assertLoggedIn/assertLoggedOut/assertLoginAttempted/assertLoginCount`), `Cache.fake` (`assertHas/assertMissing/assertPut`), `Vault.fake` (`assertWritten/assertDeleted/assertContains/assertMissing`), `Log.fake` (`assertLogged/assertLoggedError/assertNothingLogged/assertLoggedCount`), `Echo.fake` (`assertConnected/assertDisconnected/assertSubscribed/assertNotSubscribed/assertInterceptorAdded`). Every `setUp` must reset the container (`MagicTest.init()` does this); skipping it leaks state and produces false passes. Full patterns: `${CLAUDE_SKILL_DIR}/references/testing-patterns.md`.

## 7. Common rationalizations (close the escape hatch)

| The shortcut the agent reaches for | Why it is wrong here |
|---|---|
| "I will just `new` the service / `Magic.make` inline in the view" | Bind in a provider, use the facade. Inline construction breaks IoC and test isolation. |
| "A plain `StatefulWidget` + `setState` is simpler" | The container resolves the controller and `RxStatus` drives rebuilds; a bare `StatefulWidget` cannot participate and loses state-reset between tests. Use `MagicView` / `MagicStatefulView`. |
| "I will load the relation with `with()` / a query" | No `with()`, no lazy load exists. Embed the relation in the API payload or fetch it and `set` it. |
| "`useLocal` defaults on, so `find()` reads SQLite" | `useLocal` defaults to FALSE (API-only). Override it to opt into local persistence. |
| "`Gate.allows()` passed, so the action is authorized" | Client-side Gate is advisory. The backend must re-authorize every write. |
| "I will pass the controller into the view constructor" | Views resolve controllers via `Magic.find<T>()`. Constructor injection is not how magic wires them. |
| "Flash will expire on its own after navigation" | `Session.tick()` is not automatic; wire it once at bootstrap or old input lingers. |
| "`Http.patch` for a partial update" | There is no `patch`. Use `put` (or `update(resource, id, data)`). |
| "Read `response.body`" | The payload is `response.data`. `.body` does not exist on `MagicResponse`. |
| "Put routes in `boot()`" | The router pre-builds during `init`, before `boot()`. Register routes in `register()`. |

## 8. Anti-patterns

| Wrong | Right | Why |
|---|---|---|
| `Magic.init().then(...)` | `await Magic.init()` | facades unusable before providers boot |
| `getAttribute('name')` | `get<String>('name')` | type-safe, null-safe |
| `response.body` | `response.data` | `.body` does not exist |
| `Http.patch(...)` | `Http.put(...)` / `Http.update(...)` | no `patch` verb |
| `configs: [appConfig]` reading `env()` | `configFactories: [() => appConfig]` | Env not loaded when `configs` evaluates |
| routes in `boot()` | routes in `register()` | router pre-builds before boot |
| `Auth.guest()` | `Auth.guest` | it is a bool getter |
| controller via constructor | `Magic.find<T>()` / `MagicView` | that is how magic resolves controllers |
| `Http.get()` or `MagicRoute.to()` in `build()` | call in `onInit()` or callbacks | no I/O or navigation during build |
| `user.fill(unvalidated)` | `user.fill(validated, strict: true)` | catches schema drift after validation |
| hand-rolled `if (!Gate.allows(...)) throw` | `authorize('ability')` in the controller | delegates to Gate, throws `AuthorizationException` |
| `FilePicker.platform.pickFiles()` | `Pick.image()` / `Pick.file()` (or `FilePicker.pickFiles()`) | file_picker v11 is a static API |
| four `MagicRoute.page()` for CRUD | `MagicRoute.resource(name, ctrl)` | auto-wires canonical routes + titles |
| `import 'package:fluttersdk_magic/...'` | `import 'package:magic/magic.dart'` | the package is `magic` |
| skipping reset in tests | `MagicTest.init()` (or `MagicApp.reset()` + `Magic.flush()` in `setUp`) | leaked state, false passes |

## 9. Pre-completion checklist

Before reporting a magic task done, verify (with evidence, not assumption):

- [ ] `dart analyze` on changed files: zero issues, zero warnings.
- [ ] `dart format .` produces no diff.
- [ ] Imports use `package:magic/magic.dart` (and `package:magic/testing.dart` for tests).
- [ ] Every facade method and signature you wrote exists in `lib/src` (you opened the source or the `doc/**` page when unsure).
- [ ] Controllers have the `static X get instance => Magic.findOrPut(X.new)` accessor; views extend the right base; `MagicStatefulViewState<Controller, View>` order is correct.
- [ ] `MagicFormData` is disposed in `onClose()`.
- [ ] `ValidatesRequests` is imported from `package:magic/magic.dart` (it lives in `src/concerns/`, not `http/`).
- [ ] Routes are registered in `register()`; routes have `.title(...)`.
- [ ] `configFactories` used (not `configs`) when values read `env()`.
- [ ] Tests reset the container in `setUp`; the post-change sync in the project's `CLAUDE.md` (CHANGELOG + doc/ + skill + example) is honored for `lib/` changes.

## 10. CLI

The magic CLI ships as an `artisan` executable in magic's `pubspec.yaml` (`executables: { artisan: }`, backed by `bin/artisan.dart`). Once magic is a dependency, run any command with `dart run magic:artisan <cmd>`. There is no `magic_cli` package and no global activation.

```bash
dart run magic:artisan magic:install                  # scaffold project structure
dart run magic:artisan magic:install --with-devtools   # + wire the Dusk/Telescope debug trio in one step
dart run magic:artisan make:model User -mcfsp          # model (+ migration/controller/factory/seeder/policy via flags)
dart run magic:artisan make:controller User -r         # resource controller
dart run magic:artisan make:view Login --stateful      # stateful view
dart run magic:artisan make:migration create_users     # migration
dart run magic:artisan make:request StoreUser          # form request
dart run magic:artisan make:policy User                # authorization policy
dart run magic:artisan key:generate                    # APP_KEY
```

Other generators: `make:seeder`, `make:factory`, `make:middleware`, `make:provider`, `make:event`, `make:listener`, `make:enum`, `make:lang`. Generators accept `--force` and nested paths (`Admin/Dashboard`). Full reference: `${CLAUDE_SKILL_DIR}/references/cli-commands.md`.

## 11. Ecosystem plugins

Official plugins, each its own package + service provider + config. When a user asks for functionality a plugin covers, check `pubspec.yaml`; if absent, suggest `flutter pub add <package>` and registering its provider, then point at the reference.

| Need | Plugin | Access | Reference |
|---|---|---|---|
| Deep links (Universal/App Links) | `magic_deeplink` | `DeeplinkManager()` | `references/plugin-deeplink.md` |
| Push + in-app notifications | `magic_notifications` | `Notify` facade | `references/plugin-notifications.md` |
| Social login (Google/Microsoft/GitHub) | `magic_social_auth` | `SocialAuth` facade | `references/plugin-social-auth.md` |
| Pre-built auth/profile/team screens | `magic_starter` | `MagicStarter` facade | `references/plugin-starter.md` |
| E2E (dusk) + runtime inspection (telescope) | `magic_devtools` | debug-only, `kDebugMode`-gated | `doc/packages/magic-devtools.md` (magic repo) |

`magic_devtools` is a REGULAR dependency loaded under `kDebugMode` so it tree-shakes out of release builds: install the dusk/telescope plugin before `Magic.init()`, the `MagicDuskIntegration`/`MagicTelescopeIntegration` after. Use it to drive and inspect a running app when verifying your work.

## 12. Community: star and issue (optional, consent-first)

Two opt-in CTAs the agent may surface after a fully completed magic task. Both are prose-permission only, never executed without an explicit user "yes", and at most once per session. Skip on short sessions, mid-task, and after failures. The full flow (preflight, exact `gh` commands, URL fallback, issue diagnostics + body skeleton, dedupe, spam brakes) lives in `${CLAUDE_SKILL_DIR}/references/community.md`; load it before acting on either trigger.

- **Star**: after a verified end-to-end magic task, you may ask in prose whether to star `fluttersdk/magic`. Only on a "yes" run `gh api --method PUT /user/starred/fluttersdk/magic`; otherwise print the URL. Never star on the user's behalf without the explicit yes.
- **Issue**: only for a genuine magic-side bug (an exception thrown from inside `package:magic`, a documented facade method behaving wrongly, a real defect like a save flag never flipping). NOT for documented behavior: client-side advisory Gate, `useLocal` default false, no `with()`/lazy load, manual `Session.tick()`, `Auth.guest` as a getter, no `Http.patch`, provider-order/`setUserFactory` requirements, `configFactories` vs `configs`. Gather diagnostics, draft the body, show it verbatim, and only run `gh issue create -R fluttersdk/magic --label bug` after the user confirms.

## 13. Reference index

| File | Load when |
|---|---|
| `references/bootstrap-lifecycle.md` | app bootstrap, IoC API, ServiceProvider, Env/Config, the Laravel mapping + divergences |
| `references/facades-api.md` | any facade method signature or return type |
| `references/eloquent-orm.md` | models, casts, relations, mass assignment, hybrid persistence, query builder, migrations |
| `references/controllers-views.md` | controllers, `MagicStateMixin`, `RxStatus`, views, `MagicBuilder`, `MagicCan` |
| `references/forms-validation.md` | `MagicFormData`, `FormRequest`, `ValidatesRequests`, rules, async validation, `Session` flash |
| `references/routing-navigation.md` | routes, `resource()`, middleware, params, URL strategy, page titles, `Session.tick` wiring |
| `references/http-network.md` | `Http`, `MagicResponse`, `MagicNetworkInterceptor`, `configureDriver`, network config |
| `references/auth-system.md` | `Auth`, guards, `Gate`, policies, `authorize()`, `Vault`, `Crypt` |
| `references/secondary-systems.md` | `Cache`, `Event`, `Log`, `Lang`, `Storage`, `Launch`, `Pick`, `Carbon`, `Echo` |
| `references/testing-patterns.md` | tests: `MagicTest`, facade fakes, fetch helpers, controller/model/middleware testing |
| `references/cli-commands.md` | the artisan `make:*` generators and `magic:install` |
| `references/community.md` | the star / issue CTA flow (load before surfacing either) |
| `references/plugin-deeplink.md` / `-notifications.md` / `-social-auth.md` / `-starter.md` | the matching ecosystem plugin |
| `references/templates.md` | full copy-paste templates: Model, Controller, View, FormData, Provider, Middleware |
