import 'package:intl/intl.dart';

/// A single row in a party statement: loan disbursal, payment, or interest accrual.
class StatementRow {
  final String id;
  final DateTime date;
  final String type; // 'loan_disbursal', 'payment', 'interest_accrual', 'write_off'
  final String description;
  final double debit;   // increases what party owes (receivable) / we owe (payable)
  final double credit;  // decreases what party owes / we owe
  final double balance; // running balance

  StatementRow({
    required this.id,
    required this.date,
    required this.type,
    required this.description,
    required this.debit,
    required this.credit,
    required this.balance,
  });
}

/// Complete party statement with totals.
class PartyStatement {
  final String partyId;
  final String partyName;
  final String? phone;
  final String? address;
  final String direction; // 'receivable' or 'payable' (dominant direction)
  final double totalPrincipal;
  final double totalPrincipalPaid;
  final double totalInterestAccrued;
  final double totalInterestPaid;

  /// Amount forgiven when a loan was closed with an explicit write-off.
  final double totalWrittenOff;

  /// principal - principalPaid + interestAccrued - interestPaid - writtenOff
  final double outstanding;
  final List<StatementRow> rows;
  final DateTime asOfDate;

  PartyStatement({
    required this.partyId,
    required this.partyName,
    this.phone,
    this.address,
    required this.direction,
    required this.totalPrincipal,
    required this.totalPrincipalPaid,
    required this.totalInterestAccrued,
    required this.totalInterestPaid,
    this.totalWrittenOff = 0,
    required this.outstanding,
    required this.rows,
    required this.asOfDate,
  });

  /// Net principal outstanding (before interest).
  double get principalOutstanding => totalPrincipal - totalPrincipalPaid;

  /// Net interest outstanding.
  double get interestOutstanding => totalInterestAccrued - totalInterestPaid;

  /// Direction label for display.
  String get directionLabel => direction == 'receivable' ? 'Money Lent (Receivable)' : 'Money Borrowed (Payable)';

  /// Whether this party owes us (receivable) or we owe them (payable).
  bool get isReceivable => direction == 'receivable';

  /// Currency formatter.
  static final fmt = NumberFormat('#,##0.00');
}
