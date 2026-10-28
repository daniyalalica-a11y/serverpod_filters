import 'dart:convert';

import 'package:serverpod/serverpod.dart';
// ignore: implementation_imports
import 'package:serverpod_database/src/adapters/postgres/value_encoder.dart';
import 'package:serverpod_filters_server/serverpod_filters_server.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Mock Table Definitions (mirror Serverpod-generated Table classes)
// ---------------------------------------------------------------------------

class MockCountryTable extends Table<int> {
  MockCountryTable({super.tableRelation}) : super(tableName: 'nation') {
    code = ColumnString('code', this);
    name = ColumnString('name', this);
  }

  late final ColumnString code;
  late final ColumnString name;

  @override
  List<Column> get columns => [id, code, name];
}

class MockCustomerTable extends Table<int> {
  MockCustomerTable({super.tableRelation}) : super(tableName: 'client') {
    name = ColumnString('name', this);
    countryId = ColumnInt('country_id', this);
    country = createRelationTable(
      relationFieldName: 'country',
      field: countryId,
      foreignField: ColumnInt('id', MockCountryTable()),
      tableRelation: tableRelation,
      createTable: (foreignTableRelation) =>
          MockCountryTable(tableRelation: foreignTableRelation),
    );
  }

  late final ColumnString name;
  late final ColumnInt countryId;
  late final MockCountryTable country;

  @override
  List<Column> get columns => [id, name, countryId];

  @override
  Table? getRelationTable(String relationField) {
    if (relationField == 'country') return country;
    return null;
  }
}

class MockOrderTable extends Table<int> {
  MockOrderTable() : super(tableName: 'order') {
    state = ColumnString('state', this);
    amount = ColumnDouble('amount', this);
    customerId = ColumnInt('customer_id', this);
    customer = createRelationTable(
      relationFieldName: 'customer',
      field: customerId,
      foreignField: ColumnInt('id', MockCustomerTable()),
      createTable: (foreignTableRelation) =>
          MockCustomerTable(tableRelation: foreignTableRelation),
    );
  }

  late final ColumnString state;
  late final ColumnDouble amount;
  late final ColumnInt customerId;
  late final MockCustomerTable customer;

  @override
  List<Column> get columns => [id, state, amount, customerId];

