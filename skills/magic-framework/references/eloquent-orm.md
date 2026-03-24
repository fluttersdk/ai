# Eloquent ORM Reference

Laravel-inspired ORM for Flutter. Supports hybrid persistence (Remote API + Local SQLite).


## Model Definition Template

Complete boilerplate for a model with timestamps and persistence:

```dart
import 'package:magic/magic.dart';

class Monitor extends Model with HasTimestamps, InteractsWithPersistence {
  @override
  String get table => 'monitors';

  @override
  String get resource => 'monitors';

  @override
  List<String> get fillable => [
        'name',
        'url',
        'type',
        'status',
      ];

  @override
  Map<String, String> get casts => {
        'settings': 'json',
        'created_at': 'datetime',
        'updated_at': 'datetime',
      };

  // Typed getters — ALWAYS use get<T>(), never getAttribute() directly
  int? get id => get<int>('id');
  String? get name => get<String>('name');
  MonitorType? get type => MonitorType.fromValue(get<String>('type'));

  // Typed setters
  set name(String? v) => set('name', v);
  set type(MonitorType? v) => set('type', v?.value);

  // fromMap factory — bypasses fillable guard
  static Monitor fromMap(Map<String, dynamic> map) =>
      Monitor()
        ..setRawAttributes(map, sync: true)
        ..exists = true;

  // Static finders (delegate to InteractsWithPersistence static methods)
  static Future<Monitor?> find(dynamic id) =>
      InteractsWithPersistence.findById<Monitor>(id, Monitor.new);

  static Future<List<Monitor>> all() =>
      InteractsWithPersistence.allModels<Monitor>(Monitor.new);
}
```

## Configuration Properties

| Property | Type | Default | Purpose |
| :--- | :--- | :--- | :--- |
| `table` | `String` | Required | SQLite table name |
| `resource` | `String` | Required | API endpoint name |
| `primaryKey` | `String` | `'id'` | Primary key column |
| `incrementing` | `bool` | `true` | Auto-increment PK |
| `useLocal` | `bool` | `false` | Enable SQLite persistence |
| `useRemote` | `bool` | `true` | Enable API calls |
| `fillable` | `List<String>` | `[]` | Mass-assignable fields |
| `guarded` | `List<String>` | `['*']` | Guarded fields (default blocks all) |
| `casts` | `Map<String, String>` | `{}` | Type casting map |
| `hidden` | `List<String>` | `[]` | Hidden from serialization |
| `visible` | `List<String>` | `[]` | Whitelist for serialization |
| `relations` | `Map<String, Model Function()>` | `{}` | Relation factories |

## Attribute API

| Method | Signature | Purpose |
| :--- | :--- | :--- |
| `get<T>` | `T? get<T>(String key, {T? defaultValue})` | Typed read with cast support (preferred) |
| `set` | `void set(String key, dynamic value)` | Write attribute |
| `has` | `bool has(String key)` | Check non-null existence |
| `fill` | `void fill(Map<String, dynamic> attributes)` | Mass assign (respects fillable/guarded) |
| `getAttribute` | `dynamic getAttribute(String key)` | Raw read with casting (used internally) |
| `setAttribute` | `void setAttribute(String key, dynamic value)` | Raw write with type conversion |
| `setRawAttributes` | `void setRawAttributes(Map<String, dynamic> attributes, {bool sync = false})` | Bulk hydrate, bypass fillable |
| `id` | `dynamic get id` | Primary key value |
| `attributes` | `Map<String, dynamic> get attributes` | All attributes copy |
| `toMap()` | `Map<String, dynamic>` | Serialize (respects hidden/visible) |
| `toArray()` | `Map<String, dynamic>` | Alias for toMap() |
| `toJson()` | `String` | JSON string |
| `makeHidden(fields)` | `Model makeHidden(List<String>)` | Runtime hide fields, returns self |
| `makeVisible(fields)` | `Model makeVisible(List<String>)` | Runtime show fields, returns self |
| `append(fields)` | `Model append(List<String>)` | Add accessor keys to serialization |
| `exists` | `bool` | Whether model exists in DB |
| `wasRecentlyCreated` | `bool` | True immediately after first save |

## Casting

