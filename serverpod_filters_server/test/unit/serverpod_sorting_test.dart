import 'package:serverpod/serverpod.dart';
// ignore: implementation_imports
import 'package:serverpod_database/src/adapters/postgres/value_encoder.dart';
import 'package:serverpod_filters_server/serverpod_filters_server.dart';
import 'package:test/test.dart';

// Test Table Definitions representing Serverpod generated models
class MockCountryTable extends Table<int> {
  MockCountryTable({super.tableRelation}) : super(tableName: 'country') {
    code = ColumnString('code', this);
    name = ColumnString('name', this);
  }

  late final ColumnString code;
  late final ColumnString name;

  @override
  List<Column> get columns => [id, code, name];
}

class MockCustomerTable extends Table<int> {
  MockCustomerTable({super.tableRelation}) : super(tableName: 'customer') {
    name = ColumnString('name', this);
    countryId = ColumnInt('country_id', this);
    country = createRelationTable(
      relationFieldName: 'country',
      field: countryId,
      foreignField: ColumnInt('id', MockCountryTable()),
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

void main() {
  setUpAll(() {
    ValueEncoder.set(const PostgresValueEncoder());
  });

  group('SortParser', () {
    const parser = SortParser();

    test('parses empty and null sort into empty specification', () {
      expect(parser.parse(null).isEmpty, isTrue);
      expect(parser.parse('').isEmpty, isTrue);
      expect(parser.parse('   ').isEmpty, isTrue);
      expect(parser.parse([]).isEmpty, isTrue);
      expect(parser.parse({}).isEmpty, isTrue);
      expect(parser.parse('[]').isEmpty, isTrue);
      expect(parser.parse('{}').isEmpty, isTrue);
    });

    group('String inputs', () {
      test('parses simple field name as ascending', () {
        final spec = parser.parse('state');
        expect(spec.length, equals(1));
        expect(spec.first.field, equals('state'));
        expect(spec.first.direction, equals(SortDirection.ascending));
        expect(spec.first.isAscending, isTrue);
      });

      test('parses prefixed fields (+ and -)', () {
        final specDesc = parser.parse('-amount');
        expect(specDesc.first.field, equals('amount'));
        expect(specDesc.first.direction, equals(SortDirection.descending));
        expect(specDesc.first.isDescending, isTrue);

        final specAsc = parser.parse('+amount');
        expect(specAsc.first.field, equals('amount'));
        expect(specAsc.first.direction, equals(SortDirection.ascending));
      });

      test('parses suffix syntax (asc, desc, ASC, DESC, descending)', () {
        final spec1 = parser.parse('amount desc');
        expect(spec1.first.direction, equals(SortDirection.descending));

        final spec2 = parser.parse('amount ASC');
        expect(spec2.first.direction, equals(SortDirection.ascending));

        final spec3 = parser.parse('amount descending');
        expect(spec3.first.direction, equals(SortDirection.descending));
      });

      test('parses colon and slash delimiters (:asc, :desc, /desc)', () {
        final spec1 = parser.parse('amount:desc');
        expect(spec1.first.field, equals('amount'));
        expect(spec1.first.direction, equals(SortDirection.descending));

        final spec2 = parser.parse('amount/asc');
        expect(spec2.first.field, equals('amount'));
        expect(spec2.first.direction, equals(SortDirection.ascending));
      });

      test('parses comma-separated compound sort string', () {
        final spec = parser.parse(
          '-amount, state:asc, customer.country.name desc',
        );
        expect(spec.length, equals(3));
        expect(spec.criteria[0].field, equals('amount'));
        expect(spec.criteria[0].isDescending, isTrue);

        expect(spec.criteria[1].field, equals('state'));
        expect(spec.criteria[1].isAscending, isTrue);

        expect(spec.criteria[2].field, equals('customer.country.name'));
        expect(spec.criteria[2].isDescending, isTrue);
        expect(spec.criteria[2].isRelational, isTrue);
        expect(spec.criteria[2].rootField, equals('customer'));
        expect(spec.criteria[2].targetField, equals('name'));
      });
    });

    group('List inputs', () {
      test('parses 2-element tuple [field, direction]', () {
        final spec1 = parser.parse(['amount', 'desc']);
        expect(spec1.first.field, equals('amount'));
        expect(spec1.first.isDescending, isTrue);

        final spec2 = parser.parse(['amount', -1]);
        expect(spec2.first.isDescending, isTrue);

        final spec3 = parser.parse(['amount', 1]);
        expect(spec3.first.isAscending, isTrue);

        final spec4 = parser.parse(['amount', true]);
        expect(spec4.first.isDescending, isTrue);

        final spec5 = parser.parse(['amount', false]);
        expect(spec5.first.isAscending, isTrue);
      });

      test('parses list of field strings', () {
        final spec = parser.parse(['state', '-amount', 'customer.name:asc']);
        expect(spec.length, equals(3));
        expect(spec.criteria[0].field, equals('state'));
        expect(spec.criteria[0].isAscending, isTrue);
        expect(spec.criteria[1].field, equals('amount'));
        expect(spec.criteria[1].isDescending, isTrue);
        expect(spec.criteria[2].field, equals('customer.name'));
        expect(spec.criteria[2].isAscending, isTrue);
      });

      test('parses nested list of tuples', () {
        final spec = parser.parse([
          ['state', 'asc'],
          ['amount', 'desc'],
          ['customer.country.code', 'desc'],
        ]);
        expect(spec.length, equals(3));
        expect(spec.criteria[0].field, equals('state'));
        expect(spec.criteria[0].isAscending, isTrue);
        expect(spec.criteria[1].field, equals('amount'));
        expect(spec.criteria[1].isDescending, isTrue);
        expect(spec.criteria[2].field, equals('customer.country.code'));
        expect(spec.criteria[2].isDescending, isTrue);
      });
    });

    group('Map inputs', () {
      test('parses standard criterion map with field and direction/order', () {
        final spec1 = parser.parse({'field': 'amount', 'direction': 'desc'});
        expect(spec1.first.field, equals('amount'));
        expect(spec1.first.isDescending, isTrue);

        final spec2 = parser.parse({'field': 'amount', 'order': 'asc'});
        expect(spec2.first.isAscending, isTrue);
      });

      test('parses DevExtreme format (selector + desc boolean)', () {
        final specDesc = parser.parse({'selector': 'amount', 'desc': true});
        expect(specDesc.first.field, equals('amount'));
        expect(specDesc.first.isDescending, isTrue);

        final specAsc = parser.parse({'selector': 'amount', 'desc': false});
        expect(specAsc.first.isAscending, isTrue);
      });

      test('parses AG Grid format (colId + sort string)', () {
        final spec = parser.parse({'colId': 'state', 'sort': 'desc'});
        expect(spec.first.field, equals('state'));
        expect(spec.first.isDescending, isTrue);
      });

      test('parses TanStack / React Table format (id + desc boolean)', () {
        final spec = parser.parse({'id': 'amount', 'desc': true});
        expect(spec.first.field, equals('amount'));
        expect(spec.first.isDescending, isTrue);
      });

      test('parses Column descriptor format (column + descending boolean)', () {
        final spec = parser.parse({'column': 'amount', 'descending': true});
        expect(spec.first.field, equals('amount'));
        expect(spec.first.isDescending, isTrue);
      });

      test('parses key-value dictionary {fieldName: direction}', () {
        final spec = parser.parse({
          'state': 'asc',
          'amount': 'desc',
          'customer.country.code': -1,
        });
        expect(spec.length, equals(3));
        expect(spec.criteria[0].field, equals('state'));
        expect(spec.criteria[0].isAscending, isTrue);
        expect(spec.criteria[1].field, equals('amount'));
        expect(spec.criteria[1].isDescending, isTrue);
        expect(spec.criteria[2].field, equals('customer.country.code'));
        expect(spec.criteria[2].isDescending, isTrue);
      });

      test('parses list of maps', () {
        final spec = parser.parse([
          {'field': 'state', 'direction': 'asc'},
          {'field': 'amount', 'direction': 'desc'},
        ]);
        expect(spec.length, equals(2));
        expect(spec.criteria[0].field, equals('state'));
        expect(spec.criteria[0].isAscending, isTrue);
        expect(spec.criteria[1].field, equals('amount'));
        expect(spec.criteria[1].isDescending, isTrue);
      });
    });

    group('JSON String inputs', () {
      test('parses JSON string array', () {
        final spec = parser.parse('["state", "-amount"]');
        expect(spec.length, equals(2));
        expect(spec.criteria[0].field, equals('state'));
        expect(spec.criteria[0].isAscending, isTrue);
        expect(spec.criteria[1].field, equals('amount'));
        expect(spec.criteria[1].isDescending, isTrue);
      });

      test('parses JSON array of maps', () {
        final spec = parser.parse(
          '[{"field": "amount", "direction": "desc"}, {"field": "state", "direction": "asc"}]',
        );
        expect(spec.length, equals(2));
        expect(spec.criteria[0].field, equals('amount'));
        expect(spec.criteria[0].isDescending, isTrue);
        expect(spec.criteria[1].field, equals('state'));
        expect(spec.criteria[1].isAscending, isTrue);
      });

      test('parses JSON key-value map', () {
        final spec = parser.parse('{"state": "asc", "amount": "desc"}');
        expect(spec.length, equals(2));
        expect(spec.criteria[0].field, equals('state'));
        expect(spec.criteria[1].field, equals('amount'));
      });
    });

    group('Validation & Security', () {
      test(
        'throws SortParseException on invalid field names (SQL injection)',
        () {
          expect(
            () => parser.parse('amount; DROP TABLE users;'),
            throwsA(isA<SortParseException>()),
          );
          expect(
            () => parser.parse('--comment'),
            throwsA(isA<SortParseException>()),
          );
          expect(
            () => parser.parse('amount desc; select 1'),
            throwsA(isA<SortParseException>()),
          );
        },
      );

      test('throws SortParseException on invalid direction value', () {
        expect(
          () => parser.parse('amount:sideways'),
          throwsA(isA<SortParseException>()),
        );
        expect(
          () => parser.parse({'field': 'amount', 'direction': 'sideways'}),
          throwsA(isA<SortParseException>()),
        );
        expect(
          () => parser.parse([
            ['amount', 'sideways'],
          ]),
          throwsA(isA<SortParseException>()),
        );
      });
    });
  });

  group('SortSpecification Methods', () {
    test('hasField and findCriterion check fields case-insensitively', () {
      const spec = SortSpecification([
        SortCriterion('amount', SortDirection.descending),
        SortCriterion('customer.name', SortDirection.ascending),
      ]);

      expect(spec.hasField('AMOUNT'), isTrue);
      expect(spec.hasField('customer.name'), isTrue);
      expect(spec.hasField('missing'), isFalse);

      final crit = spec.findCriterion('Amount');
      expect(crit, isNotNull);
      expect(crit!.isDescending, isTrue);
    });

    test('reversed inverts all directions', () {
      const spec = SortSpecification([
        SortCriterion('state', SortDirection.ascending),
        SortCriterion('amount', SortDirection.descending),
      ]);
      final reversed = spec.reversed();
      expect(reversed.criteria[0].isDescending, isTrue);
      expect(reversed.criteria[1].isAscending, isTrue);
    });

    test('filterAllowed retains allowed fields', () {
      const spec = SortSpecification([
        SortCriterion('state', SortDirection.ascending),
        SortCriterion('amount', SortDirection.descending),
        SortCriterion('secretKey', SortDirection.ascending),
      ]);

      final filtered = spec.filterAllowed({'state', 'amount'});
      expect(filtered.length, equals(2));
      expect(filtered.hasField('secretKey'), isFalse);
    });

    test('filterAllowed with strict: true throws SortValidationException', () {
      const spec = SortSpecification([
        SortCriterion('secretKey', SortDirection.ascending),
      ]);

      expect(
        () => spec.filterAllowed({'state', 'amount'}, strict: true),
        throwsA(isA<SortValidationException>()),
      );
    });

    test('withFieldMap remaps client field names', () {
      const spec = SortSpecification([
        SortCriterion('total', SortDirection.descending),
        SortCriterion('clientName', SortDirection.ascending),
      ]);

      final remapped = spec.withFieldMap({
        'total': 'amount',
        'clientName': 'customer.name',
      });

      expect(remapped.criteria[0].field, equals('amount'));
      expect(remapped.criteria[0].isDescending, isTrue);
      expect(remapped.criteria[1].field, equals('customer.name'));
      expect(remapped.criteria[1].isAscending, isTrue);
    });
  });

  group('ServerpodSorting and Translator (Direct Serverpod Integration)', () {
    late MockOrderTable table;

    setUp(() {
      table = MockOrderTable();
    });

    test('translates single column sort to Serverpod Order', () {
      final orders = ServerpodSorting.toOrderByList('-amount', table);
      expect(orders.length, equals(1));
      expect(orders.first.column.columnName, equals('amount'));
      expect(orders.first.orderDescending, isTrue);
      expect(orders.first.toString(), contains('"order"."amount" DESC'));
    });

    test('translates compound multi-field sort in specified order', () {
      final orders = ServerpodSorting.toOrderByList(
        ['state', '-amount'],
        table,
      );
      expect(orders.length, equals(2));
      expect(orders[0].column.columnName, equals('state'));
      expect(orders[0].orderDescending, isFalse);
      expect(orders[1].column.columnName, equals('amount'));
      expect(orders[1].orderDescending, isTrue);
    });

    test(
      'automatically resolves multi-hop relational columns with dot-notation',
      () {
        final orders = ServerpodSorting.toOrderByList(
          '-customer.country.name',
          table,
        );
        expect(orders.length, equals(1));
        expect(orders.first.column.columnName, equals('name'));
        expect(orders.first.orderDescending, isTrue);
        expect(orders.first.toString(), contains('DESC'));
      },
    );

    test('normalizes camelCase and snake_case column names', () {
      final orders1 = ServerpodSorting.toOrderByList('customerId', table);
      expect(orders1.first.column.columnName, equals('customer_id'));

      final orders2 = ServerpodSorting.toOrderByList('customer_id', table);
      expect(orders2.first.column.columnName, equals('customer_id'));
    });

    test('applies defaultSort when client sort is empty or null', () {
      final ordersNull = ServerpodSorting.toOrderByList(
        null,
        table,
        defaultSort: '-id',
      );
      expect(ordersNull.length, equals(1));
      expect(ordersNull.first.column.columnName, equals('id'));
      expect(ordersNull.first.orderDescending, isTrue);

      final ordersEmpty = ServerpodSorting.toOrderByList(
        [],
        table,
        defaultSort: 'state:asc',
      );
      expect(ordersEmpty.length, equals(1));
      expect(ordersEmpty.first.column.columnName, equals('state'));
      expect(ordersEmpty.first.orderDescending, isFalse);

      // Does NOT apply defaultSort when client sends active sort
      final ordersActive = ServerpodSorting.toOrderByList(
        '-amount',
        table,
        defaultSort: 'id',
      );
      expect(ordersActive.length, equals(1));
      expect(ordersActive.first.column.columnName, equals('amount'));
    });

    test('respects allowedFields whitelist in translation', () {
      final orders = ServerpodSorting.toOrderByList(
        ['state', '-amount'],
        table,
        allowedFields: {'amount'},
      );
      expect(orders.length, equals(1));
      expect(orders.first.column.columnName, equals('amount'));
    });

    test(
      'orderByList builder callback returns OrderByListBuilder for Serverpod',
      () {
        final builder = ServerpodSorting.orderByList<MockOrderTable>(
          '-amount, state:asc',
        );
        expect(builder, isNotNull);

        final orders = builder!(table);
        expect(orders.length, equals(2));
        expect(orders[0].columnName, equals('amount'));
        expect(orders[1].columnName, equals('state'));
      },
    );

    test(
      'orderByList returns null when sort is empty, enabling ?? fallback',
      () {
        final builderNull = ServerpodSorting.orderByList<MockOrderTable>(null);
        expect(builderNull, isNull);

        final builderEmpty = ServerpodSorting.orderByList<MockOrderTable>([]);
        expect(builderEmpty, isNull);

        // Chaining with ??
        final effectiveBuilder =
            builderNull ?? ((MockOrderTable t) => [t.id.asc()]);
        final orders = effectiveBuilder(table);
        expect(orders.length, equals(1));
        expect(orders.first.columnName, equals('id'));
      },
    );

    test('ServerpodFilters facade provides orderByList and toOrderByList', () {
      final orders = ServerpodFilters.toOrderByList('-amount', table);
      expect(orders.length, equals(1));
      expect(orders.first.column.columnName, equals('amount'));
      expect(orders.first.orderDescending, isTrue);

      final builder = ServerpodFilters.orderByList<MockOrderTable>('-amount');
      expect(builder, isNotNull);
      final list = builder!(table);
      expect(list.length, equals(1));
    });

    test('SortEngine alias works identically', () {
      final orders = SortEngine.toOrderByList('state', table);
      expect(orders.length, equals(1));
      expect(orders.first.column.columnName, equals('state'));
    });
  });
}