  @override
  Table? getRelationTable(String relationField) {
    if (relationField == 'customer') return customer;
    return null;
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() {
    ValueEncoder.set(const PostgresValueEncoder());
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('FilterParser', () {
    const parser = FilterParser();

    test('parses empty filter into TrueFilter', () {
      expect(parser.parse([]), equals(const TrueFilter()));
      expect(parser.parse('[]'), equals(const TrueFilter()));
      expect(parser.parse(null), equals(const TrueFilter()));
    });

    test('parses single criterion', () {
      final node = parser.parse([
        ['state', '=', 'draft'],
      ]);

      expect(
        node,
        equals(
          const FilterCriterion(
            field: 'state',
            operator: FilterOperator.equals,
            value: 'draft',
          ),
        ),
      );
    });

    test('parses implicit AND on sequential criteria', () {
      final node = parser.parse([
        ['state', '=', 'draft'],
        ['amount', '>', 100],
      ]);

      expect(node, isA<AndFilter>());
      final andNode = node as AndFilter;
      expect(andNode.children.length, equals(2));
      expect((andNode.children[0] as FilterCriterion).field, equals('state'));
      expect((andNode.children[1] as FilterCriterion).field, equals('amount'));
    });

    test('parses prefix Polish notation (& and |)', () {
      final filter = [
        '|',
        ['state', '=', 'draft'],
        '&',
        ['amount', '>', 500],
        ['state', '=', 'posted'],
      ];

      final node = parser.parse(filter);
      expect(node, isA<OrFilter>());
      final orNode = node as OrFilter;
      expect(orNode.children.length, equals(2));
      expect((orNode.children[0] as FilterCriterion).field, equals('state'));

      expect(orNode.children[1], isA<AndFilter>());
      final andChild = orNode.children[1] as AndFilter;
      expect(andChild.children.length, equals(2));
      expect((andChild.children[0] as FilterCriterion).field, equals('amount'));
      expect((andChild.children[1] as FilterCriterion).field, equals('state'));
    });

    test('parses prefix NOT (!)', () {
      final filter = [
        '!',
        ['state', '=', 'cancelled'],
      ];
      final node = parser.parse(filter);

      expect(node, isA<NotFilter>());
      final notNode = node as NotFilter;
      expect((notNode.child as FilterCriterion).field, equals('state'));
    });

    test('simplifies double negation', () {
      final filter = [
        '!',
        '!',
        ['state', '=', 'confirmed'],
      ];
      final node = parser.parse(filter);
      expect(node, isA<FilterCriterion>());
      expect((node as FilterCriterion).field, equals('state'));
    });

    test('parses relational dot-notation field safely', () {
      final filter = [
        ['customer.country.code', '=', 'US'],
      ];
      final node = parser.parse(filter);
      expect(node, isA<FilterCriterion>());
      final criterion = node as FilterCriterion;
      expect(criterion.isRelational, isTrue);
      expect(criterion.pathSegments, equals(['customer', 'country', 'code']));
      expect(criterion.rootField, equals('customer'));
      expect(criterion.targetField, equals('code'));
    });

    test('throws on syntax error: missing operand for prefix operator', () {
      expect(
        () => parser.parse([
          '&',
          ['state', '=', 'draft'],
        ]),
        throwsA(isA<FilterParseException>()),
      );
    });

    test('throws on syntax error: invalid field format', () {
      expect(
        () => parser.parse([
          ['invalid field; DROP TABLE', '=', 'val'],
        ]),
        throwsA(isA<FilterParseException>()),
      );
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('ServerpodFilters (Direct Where Clause Compilation)', () {
    late MockOrderTable table;

    setUp(() {
      table = MockOrderTable();
    });

    test(
      'translates simple equality and comparison into Serverpod Expression',
      () {
        final filter = [
          '&',
          ['state', '=', 'done'],
          ['amount', '>=', 150.0],
        ];

        final expr = ServerpodFilters.toWhere(filter, table);
        expect(expr, isA<Expression>());
        final sqlString = expr.toString();
        expect(sqlString, contains('"order"."state" ='));
        expect(sqlString, contains('AND'));
        expect(sqlString, contains('"order"."amount" >='));
      },
    );

    test('coerces JSON integer comparisons for ColumnDouble', () {
      final filter = jsonDecode('[["amount", ">", 1000]]');

      final expression = ServerpodFilters.toWhere(filter, table);

      expect(expression.toString(), contains('"order"."amount" >'));
    });

    test('accepts whole-number doubles for ColumnInt comparisons', () {
      final filter = jsonDecode('[["customer_id", ">", 1.0]]');

      final expression = ServerpodFilters.toWhere(filter, table);

      expect(expression.toString(), contains('"order"."customer_id" >'));
    });

    test('rejects fractional values for ColumnInt comparisons', () {
      final filter = jsonDecode('[["customer_id", ">", 1.5]]');

      expect(
        () => ServerpodFilters.toWhere(filter, table),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.message,
            'message',
            contains('Expected an integer value'),
          ),
        ),
      );
    });

    test('handles null equality (IS NULL and IS NOT NULL)', () {
      final filterNull = [
        ['state', '=', null],
      ];
      final exprNull = ServerpodFilters.toWhere(filterNull, table);
      expect(exprNull.toString(), contains('"order"."state" IS NULL'));

      final filterNotNull = [
        ['state', '!=', null],
      ];
      final exprNotNull = ServerpodFilters.toWhere(filterNotNull, table);
      expect(exprNotNull.toString(), contains('"order"."state" IS NOT NULL'));
    });

    test('handles collection in and not in operators', () {
      final filterIn = [
        [
          'state',
          'in',
          ['draft', 'pending'],
        ],
      ];
      final exprIn = ServerpodFilters.toWhere(filterIn, table);
      expect(exprIn.toString(), contains('IN'));

      final filterNotIn = [
        [
          'state',
          'not in',
          ['cancelled', 'rejected'],
        ],
      ];
      final exprNotIn = ServerpodFilters.toWhere(filterNotIn, table);
      expect(exprNotIn.toString(), contains('NOT IN'));
    });

    test('handles JSON-decoded collection values for ColumnString', () {
      final filter = jsonDecode('[["state", "in", ["draft", "pending"]]]');
      final expression = ServerpodFilters.toWhere(filter, table);
      expect(expression.toString(), contains('IN'));
    });

    // ── Bug fix: JSON-decoded num coercion for ColumnInt / ColumnDouble ──
    test(
      'handles JSON-decoded numeric collections for ColumnInt (num → int coercion)',
      () {
        // jsonDecode returns List<dynamic> where integers are Dart ints, but
        // mixing with doubles (e.g. [1, 2.0]) would produce nums. We simulate
        // the common case of a JSON-decoded int list reaching a ColumnInt filter.
        final filter = jsonDecode('[["customer_id", "in", [1, 2, 3]]]');
        final expression = ServerpodFilters.toWhere(filter, table);
        expect(expression.toString(), contains('IN'));
      },
    );

    test(
      'handles JSON-decoded numeric collections for ColumnDouble (num → double coercion)',
      () {
        // Simulate JSON-decoded amounts: [100, 200] arrives as List<int>
        // but the column expects double — the coercion must upcast safely.
        final filter = jsonDecode('[["amount", "in", [100, 200, 300]]]');
        final expression = ServerpodFilters.toWhere(filter, table);
        expect(expression.toString(), contains('IN'));
      },
    );

    test('handles string pattern matching (like and ilike)', () {
      final filterLike = [
        ['state', 'like', 'd%'],
      ];
      final exprLike = ServerpodFilters.toWhere(filterLike, table);
      expect(exprLike.toString(), contains('LIKE'));

      final filterIlike = [
        ['state', 'ilike', 'd%'],
      ];
      final exprIlike = ServerpodFilters.toWhere(filterIlike, table);
      expect(exprIlike.toString(), contains('ILIKE'));
    });

    test('handles not like and not ilike operators', () {
      final exprNotLike = ServerpodFilters.toWhere(
        [
          ['state', 'not like', 'd%'],
        ],
        table,
      );
      expect(exprNotLike.toString(), contains('NOT LIKE'));

      final exprNotIlike = ServerpodFilters.toWhere(
        [
          ['state', 'not ilike', 'd%'],
        ],
        table,
      );
      expect(exprNotIlike.toString(), contains('NOT ILIKE'));
    });

    // ── Bug fix: =like and =ilike semantic distinction ──
    test('handles =like and =ilike (exact literal operators)', () {
      // =like → case-sensitive exact match → uses LIKE
      final exprExactLike = ServerpodFilters.toWhere(
        [
          ['state', '=like', 'draft'],
        ],
        table,
      );
      expect(exprExactLike.toString(), contains('LIKE'));

      // =ilike → case-insensitive exact match → uses ILIKE
      final exprExactIlike = ServerpodFilters.toWhere(
        [
          ['state', '=ilike', 'Draft'],
        ],
        table,
      );
      expect(exprExactIlike.toString(), contains('ILIKE'));
    });

    // ── Bug fix: =? non-null path now actually filters (was dead code) ──
    test('handles conditional equals =? operator', () {
      // When value is null/empty/false → no-op TRUE
      final filterNoop = [
        ['state', '=?', ''],
      ];
      final exprNoop = ServerpodFilters.toWhere(filterNoop, table);
      expect(exprNoop.toString(), equals('TRUE'));

      final filterNoopNull = [
        ['state', '=?', null],
      ];
      final exprNoopNull = ServerpodFilters.toWhere(filterNoopNull, table);
      expect(exprNoopNull.toString(), equals('TRUE'));

      final filterNoopFalse = [
        ['state', '=?', false],
      ];
      final exprNoopFalse = ServerpodFilters.toWhere(filterNoopFalse, table);
      expect(exprNoopFalse.toString(), equals('TRUE'));

      // When value is a real non-empty string → actually filters (was broken)
      final filterActive = [
        ['state', '=?', 'draft'],
      ];
      final exprActive = ServerpodFilters.toWhere(filterActive, table);
      final sql = exprActive.toString();
      // Must produce a real WHERE clause, not a constant TRUE
      expect(sql, isNot(equals('TRUE')));
      expect(sql, contains('"order"."state" ='));
    });

    test('preserves nested relations when field and table names differ', () {
      final filter = [
        ['customer.country.code', '=', 'US'],
      ];

      final expr = ServerpodFilters.toWhere(filter, table);

      expect(expr, isA<Expression>());
      expect(
        expr.toString(),
        equals(
          '"order_customer_client_country_nation"."code" = \'US\'',
        ),
      );
    });

    test('where() builder returns WhereExpressionBuilder callback', () {
      final filter = [
        ['state', '=', 'draft'],
      ];

      final builder = ServerpodFilters.where<MockOrderTable>(filter);
      final expr = builder(table);
      expect(expr, isA<Expression>());
      expect(expr.toString(), contains('"order"."state" ='));
    });

    test('FilterEngine alias works identically', () {
      final filter = [
        ['state', '=', 'draft'],
      ];
      final expr = FilterEngine.toWhere(filter, table);
      expect(expr.toString(), contains('"order"."state" ='));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Security: filter-level allowedFields whitelist
  // ─────────────────────────────────────────────────────────────────────────
  group('ServerpodFilters – allowedFields security whitelist', () {
    late MockOrderTable table;

    setUp(() {
      table = MockOrderTable();
    });

    test(
      'non-strict: silently replaces unlisted criteria with TRUE (no-op)',
      () {
        // 'state' is allowed, 'amount' is NOT — but non-strict so no exception.
        final expr = ServerpodFilters.toWhere(
          [
            '&',
            ['state', '=', 'draft'],
            ['amount', '>=', 100.0],
          ],
          table,
          allowedFields: {'state'},
        );
        final sql = expr.toString();
        // state criterion is present
        expect(sql, contains('"order"."state" ='));
        // amount criterion is replaced with TRUE and then ANDed with state,
        // so the final SQL should NOT contain an amount comparison
        expect(sql, isNot(contains('"order"."amount"')));
      },
    );

    test(
      'strict: throws FilterValidationException for unlisted field',
      () {
        expect(
          () => ServerpodFilters.toWhere(
            [
              ['amount', '>=', 100.0],
            ],
            table,
            allowedFields: {'state'},
            strict: true,
          ),
          throwsA(isA<FilterValidationException>()),
        );
      },
    );

    test(
      'strict: does NOT throw when all fields are in allowedFields',
      () {
        expect(
          () => ServerpodFilters.toWhere(
            [
              '&',
              ['state', '=', 'draft'],
              ['amount', '>=', 100.0],
            ],
            table,
            allowedFields: {'state', 'amount'},
            strict: true,
          ),
          returnsNormally,
        );
      },
    );

    test('allowedFields matching is case-insensitive', () {
      // 'State' (capitalized) should match 'state' in the whitelist
      expect(
        () => ServerpodFilters.toWhere(
          [
            ['state', '=', 'draft'],
          ],
          table,
          allowedFields: {'State', 'Amount'},
          strict: true,
        ),
        returnsNormally,
      );
    });

    test('where() builder forwards allowedFields and strict', () {
      // Strict mode through the builder callback
      expect(
        () {
          final builder = ServerpodFilters.where<MockOrderTable>(
            [
              ['amount', '>=', 100.0],
            ],
            allowedFields: {'state'},
            strict: true,
          );
          builder(table); // validation happens at build time
        },
        throwsA(isA<FilterValidationException>()),
      );
    });

    test('no allowedFields → all fields are permitted (backward compat)', () {
      // Without allowedFields, every field must work as before.
      expect(
        () => ServerpodFilters.toWhere(
          [
            '&',
            ['state', '=', 'draft'],
            ['amount', '>=', 100.0],
            ['customer.country.code', '=', 'US'],
          ],
          table,
        ),
        returnsNormally,
      );
    });

    test('allowedFields allows relational dot-notation paths', () {
      expect(
        () => ServerpodFilters.toWhere(
          [
            ['customer.country.code', '=', 'US'],
          ],
          table,
          allowedFields: {'customer.country.code'},
          strict: true,
        ),
        returnsNormally,
      );
    });
  });
}
