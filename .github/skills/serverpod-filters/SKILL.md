---
name: serverpod-filters
description: "Use when implementing Serverpod queries with serverpod_filters: parsing client filters, filtering or sorting records, traversing relations, or validating client-controlled query criteria."
---

# Using serverpod_filters

Use this library to compile serializable filter and sort input into native
Serverpod ORM expressions. Prefer its public API over raw SQL or custom dynamic
query-building logic.

## Filter and sort a query

Import `package:serverpod_filters_server/serverpod_filters_server.dart`. In an
endpoint, pass client filter and sort values to the library:

```dart
return Order.db.find(
  session,
  where: ServerpodFilters.where(
    filter,
    allowedFields: {'status', 'amount', 'customer.country.code'},
    strict: true,
  ),
  orderByList: ServerpodFilters.orderByList(
    sort,
    allowedFields: {'createdAt', 'amount'},
    defaultSort: '-createdAt',
    strict: true,
  ),
  limit: limit,
  offset: offset,
);
```

`where` returns a `WhereExpressionBuilder` usable with Serverpod's `find`,
`findFirstRow`, `count`, and `deleteWhere`. `orderByList` returns a callback for
`find`, `findFirstRow`, and `deleteWhere`; it returns `null` when the resolved
sort is empty and no default is specified.

Use `ServerpodFilters.toWhere(filter, table)` and
`ServerpodFilters.toOrderByList(sort, table)` when a concrete expression or
order list is needed instead. `FilterEngine` is an alias for
`ServerpodFilters`; `ServerpodSorting` exposes sorting independently.

## Filter grammar

Filters are Dart lists or JSON strings representing lists. Each criterion is a
three-element list: `[field, operator, value]`.

```dart
[
  ['status', '=', 'active'],
  ['amount', '>=', 100],
]
```

Sequential criteria are combined with implicit `AND`. Prefix Polish notation
supports `&` and `|` with two operands each, and `!` with one operand:

```dart
[
  '|',
  ['status', '=', 'draft'],
  '&',
  ['amount', '>', 1000],
  ['priority', '=', 'high'],
]
```

Supported operators: `=`, `!=`, `>`, `>=`, `<`, `<=`, `in`, `not in`, `like`,
`not like`, `ilike`, `not ilike`, `=like`, `=ilike`, and `=?`. Equality with
`null` checks for null. Collection operators expect an iterable. The `=?`
operator treats `null`, `false`, and `''` as a no-op; otherwise it applies
equality. `=like` and `=ilike` perform literal matches without adding wildcard
characters; `like` and `ilike` accept patterns such as `Acme%` and `%corp%`.

The parser does not accept arbitrary map-based filter formats or Odoo domains.
Adapt other client formats to this grammar before calling the library.

## Related fields

Dot notation traverses singular object relations, for example
`['customer.country.code', '=', 'US']`. Paths are resolved from Serverpod's
generated table descriptors; no field metadata dictionary is needed.

Relation paths filter root rows but do not load related objects. Use Serverpod's
`include` option when related objects are needed in returned results.

Do not use a plain path such as `lines.sku` to express a one-to-many condition.
The filter grammar does not model collection quantifiers such as `any`, `none`,
`every`, or `count`; use a typed Serverpod relation predicate or adapt the
input to an explicit collection-aware query.

## Sorting

`ServerpodFilters.orderByList` and `ServerpodSorting.orderByList` accept
multiple client formats, including strings, lists, tuples, maps, and JSON
strings:

- `'-createdAt, amount:asc'`
- `['state', '-amount']`
- `[['state', 'asc'], ['amount', 'desc']]`
- `{'selector': 'amount', 'desc': true}`

Use `defaultSort` when an empty client sort should fall back to a known order.
Use `fieldMap` to map client-facing sort names to database paths. Apply
`allowedFields` to the permitted paths and enable `strict: true` when client
input must be rejected if it requests an unauthorized field.

## Validate client input safely

For client-controlled filters and sorts, provide explicit, non-empty
`allowedFields` and set `strict: true`. Filter allowlists match case
insensitively. Without strict mode, a disallowed filter criterion becomes
`TRUE`; in an `OR` expression this can broaden results. An omitted or empty
allowlist does not restrict fields.

An empty or null filter matches all rows. Never pass an optional or untrusted
filter to `deleteWhere` without ensuring that an unrestricted operation is
intended.

Let parse, field-resolution, and strict-validation errors surface or handle
them explicitly at the application boundary. Do not silently turn invalid
input into an unrestricted query.

This library handles query criteria, not authorization, business rules, or
pagination limits; enforce those separately in the endpoint.
