# serverpod_filters

A high-performance, serializable filter parsing and query sorting engine for **Serverpod**. It compiles filter expressions (including relational dot-notation and Polish prefix combinators `&`, `|`, `!`) into native Serverpod `Expression` / `where:` clauses, and translates client sort specifications directly into native Serverpod `OrderByListBuilder` / `orderByList:` queries.

## Key Features

* **Pure Serverpod ORM:** Generates native Serverpod `Expression`s (`WhereExpressionBuilder`) and `Order` descriptors (`OrderByListBuilder`) for `find`, `findFirstRow`, `count`, and `deleteWhere`. No raw SQL required.
* **Zero Manual Metadata:** Automatically inspects Serverpod's generated `Table` descriptors (`table.columns` and `table.getRelationTable`). No schemas, dictionaries, or YAML configs to maintain.
* **Related Object Fields:** Resolves dot-notation paths through Serverpod relation table descriptors, for example `['customer.country.code', '=', 'US']`. These paths filter root rows; they do not load related objects. Collection relations need quantifiers such as `any`, `none`, `every`, or `count`, which plain dot paths do not express.
* **Prefix Polish & Implicit AND:** Supports Polish notation (`&`, `|`, `!`) as well as sequential criteria with implicit `AND`.
* **Every Client Sorting Format:** Handles string prefixes (`'-created_at'`), suffixes (`'amount desc'`), colon delimiters (`'name:asc'`), comma-delimited strings, 2-element tuples (`['name', 'desc']`), nested lists, and map formats (DevExtreme, AG-Grid, TanStack Table, key-value maps).
* **Security & Whitelisting:** Built-in column whitelisting (`allowedFields`), strict validation, and client field aliasing (`fieldMap`).
* **Database Agnostic:** Works with both PostgreSQL and SQLite.
* **Safe & Robust:** Protects against SQL injection by using Serverpod's strongly-typed column operations and validating identifier syntax.

---

## Installation

In your main Serverpod server project:

```yaml
dependencies:
  serverpod: 4.0.4
  serverpod_filters_server:
    path: path/to/serverpod_filters/serverpod_filters_server
```

---

## Quick Start & Usage

### In a Serverpod Endpoint

Use `ServerpodFilters.where(filter)` and `ServerpodFilters.orderByList(sort)` directly in Serverpod query methods:

```dart
import 'package:serverpod/serverpod.dart';
import 'package:serverpod_filters_server/serverpod_filters_server.dart';
import '../generated/protocol.dart';

class OrderEndpoint extends Endpoint {
  /// Fetches orders filtered and sorted dynamically from client input.
  Future<List<Order>> listOrders(
    Session session, {
    dynamic filter,
    dynamic sort,
    int? limit,
    int? offset,
  }) async {
    return await Order.db.find(
      session,
      where: ServerpodFilters.where(filter),
      orderByList: ServerpodFilters.orderByList(
        sort,
        defaultSort: '-id', // Fallback if no sort is specified
      ),
      limit: limit,
      offset: offset,
    );
  }

  /// Counts matching rows.
  Future<int> countOrders(Session session, {dynamic filter}) async {
    return await Order.db.count(
      session,
      where: ServerpodFilters.where(filter),
    );
  }

  /// Deletes rows matching a filter.
  Future<List<Order>> deleteOrders(Session session, {dynamic filter}) async {
    return await Order.db.deleteWhere(
      session,
      where: ServerpodFilters.where(filter),
    );
  }
}
```

---

## Filter Syntax & Operators

A filter can be provided as a Dart `List<dynamic>` or as a JSON string: `'[["status", "=", "posted"]]'`.
The parser accepts this library's list/tuple and prefix-operator grammar; it
does not parse Odoo domains or arbitrary map-based filter formats. Applications
can adapt another client format into this grammar or construct the exported
`FilterNode` AST before translating it.

For client-supplied filters, use an explicit field allowlist and strict
validation. In non-strict mode, a disallowed field becomes `TRUE`; inside an
`OR` expression this can broaden the result to every row.