| Cast | Dart Type | Conversion |
| :--- | :--- | :--- |
| `datetime` | `Carbon` | ISO 8601 string ↔ Carbon; Carbon stored as ISO 8601 string |
| `json` | `Map<String, dynamic>` | JSON string ↔ Map; Map stored as JSON string |
| `bool` | `bool` | int 0/1 or string `"true"`/`"false"` |
| `int` | `int` | Safe parse via `int.tryParse` |
| `double` | `double` | Safe parse via `double.tryParse` |

## Relations

Relations are lazy-loaded from API response Maps and auto-cached after first access.

```dart
@override
Map<String, Model Function()> get relations => {
      'user': User.new,
      'comments': Comment.new,
    };

User? get user => getRelation<User>('user');
List<Comment> get comments => getRelations<Comment>('comments');
```

| Method | Signature | Purpose |
| :--- | :--- | :--- |
| `getRelation<T>` | `T? getRelation<T extends Model>(String key)` | Get single related model |
| `getRelations<T>` | `List<T> getRelations<T extends Model>(String key)` | Get list of related models |

## Dirty Tracking

| Method | Returns | Purpose |
| :--- | :--- | :--- |
| `isDirty([key])` | `bool` | Check if model/field changed since last sync |
| `getDirty()` | `Map<String, dynamic>` | Changed attributes only |
| `syncOriginal()` | `void` | Reset original to current (marks clean) |

## HasTimestamps Mixin

Mix in alongside `InteractsWithPersistence` to get automatic timestamp management.

```dart
class Post extends Model with HasTimestamps, InteractsWithPersistence { ... }
```

| Property / Method | Type / Signature | Purpose |
| :--- | :--- | :--- |
| `timestamps` | `bool` (default `true`) | Override to `false` to disable auto-timestamps |
| `createdAtColumn` | `String` (default `'created_at'`) | Override to use a custom column name |
| `updatedAtColumn` | `String` (default `'updated_at'`) | Override to use a custom column name |
| `createdAt` | `Carbon? get createdAt` | Created timestamp as Carbon |
| `updatedAt` | `Carbon? get updatedAt` | Updated timestamp as Carbon |
| `updateTimestamps()` | `void` | Called automatically before `save()` |
| `touch()` | `void touch()` | Manually set `updated_at` to now without saving |
| `freshTimestamp()` | `Carbon` | Returns `Carbon.now()` |
| `freshTimestampString()` | `String` | Returns ISO 8601 formatted now |

`updateTimestamps()` sets `updated_at` on every save and sets `created_at` only when `!exists`.

## InteractsWithPersistence Mixin

### Static Methods

| Method | Signature | Purpose |
| :--- | :--- | :--- |
| `findById<T>` | `static Future<T?> findById<T extends Model>(dynamic id, T Function() factory)` | Find by PK; tries local then remote |
| `allModels<T>` | `static Future<List<T>> allModels<T extends Model>(T Function() factory)` | Fetch all; tries local then remote |
| `hydrate<T>` | `static T hydrate<T extends Model>(Map<String, dynamic> data, T Function() factory)` | Hydrate a model instance from a raw map |

### Instance Methods

| Method | Signature | Returns | Purpose |
| :--- | :--- | :--- | :--- |
| `save()` | `Future<bool> save()` | `bool` success | Create or update; fires Model events, calls `updateTimestamps()` |
| `delete()` | `Future<bool> delete()` | `bool` success | Delete from remote and/or local |
| `refresh()` | `Future<bool> refresh()` | `bool` success | Re-hydrate from local or remote |
| `query()` | `QueryBuilder query()` | `QueryBuilder` | Raw query builder scoped to model's table |

`save()` determines create vs update via `exists`. On success it sets `exists = true` and calls `syncOriginal()`.

## Hybrid Persistence Flow

`useLocal` and `useRemote` flags control which backends are active. Both can be `true` simultaneously.

| Flag combination | Behaviour |
| :--- | :--- |
| `useRemote: true, useLocal: false` (default) | API only; no SQLite |
| `useRemote: false, useLocal: true` | SQLite only; no HTTP calls |
| `useRemote: true, useLocal: true` | Both; local used as cache |

### save() flow
1. Dispatches `ModelSaving`, then `ModelCreating` (new) or `ModelUpdating` (existing).
2. Calls `updateTimestamps()`.
3. If `useRemote`: POST `/{resource}` (new) or PUT `/{resource}/{id}` (existing). Sets `id` from response on create.
4. If `useLocal`: INSERT or UPDATE in SQLite. QueryBuilder auto-filters columns to those present in the schema.
5. On success: `exists = true`, `syncOriginal()`, dispatches `ModelCreated`/`ModelUpdated`, then `ModelSaved`.

