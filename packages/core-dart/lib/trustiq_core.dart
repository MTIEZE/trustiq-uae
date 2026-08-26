/// TrustIQ domain rules for the Flutter app.
///
/// A port of `packages/core` (TypeScript). The two are kept in step by
/// `packages/core/src/dart-parity.test.ts`, which parses this package and fails
/// if the transition tables, enums, or money constants drift apart. If you
/// change a rule here, change it in TypeScript and in the SQL migrations too.
library;

export 'src/dispute_machine.dart';
export 'src/evidence_policy.dart';
export 'src/money.dart';
export 'src/transaction_machine.dart';
export 'src/types.dart';
