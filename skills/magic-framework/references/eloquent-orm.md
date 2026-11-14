# Eloquent ORM Reference

Laravel-inspired ORM for Flutter. API-first by default; a model opts into hybrid persistence (Remote API + Local SQLite) with `useLocal`, which needs the `magic_local_storage` plugin.

Core keeps the base `Model`, casts, `HasTimestamps`, `InteractsWithPersistence`, model events and the `LocalModelStore` contract. The query builder, `DB`, `Schema`, migrations, factories, seeders and sync live in `magic_local_storage`: see `plugin-local-storage.md`.

## Contents

- [Model Definition Template](#model-definition-template)
- [Configuration Properties](#configuration-properties)
- [Attribute API](#attribute-api)
- [Casting](#casting)
- [Mass Assignment & MassAssignmentException](#mass-assignment--massassignmentexception)
- [Relations](#relations)
- [Dirty Tracking](#dirty-tracking)
- [HasTimestamps Mixin](#hastimestamps-mixin)
- [InteractsWithPersistence Mixin](#interactswithpersistence-mixin)
- [Hybrid Persistence Flow](#hybrid-persistence-flow)
- [Local persistence (magic_local_storage)](#local-persistence-magic_local_storage)
- [Model Events](#model-events)
- [Gotchas](#gotchas)

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
  Map<String, String> get casts => const {
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
| `table` | `String` | Required | Local table name (used when `useLocal` is true) |
| `resource` | `String` | Required | API endpoint name |
| `primaryKey` | `String` | `'id'` | Primary key column |
| `incrementing` | `bool` | `true` | Auto-increment PK |
| `useLocal` | `bool` | `false` | Enable local persistence; needs `magic_local_storage` (a `StateError` otherwise) |
| `useRemote` | `bool` | `true` | Enable API calls |
| `fillable` | `List<String>` | `[]` | Mass-assignable fields |
| `guarded` | `List<String>` | `['*']` | Guarded fields (default blocks all) |
| `casts` | `Map<String, dynamic>` | `const {}` | Type casting map (string tokens or `CastsAttributes<T>` instances). Return a `const` literal: `getAttribute` reads it on every call, so a non-const literal allocates on every attribute read. |
| `hidden` | `List<String>` | `[]` | Hidden from serialization |
| `visible` | `List<String>` | `[]` | Whitelist for serialization |
| `relations` | `Map<String, Model Function()>` | `{}` | Relation factories |

## Attribute API

| Method | Signature | Purpose |
| :--- | :--- | :--- |
| `get<T>` | `T? get<T>(String key, {T? defaultValue})` | Typed read with cast support (preferred) |
| `set` | `void set(String key, dynamic value)` | Write attribute |
| `has` | `bool has(String key)` | Check non-null existence |
| `fill` | `void fill(Map<String, dynamic> attributes, {bool strict = false})` | Mass assign (respects fillable/guarded); when `strict: true`, throws `MassAssignmentException` on non-fillable keys instead of silently dropping them |
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

### Built-in string-token casts

| Cast | Dart Type | Conversion |
| :--- | :--- | :--- |
| `datetime` | `Carbon` | ISO 8601 string ↔ Carbon; Carbon stored as ISO 8601 string |
| `json` | `Map<String, dynamic>` or `List` | JSON string ↔ Map/List; Map/List stored as JSON string |
| `bool` | `bool` | int 0/1 or string `"true"`/`"false"` |
| `int` | `int` | Safe parse via `int.tryParse` |
| `double` | `double` | Safe parse via `double.tryParse` |

A built-in cast is computed once per raw value and memoised, so repeated
reads of the same attribute return the identical instance rather than
re-parsing. The memo is dropped by `setAttribute` for that key and by
`setRawAttributes` for all of them. A `CastsAttributes` instance is NOT
memoised, because it may derive its answer from something other than the
attribute it is registered against.

Reading a relation with `getRelation` / `getRelations` does not make the
model dirty: the materialised instance replaces the raw Map in the
original snapshot too, so `isDirty()` still answers about writes only.

### Class-based casts (`CastsAttributes<T>`)

Implement `CastsAttributes<T>` for reusable, typed, custom casts. Two built-in implementations ship in `package:magic/magic.dart`:

```dart
abstract class CastsAttributes<T> {
  const CastsAttributes();
  T? get(Model model, String key, Object? raw);       // storage -> domain
  Object? set(Model model, String key, Object? value); // domain -> storage
}
```

```dart
// EnumCast — map a name-based string column to an enum.
enum MonitorStatus { up, down, paused }

@override Map<String, dynamic> get casts => const {
  'status': EnumCast(MonitorStatus.values),                   // unknown values return null
  'strict_status': EnumCast(MonitorStatus.values, strict: true), // throws ArgumentError on unknown value
};

// ListCast — apply an inner cast element-by-element. Stored as JSON string.
@override Map<String, dynamic> get casts => const {
  'tags': ListCast(EnumCast(MonitorTag.values)),
};
```

`ListCast.get()` accepts either a `List`, a JSON string, or a single value (coerced into `[value]`). `ListCast.set()` emits JSON when given a `List`; otherwise passes raw storage forms through unchanged.

Mix string-token and class-based entries in the same `casts` map — resolution happens per key.

## Mass Assignment & MassAssignmentException

```dart
final user = User();
user.fill({'name': 'Ada', 'role': 'admin'});                // 'role' silently dropped (not fillable)
user.fill({'name': 'Ada', 'role': 'admin'}, strict: true);  // throws MassAssignmentException('role', User)
```

`MassAssignmentException` is an `Exception` with `.attribute` (the offending key) and optional `.modelType`. Pair `strict: true` with a validated payload (e.g., from `FormRequest.validate()` or `Validator.validate()`) so schema drift fails loudly at the boundary instead of corrupting state.

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
4. If `useLocal`: INSERT or UPDATE through the bound `LocalModelStore`. The SQLite store drops attributes the table has no column for.
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

## Local persistence (magic_local_storage)

A `useLocal => true` model persists through the `LocalModelStore` contract that core resolves from the container key `'local_model_store'` before every local leg (`save`, `find`, `allModels`, `delete`, `refresh`, and the remote-to-local sync). With nothing bound it throws a `StateError` naming `magic_local_storage`, on every leg; set `useLocal` back to `false` or install the plugin.

`LocalModelStore` has six members: `find(table, primaryKey, id)`, `all(table)`, `insert(table, data)`, `update(table, primaryKey, id, data)`, `delete(table, primaryKey, id)` and `upsert(table, primaryKey, id, data)`. `magic_local_storage` supplies the SQLite implementation (`QueryModelStore`, bound by `DatabaseServiceProvider`), plus the query builder, the `DB` and `Schema` facades, migrations, factories, seeders and sync. Everything that touches SQL is in `plugin-local-storage.md`: the query builder (`DB.table(...)` and the `model.query()` extension), `Migration`, `Factory<T>` and `Seeder`, none of which exist in core.

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
- **Column filtering**: the SQLite store behind `useLocal` drops attributes the table has no column for on insert and update.
- **Manual Hydration**: Call `syncOriginal()` after manually hydrating a model to reset dirty state.
- **Timestamps**: `HasTimestamps` stores timestamps as ISO 8601 strings; reads them back as `Carbon`.
- **Typed Access**: NEVER read via `getAttribute()` in model getters. ALWAYS use `get<T>()`.
- **`useLocal` default is `false`**: Models are remote-only by default. Add `@override bool get useLocal => true;` to enable local persistence, and install `magic_local_storage`: with no `LocalModelStore` bound the model throws a `StateError` naming it.
- **`create()`/`firstOrCreate()`/`updateOrCreate()`**: These static convenience methods do NOT exist on `InteractsWithPersistence`. Use `save()` on a constructed model instance instead.
