<!-- magic_local_storage v1.0.0 | Updated: 2026-11-14 -->

# magic_local_storage Plugin

The SQLite layer of a Magic app: the `DB` and `Schema` facades, the query builder, migrations, seeders, factories, the `SyncFeed` and `SyncLedger` sync skeleton, and the `QueryModelStore` behind every `useLocal` model. All of it lived in core `magic` up to 0.0.41. Core 0.1.0 keeps only the base `Model`, casts, `HasTimestamps`, `InteractsWithPersistence`, model events and the `LocalModelStore` contract (container key `'local_model_store'`).

## Contents

- [Installation](#installation)
- [Models with useLocal](#models-with-uselocal)
- [DB Facade API](#db-facade-api)
- [Schema and migrations](#schema-and-migrations)
- [Query builder](#query-builder)
- [Factories and seeders](#factories-and-seeders)
- [Sync](#sync)
- [CLI commands](#cli-commands)
- [Testing](#testing)
- [Gotchas](#gotchas)

## Installation

```yaml
dependencies:
  magic_local_storage: ^1.0.0
```

Requires Dart >=3.13, Flutter >=3.47 and `magic ^1.0.0`.

```bash
flutter pub add magic_local_storage
dart run magic:dowel plugin:install magic_local_storage
```

The installer adds `DatabaseServiceProvider` to `lib/config/app.dart` and `() => databaseConfig` to the `configFactories` of `lib/main.dart` (imported from the barrel; no config file is published), then chains `local_storage:install`, which downloads `web/sqlite3.wasm` (release `sqlite3-3.9.1`) when the project has a `web/` folder. Re-run `local_storage:install` after adding the web target later. Import only `package:magic_local_storage/magic_local_storage.dart`.

`register()` binds `'db'` (`DatabaseManager`) and `'local_model_store'` (`QueryModelStore`); `boot()` opens the connection. The default is SQLite at `magic_app.db` in the documents directory on native platforms, and `sqlite3.wasm` over IndexedDB on the web.

## Models with useLocal

The model stays in core; this package supplies the storage:

```dart
class Post extends Model with HasTimestamps, InteractsWithPersistence {
  @override String get table => 'posts';
  @override String get resource => 'posts';
  @override bool get useLocal => true;
  @override bool get useRemote => false;   // SQLite only, no HTTP
}
```

`useLocal: true, useRemote: true` reads SQLite first, falls back to the API and upserts what the API returned. With the plugin missing, a `useLocal` model throws a `StateError` naming `magic_local_storage` on every persistence leg. `QueryModelStore` drops attributes the table has no column for, so a model may carry computed or remote-only attributes. The `ModelQuery` extension adds `model.query()`, a `QueryBuilder` over the model's table.

## DB Facade API

| Member | Return type | Notes |
|:-------|:------------|:------|
| `DB.table(name)` | `QueryBuilder` | Fluent query entry point. |
| `DB.select(sql, [params])` | `List<Map<String, dynamic>>` | Raw SELECT, synchronous. |
| `DB.insert(sql, [params])` | `int` | Last insert rowid. |
| `DB.update(sql, [params])` / `DB.delete(sql, [params])` | `int` | Affected rows. |
| `DB.statement(sql, [params])` | `void` | Any SQL (DDL). |
| `DB.beginTransaction()` / `commit()` / `rollback()` | `void` | Manual transaction. |
| `DB.transaction<T>(callback)` | `Future<T>` | Commits on success, rolls back on error. The callback must NOT call `commit` / `rollback` itself. |

## Schema and migrations

`Schema`: `create(table, (Blueprint b) {})`, `table(name, (b) {})`, `drop`, `dropIfExists`, `rename(from, to)` (all synchronous), and `hasTable`, `hasColumn`, `getColumns` (async).

`Blueprint` columns: `id([name])`, `string(name, [length])`, `text`, `integer`, `bigInteger`, `boolean` (stored 0/1), `real`, `blob`, `timestamps()`, `dropColumn`, `renameColumn`. Modifiers: `.nullable()`, `.unique()`, `.defaultValue(v)`.

```dart
class CreatePostsTable extends Migration {
  @override String get name => '20261114120000_create_posts_table';

  @override
  void up() => Schema.create('posts', (Blueprint table) {
    table.id();
    table.string('title');
    table.timestamps();
  });

  @override
  void down() => Schema.dropIfExists('posts');
}

await Migrator().run([CreatePostsTable()]);
```

`Migrator` methods: `run`, `rollback`, `reset`, `refresh`, `getExecuted`, `getPending`. There is no migration discovery: list every migration in the call. The run is one unit (a SAVEPOINT): if one throws, none is recorded. `up()` and `down()` are synchronous `void`; writing `void up() async` is a silent defect, so use `DB.statement` and `DB.select`, never `DatabaseManager().getColumns`. A migration must not call `DB.beginTransaction`, `commit` or `rollback`. A migration with no honest rollback throws `UnsupportedError` from `down()`.

## Query builder

Chain: `select(cols)`, `where(col, opOrValue, [value])`, `orderBy(col, [dir])`, `limit`, `offset`. Execute: `get()`, `first()`, `value<T>(col)`, `pluck<T>(col)`, `count()`, `exists()`, `insert(map)` (last id), `insertAll(list)`, `update(map)` and `delete()` (affected rows), `truncate()`. Insert and update drop columns absent from the table.

## Factories and seeders

`Factory<T extends Model>`: implement `definition()` (with `faker`), `newInstance()` and `newFactory()`; then `count(n)`, `state(map)`, `raw()`, `make()` (in memory) and `create()` (persists via `save()`, unguarded, throws `StateError` when a save is refused). Write named states as an extension on `Factory<T>`.

`Seeder`: override `run()`; `call([...])` runs child seeders in order. Seeding runs from Dart (there is no `db:seed` command), replacing `Magic.seed`:

```dart
await Magic.init(configFactories: [...]);
await Seeding.run([UserSeeder(), TodoSeeder()]);   // sequential; a throw stops the run
```

## Sync

`SyncFeed` runs push-then-pull over one REST resource and never throws: `run({scope, account})` answers a `SyncReport` (`pushed`, `adopted`, `failure`, `complete`). A subclass supplies `feed`, `resource`, `envelopeKey`, `pending({account, sinceMillis, scope})` (oldest first) and `adoptRow({account, row})`; `batchSize` (500) and `maxPages` (100) are overridable. Push is `POST '$resource/sync'` with `{envelopeKey: [rows]}`; pull is `GET resource` with `{scope, cursor}` and expects `{data, cursor, has_more}`. The push mark is the device's own `updated_at` and advances only on push; the pull cursor is the server's opaque text. `SyncLedger({table: 'sync_cursors'})` stores the bookmarks (delete-then-insert inside a SAVEPOINT); `CreateSyncCursorsTable` creates the table and must be listed in the app's `Migrator().run`.

## CLI commands

| Command | Description |
|:--------|:------------|
| `local_storage:install` | Register the provider and config factory, download `web/sqlite3.wasm` (`--dry-run` supported). |
| `make:migration name [--create=table] [--table=table]` | Timestamped migration in `lib/database/migrations/`. |
| `make:seeder Name` | Seeder in `lib/database/seeders/`. |
| `make:factory Name` | Factory in `lib/database/factories/`. |

Core's `make:model -m/-f/-s` and `make:resource` find these three by name in the dowel registry; without this plugin they print a hint and skip that file. Core no longer registers them (dowel exits on a name collision).

## Testing

Bind a store per test. With SQLite: add `sqlite3` as a dev dependency, then in `setUp()` call `MagicApp.reset()` and `Magic.flush()`, `DatabaseManager().setConnection(sqlite3.openInMemory())` and `MagicApp.instance.singleton('local_model_store', () => QueryModelStore())`; call `DatabaseManager().dispose()` in `tearDown()`. `DatabaseManager` is a singleton that `Magic.flush()` does not clear. Without SQLite, implement `LocalModelStore` by contract in memory.

## Gotchas

| Mistake | Fix |
|:--------|:----|
| `useLocal => true` with no plugin | Install and register `DatabaseServiceProvider`; the `StateError` is deliberate. |
| `void up() async` in a migration | Keep `up()` and `down()` synchronous. |
| Expecting migration discovery | Pass every migration to `Migrator().run([...])`. |
| `Magic.seed(...)` | Gone: `Seeding.run(List<Seeder>)`. |
| Opening the web build with no `web/sqlite3.wasm` | Run `local_storage:install` with a `web/` folder present. |
| `databaseConfig` under `configs` | Use `configFactories`. |
| Calling `DB.commit` inside `DB.transaction` | The callback must not close its own transaction. |
