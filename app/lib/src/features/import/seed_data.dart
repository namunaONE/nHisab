/// Transcribed from reference sheet. Rate as annual decimal 0.18 = 18%.
/// Row4 Table2 corrected 4190000 -> 41900000 to match PerDay 7891.17 and total 85713900.
class SeedLoan {
  final String party;
  final double principal;
  final double rate;
  final String startDate; // yyyy-mm-dd
  final String direction; // receivable | payable
  final String loanType;
  final String remarks;
  const SeedLoan(this.party, this.principal, this.rate, this.startDate, this.direction, this.loanType, this.remarks);
}

const seedLoans = <SeedLoan>[
  // Group A lent 7
  SeedLoan('Saroj Poudel', 1500000, 0.18, '2026-06-19', 'receivable', 'personal', 'G-A1'),
  SeedLoan('Madhav Koirala (Harkapur)', 500000, 0.24, '2026-04-14', 'receivable', 'personal', 'G-A2'),
  SeedLoan('Diliram Sapkota (Harkapur)', 500000, 0.18, '2026-06-15', 'receivable', 'personal', 'G-A3'),
  SeedLoan('Sujan Acharya', 1200000, 0.15, '2026-04-21', 'receivable', 'personal', 'G-A4'),
  SeedLoan('Madhu (Japan) A', 1000000, 0.18, '2026-04-24', 'receivable', 'personal', 'G-A5'),
  SeedLoan('Madhu (Japan) B', 600000, 0.12, '2026-01-16', 'receivable', 'personal', 'G-A6'),
  SeedLoan('Sharada Paudel (U.S.A)', 400000, 0.0, '2026-10-15', 'receivable', 'personal', 'G-A7 zero-rate'),
  // Group B borrowed 7
  SeedLoan('Dhana Laxmi Sahakari', 7251400, 0.18, '2026-10-16', 'payable', 'business', 'G-B1'),
  SeedLoan('Sharba Shakti Sahakari', 3050000, 0.18, '2026-10-16', 'payable', 'business', 'G-B2'),
  SeedLoan('Laxmi Sunrise Bank (Cash Credit)', 14000000, 0.0678, '2026-10-17', 'payable', 'cash_credit', 'G-B3'),
  SeedLoan('Laxmi Sunrise Bank (Working Capital)', 41900000, 0.0678, '2026-10-18', 'payable', 'business', 'G-B4 corrected zero'),
  SeedLoan('Laxmi Sunrise Bank (Demand Loan)', 15000000, 0.0678, '2026-10-19', 'payable', 'demand', 'G-B5'),
  SeedLoan('Everest Bank Limited (MG Car)', 512500, 0.08, '2026-10-20', 'payable', 'vehicle', 'G-B6'),
  SeedLoan('Machaapuchhre Bank (Hyundai Car)', 4000000, 0.80, '2026-10-21', 'payable', 'vehicle', 'G-B7 rate 80% as per sheet - verify'),
  // Group C lent 7
  SeedLoan('Daya Dawadi', 700000, 0.18, '2026-08-10', 'receivable', 'personal', 'G-C1'),
  SeedLoan('Jaya Ram', 1300000, 0.18, '2026-07-23', 'receivable', 'personal', 'G-C2'),
  SeedLoan('Narhari Dhital 110k', 110000, 0.18, '2026-04-24', 'receivable', 'personal', 'G-C3'),
  SeedLoan('Shubhakar Chapagain', 700000, 0.18, '2025-08-17', 'receivable', 'personal', 'G-C4'),
  SeedLoan('Tulsi Chapagain', 500000, 0.18, '2026-07-16', 'receivable', 'personal', 'G-C5'),
  SeedLoan('Narhari Dhital 800k', 800000, 0.18, '2026-10-15', 'receivable', 'personal', 'G-C6 no start date in sheet'),
  SeedLoan('Som Sir Bhai', 150000, 0.0, '2026-10-15', 'receivable', 'personal', 'G-C7 zero-rate'),
];