### find(id) flow
1. If `useLocal`: queries SQLite first; returns hydrated model on hit.
2. If `useRemote`: GET `/{resource}/{id}`; on success syncs to local (if `useLocal`) and returns model.
3. Returns `null` if both miss.

### allModels() flow
1. If `useLocal`: queries SQLite; returns results (does not fall back to remote on success).
2. If `useRemote`: GET `/{resource}`; syncs each item to local if `useLocal`.

### delete() flow
1. If `useRemote`: DELETE `/{resource}/{id}`.
2. If `useLocal`: deletes SQLite row.
3. On success: `exists = false`, dispatches `ModelDeleted`.

## QueryBuilder

Accessed directly via `DB.table('name')` facade or `model.query()`.
Schema-aware: insert/update silently drop columns absent from the actual SQLite schema.

| Category | Method | Signature | Returns |
| :--- | :--- | :--- | :--- |
| Chaining | `select` | `select(List<String> cols)` | `QueryBuilder` |
| Chaining | `where` | `where(String col, [dynamic op], [dynamic val])` | `QueryBuilder` |
| Chaining | `whereNull` | `whereNull(String col)` | `QueryBuilder` |
| Chaining | `whereNotNull` | `whereNotNull(String col)` | `QueryBuilder` |
| Chaining | `orderBy` | `orderBy(String col, [String dir = 'asc'])` | `QueryBuilder` |
| Chaining | `limit` | `limit(int count)` | `QueryBuilder` |
| Chaining | `offset` | `offset(int count)` | `QueryBuilder` |
| Execute | `get` | `.get()` | `Future<List<Map<String, dynamic>>>` |
| Execute | `first` | `.first()` | `Future<Map<String, dynamic>?>` |
| Execute | `value<T>` | `.value<T>(String col)` | `Future<T?>` |
| Execute | `pluck<T>` | `.pluck<T>(String col)` | `Future<List<T>>` |
| Execute | `count` | `.count()` | `Future<int>` |
| Execute | `exists` | `.exists()` | `Future<bool>` |
| Execute | `insert` | `.insert(Map<String, dynamic>)` | `Future<int>` (last insert id) |
| Execute | `insertAll` | `.insertAll(List<Map<String, dynamic>>)` | `Future<void>` |
| Execute | `update` | `.update(Map<String, dynamic>)` | `Future<int>` (rows affected) |
| Execute | `delete` | `.delete()` | `Future<int>` (rows affected) |
| Execute | `truncate` | `.truncate()` | `Future<void>` |

## Migrations

Naming convention: `YYYY_MM_DD_HHMMSS_verb_table_name`

```dart
import 'package:magic/magic.dart';

class CreateMonitorsTable extends Migration {
  @override
  String get name => '2024_01_15_120000_create_monitors_table';

  @override
  void up() {
    Schema.create('monitors', (Blueprint table) {
      table.id();
      table.string('name');
      table.string('url');
      table.string('status').nullable();
      table.timestamps();
    });
  }

  @override
  void down() => Schema.dropIfExists('monitors');
}
```

`up()` and `down()` are synchronous `void`. Register migrations via `Migrator().run([...])`.

### Blueprint Column Methods

| Method | SQLite type | Notes |
| :--- | :--- | :--- |
| `id([name = 'id'])` | `INTEGER PRIMARY KEY AUTOINCREMENT` | |
| `string(name, [length])` | `TEXT` | Length ignored by SQLite |
| `text(name)` | `TEXT` | |
| `integer(name)` | `INTEGER` | |
| `bigInteger(name)` | `INTEGER` | Alias for `integer` |
| `boolean(name)` | `INTEGER` | Stored as 0/1 |
| `real(name)` | `REAL` | |
| `blob(name)` | `BLOB` | |
| `timestamps()` | Two nullable `TEXT` columns | `created_at`, `updated_at` |

### ColumnDefinition Modifiers (chainable)

| Modifier | Effect |
| :--- | :--- |
| `.nullable()` | Omits `NOT NULL` constraint |
| `.unique()` | Adds `UNIQUE` constraint |
| `.defaultValue(v)` | Adds `DEFAULT` clause |

