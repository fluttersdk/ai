---
name: magic-local-storage
description: "Store data locally in a Magic app with SQLite: DB and Schema facades, migrations, seeders, factories, the useLocal model store and SyncFeed."
version: 1.0.0
when_to_use: "Use when code imports package:magic_local_storage or touches DB, Schema, Migration, Migrator, Seeding.run, Factory, SyncFeed, DatabaseServiceProvider or a useLocal model in a Magic app."
---

# magic_local_storage

The local SQLite layer of a Magic app. `DB` and `Schema` run queries and table changes on one connection that `DatabaseManager` opens (FFI on native, `sqlite3.wasm` on web). `Migration` classes run through `Migrator`, `Seeder` and `Factory` fill tables, and `SyncFeed` keeps a table consistent with a server. `DatabaseServiceProvider` also binds the `QueryModelStore` at `local_model_store`, which is what a `useLocal => true` model persists through.

This skill covers `magic_local_storage` only. The Magic framework itself (container, providers, `Model` and `InteractsWithPersistence`, `Http`, config) is the `magic-framework` skill.

## Install

```bash
flutter pub add magic_local_storage
dart run magic:dowel plugin:install magic_local_storage
```

Requires Dart >=3.13, Flutter >=3.47 and `magic` ^1.0.0. The installer adds `DatabaseServiceProvider` to `lib/config/app.dart` and `() => databaseConfig` to the `configFactories` of `lib/main.dart`, then chains `local_storage:install`, which downloads `web/sqlite3.wasm` for a project with a `web/` folder. It publishes no config. Import only `package:magic_local_storage/magic_local_storage.dart`.

## Model rules

1. A `useLocal => true` model needs this package. With no store bound, every persistence leg (`find`, `all`, `save`, `delete`, `refresh`) throws a `StateError` naming `magic_local_storage`, and it is thrown before the leg's own `try`, so no fallback hides it. Fix it by registering the provider, never by catching the error.
2. The store keeps only the attributes the table has a column for. A typo in an attribute name is dropped without an error, so check the table when a value does not persist.
3. Run the migration before the first save. A table with no columns makes the store write nothing and the insert answers `0`.
4. `model.query()` returns raw row maps. Booleans arrive as `0` and `1`; hydrate through the model to apply its casts.
5. Another engine or a test double implements core's `LocalModelStore` and binds it at `local_model_store`.

## Migration rules

1. `up()` and `down()` return `void` and stay synchronous. `void up() async` compiles and `run` records it complete at the first suspension.
2. Inside a migration use `Schema.create`, `Schema.table`, `Schema.drop`, `Schema.dropIfExists`, `Schema.rename`, `DB.statement` and `DB.select`. `Schema.hasTable`, `hasColumn`, `getColumns` and `DatabaseManager.getColumns` return futures; read `PRAGMA table_info` with `DB.select` instead.
3. Never call `DB.beginTransaction`, `DB.commit` or `DB.rollback` in a migration. One `run` is one `SAVEPOINT`, and a commit inside it closes that unit; `run` throws a `StateError` naming the migration.
4. `name` is the ledger key in `magic_migrations`. Keep it unique and never rename a released one, or it runs again.
5. There is no discovery: pass every migration to `Migrator().run`, in order, after `Magic.init`. It skips applied names, so calling it on every launch is safe.
6. A migration with no honest rollback throws `UnsupportedError` from `down()`; doing nothing makes `rollback` forget a migration that is still applied.
7. A column added to an existing table must be `nullable()` or carry `defaultValue`; SQLite refuses a `NOT NULL` column with no default.

## Query rules

1. Raw `DB.select`, `insert`, `update`, `delete` and `statement` are synchronous; `QueryBuilder` terminals return futures.
2. Values are bound. A plain table or column name (`order`, `users.id`) is quoted, so `order` works as a column in `where`, `orderBy`, `value` and `pluck`; any other text (`lower(email)`, `name COLLATE NOCASE`, `RANDOM()`) and every `select([...])` entry is raw SQL. Never pass user input as a name.
3. `where` takes `=`, `==`, `!=`, `<>`, `<`, `<=`, `>`, `>=`, `like`, `not like`, `glob`, `not glob`, `match`, `is` and `is not`; `orderBy` takes `asc` or `desc`. Anything else, `in` included, throws an `ArgumentError`.
4. A `null` value in `where` becomes `IS NULL` (`=`, `==`, `is`, two arguments) or `IS NOT NULL` (`!=`, `<>`, `is not`); prefer `whereNull` and `whereNotNull`. Constraints are always `AND`ed.
5. `insert` or `update` on a table that does not exist throws a `StateError` naming it, so `save()` on a `useLocal` model answers `false` until its migration ran.
6. `insertAll` is one insert per record and not atomic; wrap it in `DB.transaction`.
7. `DB.transaction` owns its transaction. A `DB.commit()` or `DB.rollback()` inside it makes the call throw. For manual control use `beginTransaction`, `commit` and `rollback` throughout and do not mix the two.

## Seeding rules

