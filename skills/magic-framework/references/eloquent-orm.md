# Eloquent ORM Reference

Laravel-inspired ORM for Flutter. Supports hybrid persistence (Remote API + Local SQLite).


## Model Definition Template

Complete boilerplate for a model with timestamps and persistence:

```dart
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

  // Typed getters — ALWAYS use get<T>(), never getAttribute()
  int? get id => get<int>('id');
  String? get name => get<String>('name');
  MonitorType? get type => MonitorType.fromValue(get<String>('type'));

  // Setters
  set name(String? v) => set('name', v);
  set type(MonitorType? v) => set('type', v?.value);

  // Static finders (delegate to InteractsWithPersistence)
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
| `useLocal` | `bool` | `false` | Enable SQLite (overridden by mixins) |
| `useRemote` | `bool` | `true` | Enable API calls |
| `fillable` | `List<String>` | `[]` | Mass-assignable fields |
| `guarded` | `List<String>` | `['*']` | Guarded fields |
| `casts` | `Map<String, String>` | `{}` | Type casting map |
| `hidden` | `List<String>` | `[]` | Hidden from serialization |
| `visible` | `List<String>` | `[]` | Whitelist for serialization |
| `relations` | `Map<String, Model Function()>` | `{}` | Relation factories |

## Attribute API

| Method | Signature | Purpose |
| :--- | :--- | :--- |
| `get<T>` | `T? get<T>(String key, {T? defaultValue})` | Typed read (preferred) |
| `set` | `void set(String key, dynamic value)` | Write attribute |
| `has` | `bool has(String key)` | Check non-null existence |
| `fill` | `void fill(Map<String, dynamic> attributes)` | Mass assign (respects fillable) |
| `id` | `dynamic get id` | Primary key value |
| `attributes` | `Map<String, dynamic> get attributes` | All attributes copy |
| `toMap()` | `Map<String, dynamic>` | Serialize (respects hidden/visible) |
| `toArray()` | `Map<String, dynamic>` | Alias for toMap() |
| `toJson()` | `String` | JSON string |
| `makeHidden(fields)` | `Model` | Runtime hide fields |
| `makeVisible(fields)` | `Model` | Runtime show fields |
| `exists` | `bool` | Whether model exists in DB |

## Casting

| Cast | Dart Type | Conversion |
| :--- | :--- | :--- |
| `datetime` | `Carbon` | ISO 8601 string ↔ Carbon |
| `json` | `Map<String, dynamic>` | JSON string ↔ Map |
| `bool` | `bool` | int 0/1 or string "true"/"false" |
| `int` | `int` | Safe parse via int.tryParse |
| `double` | `double` | Safe parse via double.tryParse |

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

## Dirty Tracking

| Method | Returns | Purpose |
| :--- | :--- | :--- |
| `isDirty([key])` | `bool` | Check if model/field changed |
| `getDirty()` | `Map` | Changed attributes only |
| `syncOriginal()` | `void` | Reset original to current (marks clean) |

## Hybrid Persistence Flow

### save() flow
1. **New Model** (`id == null`):
   - POST `/{resource}` to API.
   - Set `id` from response.
   - INSERT row into local SQLite.
   - Call `syncOriginal()`.
2. **Existing Model** (`id != null`):
   - PUT `/{resource}/{id}` to API.
   - UPDATE row in local SQLite.
   - Call `syncOriginal()`.
- *Note: `HasTimestamps` auto-sets `created_at`/`updated_at` and fires Model events.*

### find(id) flow
1. Query local SQLite first.
2. If found, hydrate model and return.
3. If miss, GET `/{resource}/{id}` from API.
4. INSERT into local SQLite.
5. Return hydrated model.

### delete() flow
1. DELETE `/{resource}/{id}` from API.
2. Remove local SQLite row.

### allModels() flow
- Queries local SQLite only. Caller is responsible for prior API sync if needed.

## QueryBuilder

QueryBuilder is schema-aware — it auto-filters attributes by actual table columns on insert/update.

| Category | Method | Signature | Returns |
| :--- | :--- | :--- | :--- |
| Chaining | `where` | `where(String col, [dynamic op], [dynamic val])` | `QueryBuilder` |
| Chaining | `whereNull` | `whereNull(String col)` | `QueryBuilder` |
| Chaining | `whereNotNull` | `whereNotNull(String col)` | `QueryBuilder` |
| Chaining | `orderBy` | `orderBy(String col, [String dir = 'asc'])` | `QueryBuilder` |
| Chaining | `limit` | `limit(int count)` | `QueryBuilder` |
| Chaining | `offset` | `offset(int count)` | `QueryBuilder` |
| Chaining | `select` | `select(List<String> cols)` | `QueryBuilder` |
| Execute | `get` | `.get()` | `Future<List<Map>>` |
| Execute | `first` | `.first()` | `Future<Map?>` |
| Execute | `value<T>` | `.value<T>(String col)` | `Future<T?>` |
| Execute | `pluck<T>` | `.pluck<T>(String col)` | `Future<List<T>>` |
| Execute | `count` | `.count()` | `Future<int>` |
| Execute | `exists` | `.exists()` | `Future<bool>` |
| Execute | `insert` | `.insert(Map)` | `Future<int>` (id) |
| Execute | `update` | `.update(Map)` | `Future<int>` (rows) |
| Execute | `delete` | `.delete()` | `Future<int>` (rows) |
| Execute | `truncate` | `.truncate()` | `Future<void>` |

## Migrations

Naming convention: `m_YYYY_MM_DD_HHMMSS_{verb}_{table}_table.dart`

```dart
class CreateMonitorsTable extends Migration {
  @override
  Future<void> up() async {
    await Schema.create('monitors', (Blueprint table) {
      table.id();
      table.string('name');
      table.string('url');
      table.string('status').nullable();
      table.timestamps();
    });
  }