### Schema Facade Methods (used in migrations)

| Method | Purpose |
| :--- | :--- |
| `Schema.create(table, callback)` | Create table via Blueprint |
| `Schema.table(table, callback)` | Modify table (add/rename/drop columns) |
| `Schema.drop(table)` | Drop table |
| `Schema.dropIfExists(table)` | Drop table if exists |

## Factories & Seeders

### Factory

Extend `Factory<T>` and implement both `definition()` and `newInstance()`.

```dart
import 'package:magic/magic.dart';

class MonitorFactory extends Factory<Monitor> {
  @override
  Monitor newInstance() => Monitor();

  @override
  Map<String, dynamic> definition() => {
        'name': faker.company.name(),
        'url': faker.internet.httpUrl(),
        'status': 'active',
      };
}

// Usage
final monitor = (await MonitorFactory().create()).first;
final monitors = await MonitorFactory().count(10).create();
final admins = await MonitorFactory().state({'status': 'paused'}).count(3).create();
final stubs = MonitorFactory().count(5).make(); // in-memory only, no save
```

| Method | Signature | Returns | Purpose |
| :--- | :--- | :--- | :--- |
| `definition()` | `Map<String, dynamic> definition()` | `Map` | Default attribute values using `faker` |
| `newInstance()` | `T newInstance()` | `T` | Returns empty model instance |
| `count(n)` | `Factory<T> count(int count)` | `Factory<T>` | Set number of models |
| `state(map)` | `Factory<T> state(Map<String, dynamic>)` | `Factory<T>` | Merge overrides with definition |
| `create()` | `Future<List<T>> create()` | `Future<List<T>>` | Persist models via `save()` |
| `make()` | `List<T> make()` | `List<T>` | Build in-memory only, no persistence |
| `faker` | `Faker get faker` | `Faker` | Access to `package:faker` instance |

### Seeder

```dart
import 'package:magic/magic.dart';

class MonitorSeeder extends Seeder {
  @override
  Future<void> run() async => MonitorFactory().count(10).create();
}

class DatabaseSeeder extends Seeder {
  @override
  Future<void> run() async {
    await call([
      MonitorSeeder(),
      UserSeeder(),
    ]);
  }
}

// Running:
await DatabaseSeeder().run();
```

| Method | Signature | Purpose |
| :--- | :--- | :--- |
| `run()` | `Future<void> run()` | Entry point — override to define seed logic |
| `call(seeders)` | `Future<void> call(List<Seeder>)` | Run child seeders in order |

## Model Events

Dispatched via `Event.dispatch()` during the `save()` / `delete()` lifecycle.

| Event | Fired when |
| :--- | :--- |
| `ModelSaving` | Before any save (create or update) |
| `ModelCreating` | Before create (`!exists`) |
| `ModelUpdating` | Before update (`exists`) |
| `ModelCreated` | After successful create |
| `ModelUpdated` | After successful update |
| `ModelSaved` | After any successful save |
| `ModelDeleted` | After successful delete |

## Gotchas

- **Null Safety**: `get<T>()` returns `null` for missing or wrongly-typed values — it never throws.
- **Schema Filtering**: QueryBuilder silently drops columns not present in the actual SQLite schema on `insert`/`update`.
- **Manual Hydration**: Call `syncOriginal()` after manually hydrating a model to reset dirty state.
- **Web vs Mobile**: Web uses in-memory SQLite (`sql.js`); mobile uses file-based SQLite.
- **Timestamps**: `HasTimestamps` stores timestamps as ISO 8601 strings; reads them back as `Carbon`.
- **Typed Access**: NEVER read via `getAttribute()` in model getters. ALWAYS use `get<T>()`.
- **`useLocal` default is `false`**: Models are remote-only by default. Add `@override bool get useLocal => true;` to enable SQLite.
- **`create()`/`firstOrCreate()`/`updateOrCreate()`**: These static convenience methods do NOT exist on `InteractsWithPersistence`. Use `save()` on a constructed model instance instead.
- **Factory requires `newInstance()`**: Omitting it causes a compile error — the framework cannot instantiate your model generically.
- **`migration.up()` is sync**: `Migration.up()` and `down()` are `void`, not `Future<void>`. Use sync SQLite calls inside them.
