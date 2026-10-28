## 1.1.0

### Breaking changes
- `FilterExpressionTranslator.translate()` now accepts optional `allowedFields` and `strict`
  parameters. Existing call sites with positional arguments are unaffected — both parameters
  are named and have default values.

### New features
- **Filter-level security whitelist** (`allowedFields` + `strict`) added to
  `FilterExpressionTranslator.translate()`, `ServerpodFilters.toWhere()`, and
  `ServerpodFilters.where()`. Unknown fields are silently treated as `TRUE` by default;
  setting `strict: true` throws `FilterValidationException` instead.
- New `FilterValidationException` class (analogous to `SortValidationException`)
  exported from the top-level library.
- `=like` (`exactLike`) and `=ilike` (`exactIlike`) operators are now semantically
  distinguished from `like` / `ilike` with dedicated `_applyExactLike` /
  `_applyExactIlike` methods and proper documentation.

### Bug fixes
- **`=?` (conditionalEquals) non-null path was unreachable.** The `switch` contained a
  redundant `conditionalEquals` case that returned `Constant.bool(true)`, shadowing the
  early-exit that correctly called `_applyEquals`. The redundant branch has been removed;
  a non-empty `=?` value now correctly applies equality filtering.
- **`inSet` / `notInSet` crash on JSON-decoded `num` values.** `_typedSet` has been
  replaced by `_coercedSet`, which applies safe numeric coercion (`num.toInt()` /
  `num.toDouble()`) so that JSON-decoded integer lists work for both `ColumnInt` and
  `ColumnDouble` columns without type errors.

### Internal improvements
- Translator rewritten to use exhaustive Dart 3 `switch` expressions, eliminating the
  mixed early-return + `switch` control flow that caused the `conditionalEquals` dead code.
- `_coercedSet` adds a descriptive error message with column name and expected type when
  coercion is not possible.

## 1.0.0

- Initial version.
