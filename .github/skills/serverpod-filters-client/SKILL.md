---
name: serverpod-filters-client
description: "Use when building Flutter or Dart client requests for a Serverpod endpoint that accepts serverpod_filters input; create correctly shaped filter and sort values."
---

# Sending filters from a client

When a Serverpod endpoint accepts filter or sort arguments for
`serverpod_filters`, create values using the library's grammar and pass them as
the endpoint arguments through the generated Serverpod client.

## Send structured values

Build filters as nested Dart lists. Each criterion must be exactly
`[field, operator, value]`. For example:

```dart
final filter = <dynamic>[
  ['status', '=', 'active'],
  ['amount', '>=', 100],
];

final result = await client.order.listOrders(filter: filter);
```

Sequential criteria are combined with `AND`. Use prefix operators for other
logic: `&` and `|` each require two following operands, and `!` requires one.

```dart
final filter = <dynamic>[
  '|',
  ['status', '=', 'draft'],
  '&',
  ['amount', '>', 1000],
  ['priority', '=', 'high'],
];
```

Pass the list itself to the generated RPC method when its endpoint parameter
accepts the filter value. Do not JSON-encode it first unless the endpoint
explicitly declares a `String` parameter or the transport is a custom API that
expects JSON text. Match the generated method's actual parameter names and
types.

## Operators and values

Use only supported operators:

- Comparisons: `=`, `!=`, `>`, `>=`, `<`, `<=`
- Collections: `in`, `not in` (value must be a list/iterable)
- Patterns: `like`, `not like`, `ilike`, `not ilike`, `=like`, `=ilike`
- Optional equality: `=?`

Examples:

```dart
['notes', '=', null] // Match null
['state', 'in', ['draft', 'pending']]
['name', 'ilike', '%corp%']
['category', '=?', selectedCategory] // Skips when null, false, or ''
```

For `like` and `ilike`, include `%` in the value where wildcard matching is
desired. `=like` and `=ilike` are literal matching operators; they do not add
wildcards.

## Field paths

Use the server model's field names, optionally with dot notation across
singular relations:

```dart
['customer.country.code', '=', 'US']
```

Only send fields the server endpoint allows. The server's `allowedFields`
configuration is authoritative; client-side hiding or validation is not an
authorization boundary. Dot paths do not express one-to-many collection
quantifiers such as `any` or `count`.

## Sorting

Send a supported sort value through the endpoint's sort parameter. Common
formats include:

```dart
final sort = '-createdAt, amount:asc';
// Or:
final sort = ['-createdAt', 'amount:asc'];
// Or:
final sort = [
  ['createdAt', 'desc'],
  ['amount', 'asc'],
];

final result = await client.order.listOrders(filter: filter, sort: sort);
```

Sort strings support direction prefixes (`-field`, `+field`), suffixes
(`field desc`), and delimiters (`field:asc`). The parser also accepts supported
map formats such as `{'selector': 'amount', 'desc': true}`. Use actual server
field paths or names explicitly mapped by the server.

## Client implementation guidance

- Keep filter-building code returning the nested list structure; do not
  flatten logical trees or stringify values for a generated RPC call.
- Use Dart values matching the field type: numbers for numeric columns, strings
  for text, booleans for boolean fields, `null` for null checks, and lists for
  membership checks.
- Omit a criterion when the user has not supplied a value, or use `=?` when
  its null/false/empty-string skip behavior is intended.
- Treat all client-generated criteria as untrusted. The server must still
  validate fields, enforce authorization, and apply safe defaults.
- Do not send Odoo domains or arbitrary map-based filters; adapt them to the
  documented criterion and prefix-operator grammar first.
