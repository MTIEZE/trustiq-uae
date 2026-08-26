import 'package:test/test.dart';
import 'package:trustiq_core/src/money.dart';

void main() {
  group('filsFromAed', () {
    test('parses whole and fractional amounts exactly', () {
      expect(filsFromAed('500').value, 50000);
      expect(filsFromAed('500.5').value, 50050);
      expect(filsFromAed('500.55').value, 50055);
      expect(filsFromAed('0.01').value, 1);
      expect(filsFromAed('0').value, 0);
    });

    test('does not drift on values that break naive float maths', () {
      // 5.55 * 100 is 554.9999999999999 in IEEE 754. This is the whole reason
      // the module exists, so it gets an explicit test on both sides of the port.
      expect(filsFromAed('5.55').value, 555);
      expect(filsFromAed('1.10').value, 110);
    });

    test('handles negative amounts', () {
      expect(filsFromAed('-12.34').value, -1234);
    });

    test('rejects more precision than a fil can hold', () {
      expect(() => filsFromAed('1.234'), throwsA(isA<MoneyError>()));
    });

    test('rejects malformed input rather than guessing', () {
      for (final bad in ['', 'abc', '1,50', '1.2.3', '--5', ' ', '1e3']) {
        expect(() => filsFromAed(bad), throwsA(isA<MoneyError>()), reason: bad);
      }
    });
  });

  group('formatting', () {
    test('round-trips through fils and back', () {
      for (final value in ['0.00', '0.07', '9.90', '500.55', '123456.78']) {
        expect(aedFromFils(filsFromAed(value)), value);
      }
    });

    test('pads the fractional part', () {
      expect(aedFromFils(Fils(5)), '0.05');
      expect(aedFromFils(Fils(50)), '0.50');
      expect(aedFromFils(Fils(-5)), '-0.05');
    });

    test('renders a human-facing string', () {
      expect(formatAed(filsFromAed('500')), '500.00 AED');
    });
  });

  group('arithmetic', () {
    test('adds and subtracts', () {
      expect((Fils(100) + Fils(250)).value, 350);
      expect((Fils(350) - Fils(100)).value, 250);
    });

    test('sums a list, empty included', () {
      expect(sumFils([]).value, 0);
      expect(sumFils([Fils(1), Fils(2), Fils(3)]).value, 6);
    });

    test('refuses amounts beyond the supported range', () {
      expect(() => Fils(Fils.maxFils + 1), throwsA(isA<MoneyError>()));
    });
  });

  group('allocate', () {
    test('splits evenly divisible amounts exactly', () {
      expect(allocate(Fils(10000), [60, 40]).map((f) => f.value), [6000, 4000]);
      expect(allocate(Fils(1000), [1, 1]).map((f) => f.value), [500, 500]);
    });

    test('distributes the remainder by largest fraction, ties to earlier index', () {
      expect(allocate(Fils(100), [1, 1, 1]).map((f) => f.value), [34, 33, 33]);
      expect(allocate(Fils(10), [1, 1, 1]).map((f) => f.value), [4, 3, 3]);
    });

    test('handles a zero weight and a zero total', () {
      expect(allocate(Fils(1000), [1, 0]).map((f) => f.value), [1000, 0]);
      expect(allocate(Fils.zero, [70, 30]).map((f) => f.value), [0, 0]);
    });

    test('never loses or invents a fil, across a wide sweep of inputs', () {
      const weightSets = [
        [1, 1],
        [1, 2],
        [60, 40],
        [1, 1, 1],
        [7, 11, 13],
        [1, 0, 1],
        [99, 1],
        [1, 1, 1, 1, 1, 1, 1],
      ];
      for (final weights in weightSets) {
        for (var total = 0; total <= 1000; total++) {
          final shares = allocate(Fils(total), weights);
          expect(shares.length, weights.length);
          expect(shares.every((s) => s.value >= 0), isTrue);
          expect(shares.fold<int>(0, (a, b) => a + b.value), total,
              reason: '$weights at $total');
        }
      }
    });

    test('is deterministic', () {
      final a = allocate(Fils(9999), [7, 11, 13]).map((f) => f.value).toList();
      final b = allocate(Fils(9999), [7, 11, 13]).map((f) => f.value).toList();
      expect(a, b);
    });

    test('rejects nonsense input', () {
      expect(() => allocate(Fils(100), []), throwsA(isA<MoneyError>()));
      expect(() => allocate(Fils(100), [0, 0]), throwsA(isA<MoneyError>()));
      expect(() => allocate(Fils(100), [-1, 2]), throwsA(isA<MoneyError>()));
      expect(() => allocate(Fils(-100), [1, 1]), throwsA(isA<MoneyError>()));
    });
  });

  group('splitByPercent', () {
    test('produces the split shown in the product demo', () {
      final split = splitByPercent(filsFromAed('500'), 60);
      expect(aedFromFils(split.seller), '300.00');
      expect(aedFromFils(split.buyer), '200.00');
    });

    test('gives everything to one side at the extremes', () {
      final all = splitByPercent(Fils(1000), 100);
      expect([all.seller.value, all.buyer.value], [1000, 0]);
      final none = splitByPercent(Fils(1000), 0);
      expect([none.seller.value, none.buyer.value], [0, 1000]);
    });

    test('conserves the total at every whole percentage, for awkward amounts', () {
      for (final total in [1, 7, 99, 333, 50055, 1000001]) {
        for (var pct = 0; pct <= 100; pct++) {
          final split = splitByPercent(Fils(total), pct);
          expect(split.seller.value + split.buyer.value, total,
              reason: '$total at $pct%');
          expect(split.seller.value >= 0 && split.buyer.value >= 0, isTrue);
        }
      }
    });

    test('rejects a percentage outside 0 to 100', () {
      expect(() => splitByPercent(Fils(100), 101), throwsA(isA<MoneyError>()));
      expect(() => splitByPercent(Fils(100), -1), throwsA(isA<MoneyError>()));
    });
  });
}
