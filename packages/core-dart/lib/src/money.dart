/// Money handling for TrustIQ.
///
/// This is the Dart port of `packages/core/src/money.ts`. The rules are
/// identical on purpose, and `money_parity_test.dart` in the TypeScript package
/// fails if the two drift.
///
/// Every amount is an integer number of fils, the minor unit of the UAE dirham
/// (1 AED = 100 fils). Doubles are never used to represent money.
library;

/// An amount in fils.
///
/// An extension type, so it is a plain `int` at runtime with no wrapper cost,
/// but the compiler refuses to let a bare int stand in for an amount. This is
/// the Dart equivalent of the branded `Fils` type in TypeScript.
extension type const Fils._(int value) implements Comparable<num> {
  factory Fils(int value) {
    if (value.abs() > maxFils) {
      throw MoneyError('fils: amount $value exceeds the supported range');
    }
    return Fils._(value);
  }

  static const int filsPerAed = 100;

  /// Largest amount we accept, ~92 billion AED. Matches MAX_FILS in TypeScript.
  static const int maxFils = 9223372036854;

  static const Fils zero = Fils._(0);

  Fils operator +(Fils other) => Fils(value + other.value);
  Fils operator -(Fils other) => Fils(value - other.value);

  bool operator <(Fils other) => value < other.value;
  bool operator >(Fils other) => value > other.value;
  bool operator <=(Fils other) => value <= other.value;
  bool operator >=(Fils other) => value >= other.value;

  bool get isPositive => value > 0;
  bool get isNegative => value < 0;
}

class MoneyError implements Exception {
  const MoneyError(this.message);
  final String message;
  @override
  String toString() => 'MoneyError: $message';
}

final RegExp _aedPattern = RegExp(r'^(-)?(\d+)(?:\.(\d{1,2}))?$');

/// Parses an AED amount into fils.
///
/// Takes a string so the value is exact. More precision than a fil is rejected
/// rather than silently rounded: dropping a fil without telling anyone is how
/// ledgers stop balancing.
Fils filsFromAed(String amount) {
  final match = _aedPattern.firstMatch(amount.trim());
  if (match == null) {
    throw MoneyError(
      'filsFromAed: "$amount" is not a valid AED amount '
      '(expected digits with at most 2 decimals)',
    );
  }
  final whole = int.parse(match.group(2)!);
  final fraction = int.parse((match.group(3) ?? '').padRight(2, '0').padLeft(1, '0'));
  final minor = whole * Fils.filsPerAed + fraction;
  return Fils(match.group(1) == '-' ? -minor : minor);
}

/// Formats fils as a plain AED decimal string: 50055 -> "500.55".
String aedFromFils(Fils amount) {
  final negative = amount.value < 0;
  final abs = amount.value.abs();
  final whole = abs ~/ Fils.filsPerAed;
  final fraction = abs % Fils.filsPerAed;
  return '${negative ? '-' : ''}$whole.${fraction.toString().padLeft(2, '0')}';
}

/// Human-facing amount: "500.55 AED".
String formatAed(Fils amount) => '${aedFromFils(amount)} AED';

Fils sumFils(Iterable<Fils> amounts) =>
    amounts.fold(Fils.zero, (total, amount) => total + amount);

/// Splits an amount across weighted shares without losing or inventing a fil.
///
/// Largest-remainder method: floor every share, then hand the leftover fils one
/// at a time to the shares with the largest fractional part. Ties go to the
/// earlier index, so the result is deterministic and reproducible in an audit,
/// and identical to the TypeScript implementation.
List<Fils> allocate(Fils total, List<num> weights) {
  if (weights.isEmpty) {
    throw const MoneyError('allocate: at least one weight is required');
  }
  if (weights.any((w) => !w.isFinite || w < 0)) {
    throw const MoneyError('allocate: weights must be finite and non-negative');
  }
  final totalWeight = weights.fold<num>(0, (a, b) => a + b);
  if (totalWeight <= 0) {
    throw const MoneyError('allocate: weights must not all be zero');
  }
  if (total.isNegative) {
    throw const MoneyError('allocate: cannot allocate a negative amount');
  }

  final shares = <int>[];
  final remainders = <({int index, double fraction})>[];
  var distributed = 0;

  for (var i = 0; i < weights.length; i++) {
    final exact = total.value * weights[i] / totalWeight;
    final floored = exact.floor();
    shares.add(floored);
    remainders.add((index: i, fraction: exact - floored));
    distributed += floored;
  }

  var leftover = total.value - distributed;
  remainders.sort((a, b) {
    final byFraction = b.fraction.compareTo(a.fraction);
    return byFraction != 0 ? byFraction : a.index.compareTo(b.index);
  });

  for (var i = 0; leftover > 0; i = (i + 1) % remainders.length) {
    shares[remainders[i].index] += 1;
    leftover -= 1;
  }

  return shares.map(Fils.new).toList();
}

/// Splits by percentage between seller and buyer, the shape a dispute
/// resolution actually takes. [sellerPercent] is 0-100 inclusive.
({Fils seller, Fils buyer}) splitByPercent(Fils total, num sellerPercent) {
  if (!sellerPercent.isFinite || sellerPercent < 0 || sellerPercent > 100) {
    throw MoneyError(
      'splitByPercent: sellerPercent must be between 0 and 100, got $sellerPercent',
    );
  }
  final parts = allocate(total, [sellerPercent, 100 - sellerPercent]);
  return (seller: parts[0], buyer: parts[1]);
}