1. `Seeding.run(List<Seeder>)` runs the seeders in order. Core's `Magic.seed` is gone.
2. Guard it (`kDebugMode`, a `count()` check) so a restart does not seed twice.
3. A `Factory<T>` implements `definition()`, `newInstance()` and `newFactory()`. `count` and `state` return copies built through `newFactory`; name reusable states as an extension on `Factory<T>`, since a method on the subclass is lost after `count()`.
4. A factory fills its models unguarded. `create()` saves through `save()`, so the model needs `InteractsWithPersistence`; a refused save throws a `StateError`.

## Sync rules

1. A feed overrides `feed`, `resource`, `envelopeKey`, `pending` and `adoptRow`. `run({scope, account})` pushes `POST <resource>/sync`, then, only after a push with no failure, pulls `GET <resource>` pages until `has_more` is false.
2. `run` never throws; read `SyncReport.failure`. It needs a network driver and the `sync_cursors` table: list `CreateSyncCursorsTable` in `Migrator().run`, or point `SyncLedger(table: ...)` at your own five-column table.
3. `pending` returns rows oldest first, filtered by a strict `>` on `sinceMillis`. Only the push advances the mark; an adopted row never does. `adoptRow` answers `false` for a row it cannot read.

## Recipes

A migration, model and save:

```dart
import 'package:magic/magic.dart';
import 'package:magic_local_storage/magic_local_storage.dart';

class CreateNotesTable extends Migration {
  @override
  String get name => '20261114120000_create_notes_table';

  @override
  void up() {
    Schema.create('notes', (Blueprint table) {
      table.id();
      table.string('title');
      table.timestamps();
    });
  }

  @override
  void down() {
    Schema.dropIfExists('notes');
  }
}

class Note extends Model with HasTimestamps, InteractsWithPersistence {
  @override
  String get table => 'notes';

  @override
  String get resource => 'notes';

  @override
  List<String> get fillable => ['title'];

  @override
  bool get useLocal => true;

  @override
  bool get useRemote => false;
}

Future<void> saveNote() async {
  await Migrator().run([CreateNotesTable()]);

  await (Note()..fill({'title': 'First'})).save();
}
```

Query and transact:

```dart
import 'package:magic_local_storage/magic_local_storage.dart';

Future<void> archive(int id) async {
  await DB.transaction(() async {
    final Map<String, dynamic>? row = await DB.table('notes').where('id', id).first();

    await DB.table('archive').insert({'title': row?['title']});
    await DB.table('notes').where('id', id).delete();
  });
}
```

Seed with a factory:

```dart
import 'package:magic/magic.dart';
import 'package:magic_local_storage/magic_local_storage.dart';

class Note extends Model with InteractsWithPersistence {
  @override
  String get table => 'notes';

  @override
  String get resource => 'notes';

  @override
  List<String> get fillable => ['title'];

  @override
  bool get useLocal => true;

  @override
  bool get useRemote => false;
}

class NoteFactory extends Factory<Note> {
  @override
  Factory<Note> newFactory() => NoteFactory();

  @override
  Note newInstance() => Note();

  @override
  Map<String, dynamic> definition() => {'title': faker.lorem.sentence()};
}

class NoteSeeder extends Seeder {
  @override
  Future<void> run() async {
    await NoteFactory().count(10).create();
  }
}

Future<void> seed() => Seeding.run([NoteSeeder()]);
```

## Generators

`dart run magic:dowel make:migration create_notes_table --create=notes` writes `lib/database/migrations/m_<timestamp>_create_notes_table.dart`; `make:seeder Note` and `make:factory Note` write `lib/database/seeders/note_seeder.dart` and `lib/database/factories/note_factory.dart`. Core's `make:model -m -f -s` calls them through the dowel registry and prints a hint naming this package when it is absent. A generated factory throws `UnimplementedError` until you import the model and implement `newInstance()`. Nothing registers a generated migration: add it to `Migrator().run`.

## Testing

In `setUp()` call `MagicApp.reset()` and `Magic.flush()`, set an in-memory connection with `DatabaseManager().setConnection(sqlite3.openInMemory())` (add `sqlite3` as a dev dependency), bind the store with `MagicApp.instance.singleton('local_model_store', () => QueryModelStore())`, then run the migrations the test needs. `:memory:` does not work as a `database` config value on native platforms.

`DatabaseManager` is a singleton that `Magic.flush()` does not clear: call `DatabaseManager().dispose()` in `tearDown()`. Call `Log.fake()` before `Seeding.run`, and `Http.fake` plus `Http.unfake()` around a `SyncFeed` test. A `useLocal` test with no store bound fails with the `StateError`, which is the behaviour to assert when that is the point.

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';
import 'package:magic_local_storage/magic_local_storage.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  setUp(() {
    MagicApp.reset();
    Magic.flush();

    DatabaseManager().setConnection(sqlite3.openInMemory());
    MagicApp.instance.singleton('local_model_store', () => QueryModelStore());
  });

  tearDown(() {
    DatabaseManager().dispose();
  });

  test('the table accepts a row', () async {
    DB.statement('CREATE TABLE notes (id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT)');

    await DB.table('notes').insert({'title': 'First'});

    expect(await DB.table('notes').count(), 1);
  });
}
```