```dart
where: ServerpodFilters.where(
  filter,
  allowedFields: {'status', 'amount', 'customer.country.code'},
  strict: true,
)
```

### 1. Simple Criteria
Each criterion is a 3-element list: `[field, operator, value]`.

```dart
// Equality
['status', '=', 'posted']

// Numeric comparisons
['amount', '>', 100.0]
['amount', '<=', 500.0]

// Pattern matching (case-sensitive and case-insensitive)
['name', 'like', 'Acme%']
['name', 'ilike', '%corp%']

// Collection membership
['state', 'in', ['draft', 'pending']]
['state', 'not in', ['cancelled', 'archived']]

// Null checks
['notes', '=', null]   // Compiles to IS NULL
['notes', '!=', null]  // Compiles to IS NOT NULL

// Conditional equality (ignores criterion if value is null, false, or empty string)
['category', '=?', filterInput]
```

### 2. Related Object Fields (Dot Notation)
Traverse through singular object relations defined in your Serverpod models:

```dart
// Filter orders through the Order -> Customer -> Country object relations:
['customer.country.code', '=', 'US']
```

The translator resolves each relation segment using Serverpod's generated table
descriptors and applies the predicate to the related column. Serverpod's query
builder handles the relation reference in the query. This filters matching
orders; it does not populate `customer` or `country` in the returned objects.
Use `include` separately when the result needs related objects:

```dart
final orders = await Order.db.find(
  session,
  where: ServerpodFilters.where([
    ['customer.country.code', '=', 'US'],
  ]),
  include: Order.include(
    customer: Customer.include(
      country: Country.include(),
    ),
  ),
);
```

This dot-path syntax is for traversing object relations. A one-to-many
collection predicate has different semantics: for example, “orders with any
line whose SKU is X” needs an existential `any` condition. Serverpod exposes
`any`, `none`, `every`, and `count` for collection relations, but this library's
current filter grammar does not encode those quantifiers. Do not use a plain
path such as `lines.sku` as a substitute; use Serverpod's typed relation
predicate directly or add a filter input adapter/AST node that models the
quantifier explicitly.

### 3. Logical Combinators

#### Implicit AND (Default)
Sequences of criteria are joined with `AND` automatically:
```dart
[
  ['status', '=', 'active'],
  ['amount', '>=', 500.0],
  ['customer.country.code', '=', 'US'],
]
```

#### Prefix Polish Notation (`&`, `|`, `!`)
Prefix notation allows expressing arbitrary boolean trees:
```dart
[
  '|',
  ['status', '=', 'draft'],
  '&',
  ['amount', '>', 1000.0],
  ['priority', '=', 'high'],
]
// Evaluates to: (status = 'draft') OR (amount > 1000.0 AND priority = 'high')
```

#### Inversion (`!`)
```dart
[
  '!',
  ['status', '=', 'cancelled']
]
// Evaluates to: NOT (status = 'cancelled')
```

---

## Supported Operators Cheat Sheet

| Operator | Syntax | Generated Serverpod Operation |
|---|---|---|
| `=` | `['field', '=', val]` | `t.column.equals(val)` (or `isNull()`) |
| `!=` | `['field', '!=', val]` | `t.column.notEquals(val)` (or `isNotNull()`) |
| `>` | `['field', '>', val]` | `t.column > val` |
| `>=` | `['field', '>=', val]` | `t.column >= val` |
| `<` | `['field', '<', val]` | `t.column < val` |
| `<=` | `['field', '<=', val]` | `t.column <= val` |
| `in` | `['field', 'in', [...]]` | `t.column.inSet({...})` |
| `not in` | `['field', 'not in', [...]]` | `t.column.notInSet({...})` |
| `like` | `['field', 'like', 'A%']` | `t.column.like('A%')` |
| `ilike` | `['field', 'ilike', '%a%']` | `t.column.ilike('%a%')` |
| `not like` | `['field', 'not like', 'A%']` | `t.column.notLike('A%')` |
| `not ilike` | `['field', 'not ilike', '%a%']` | `t.column.notIlike('%a%')` |
| `=?` | `['field', '=?', val]` | `col.equals(val)` if set, else `TRUE` |