  @override
  Future<void> down() async => Schema.dropIfExists('monitors');
}
```

**Blueprint methods**: `id()`, `string(col)`, `integer(col)`, `boolean(col)`, `text(col)`, `real(col)`, `blob(col)`, `timestamps()`.
**Modifiers**: `.nullable()`, `.unique()`, `.defaultValue(v)`.

## Factories & Seeders

```dart
class MonitorFactory extends Factory<Monitor> {
  @override
  Map<String, dynamic> definition() => {
        'name': faker.food.dish(),
        'url': faker.internet.httpUrl(),
      };
}

class MonitorSeeder extends Seeder {
  @override
  Future<void> run() async => MonitorFactory().count(10).create();
}

// Running seeders:
await MonitorSeeder().run();
```


## Model Events

The persistence lifecycle dispatches events via `Event.dispatch()`. Listen to these via `EventDispatcher.instance.register()`.

| Event | Fired | Description |
|:------|:------|:------------|
| `ModelSaving` | Before save (create or update) | Runs before any persistence call |
| `ModelCreating` | Before create | Runs only on new models (`id == null`) |
| `ModelUpdating` | Before update | Runs only on existing models |
| `ModelCreated` | After create | Model has been persisted with new ID |
| `ModelUpdated` | After update | Model changes have been persisted |
| `ModelSaved` | After save (create or update) | Final event after persistence completes |
| `ModelDeleted` | After delete | Model has been removed |

## Gotchas

- **Null Safety**: `get<T>()` returns `null` for missing keys — it never throws.
- **Schema Filtering**: QueryBuilder silently drops columns not present in the actual SQLite schema.
- **Manual Hydration**: `syncOriginal()` must be called after manual model hydration to reset dirty state.
- **Web vs Mobile**: Web uses in-memory SQLite (sql.js); mobile uses file-based SQLite.
- **Timestamps**: `HasTimestamps` sets `created_at`/`updated_at` as ISO 8601 strings.
- **Typed Access**: NEVER use `getAttribute()` directly. ALWAYS use `get<T>()` for safe, typed access.
