# Serverpod module: serverpod_filters

A high-performance filter parsing and query engine for Serverpod. It converts serializable filter expressions (including relational dot-notation traversals and prefix logical operators `&`, `|`, `!`) directly into native Serverpod `WhereExpression` / `Expression` queries.

Key features:
- **Pure Serverpod ORM Integration:** Translates filter expressions into Serverpod `Expression`s (`WhereExpressionBuilder`) for `find`, `findFirstRow`, `count`, and `deleteWhere`. No raw SQL required.
- **Zero Field Metadata Maintenance:** Automatically inspects Serverpod's generated `Table` descriptors (`table.columns` and `table.getRelationTable`). No manual dictionaries or schemas to keep in sync.
- **Relational Field Traversal:** Supports dot-notation paths (`customer.country.code`) using Serverpod's built-in relation tables.
- **Filter Syntax:** Polish prefix notation (`&`, `|`, `!`), implicit sequential `AND`s, comparisons (`=`, `!=`, `<`, `<=`, `>`, `>=`), collections (`in`, `not in`), string patterns (`like`, `ilike`, `not like`, `not ilike`), and conditional equals (`=?`).

Working loop, run from `serverpod_filters_server`:

- Add models (`.spy.yaml`) and endpoints under `lib/src/`.
- `serverpod generate` after every change to a model or an endpoint.
- `serverpod create-migration` after changing a model with a `table` (add `--force` for destructive changes). The migration ships with the module and is applied by the projects that depend on it.
- `dart analyze` and `dart format`.
- `dart test` to run the tests. They use `withServerpod` from the generated test tools together with `config/test.yaml`. No Docker is needed: `config/test.yaml` sets `database.dataPath`, so Serverpod starts and manages the test database (an embedded PostgreSQL) itself.

Prefix table names with the module name (for example `serverpod_filters_orders`) so they cannot collide with the tables of the projects that use this module.

NEVER edit generated code. `serverpod_filters_server/lib/src/generated/` and the whole `serverpod_filters_client` package are rewritten by the code generator. Change the models, the endpoints or `lib/serverpod_filters_server.dart` instead.

Migrations are a narrow exception: the `migration.sql` of a generated migration MAY be edited by hand when the generated SQL would lose data — to add a data transformation, or to reach a destructive change through non-destructive steps. Never touch the other files in the migration directory, and keep the schema the SQL ends up with identical to `definition.sql` — new databases are created from that file and never run `migration.sql`.

Projects that depend on this module reference its types as `module:serverpod_filters:MyType`, where `serverpod_filters` is the `nickname` in `config/generator.yaml`.