---

## Advanced Sorting Engine

`ServerpodSorting` (also accessible via `ServerpodFilters`) parses virtually every format of client-side sorting specifications and compiles them directly into Serverpod `OrderByListBuilder` callbacks (`List<Order>`).

### 1. Supported Client Sort Formats

#### String Formats
```dart
// Simple ascending:
'createdAt'

// Prefixed direction (REST / Django / Google API style):
'-createdAt'  // Descending
'+createdAt'  // Ascending

// Direction suffix (SQL / OData style):
'amount desc'
'name asc'

// Delimited syntax:
'amount:desc'
'createdAt/asc'

// Multi-field comma-separated (ideal for URL query parameters):
'-createdAt, amount:asc, customer.country.name:desc'
```

#### List / Array Formats
```dart
// List of field strings:
['state', '-amount', 'customer.country.name:desc']

// 2-element tuples [field, direction]:
['amount', 'desc']
['amount', -1]       // -1 = descending, 1 = ascending
['amount', true]     // true = descending, false = ascending

// Nested list of tuples:
[
  ['state', 'asc'],
  ['amount', 'desc'],
  ['customer.country.code', 'desc'],
]
```

#### Map / JSON Object Formats
```dart
// Standard property maps:
{'field': 'amount', 'direction': 'desc'}
{'field': 'createdAt', 'order': 'asc'}

// DevExtreme format:
{'selector': 'amount', 'desc': true}

// AG Grid format:
{'colId': 'amount', 'sort': 'desc'}

// TanStack / React Table format:
{'id': 'amount', 'desc': true}

// Key-value dictionary:
{
  'state': 'asc',
  'amount': 'desc',
  'customer.country.code': -1,
}

// Array of maps:
[
  {'field': 'state', 'direction': 'asc'},
  {'field': 'amount', 'direction': 'desc'},
]
```

#### JSON Strings
Any of the above formats serialized as JSON:
```dart
'["state", "-amount"]'
'[{"field": "amount", "direction": "desc"}]'
'{"state": "asc", "amount": "desc"}'
```

---

### 2. Related-Field Sorting (Dot Notation)

Sort seamlessly across relational tables defined in your Serverpod models:

```dart
// Traverse Order -> Customer -> Country:
ServerpodSorting.orderByList('-customer.country.name')
```

The translator resolves relation paths against Serverpod table descriptors.
As with filtering, a relation path references related data in the query; it
does not include related objects in the returned rows.

---

### 3. Whitelisting, Aliasing & Defaults

#### Column Whitelisting (`allowedFields`)
Prevent clients from sorting by unindexed or sensitive columns:
```dart
ServerpodFilters.orderByList(
  clientSort,
  allowedFields: {'id', 'amount', 'createdAt', 'customer.name'},
  strict: true, // Throws SortValidationException if an unauthorized field is requested
)
```

#### Client Field Remapping (`fieldMap`)
Map client-friendly field names to internal database paths:
```dart
ServerpodFilters.orderByList(
  clientSort,
  fieldMap: {
    'country': 'customer.country.name',
    'total': 'amount',
  },
)
```

#### Default Fallback
Specify a default sort if the client sends `null` or an empty sort:
```dart
ServerpodFilters.orderByList(
  clientSort,
  defaultSort: '-createdAt', // Used only if clientSort is empty/null
)

// Or chain with standard Dart null-coalescing:
ServerpodFilters.orderByList(clientSort) ?? ((t) => [t.id.desc()])
```

---

## Zero Field Metadata Maintenance

Unlike other query tools that require manually maintaining YAML dictionaries, reflection registrations, or column mappings:

1. You define models in `.spy.yaml` as usual.
2. Run `serverpod generate`.
3. `ServerpodFilters` and `ServerpodSorting` dynamically read `table.columns` and `table.getRelationTable(...)` from Serverpod's generated classes at runtime.
4. Field names are matched automatically across snake_case and camelCase (e.g. `country_code` and `countryCode` both resolve properly).
