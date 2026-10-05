import '../money.dart';

// Hand-written on purpose: a model that fails loudly on a missing field is a
// better contract check than generated code nobody reads. Shapes come from the
// recorded responses in test/fixtures/. Add a model with the phase that uses it.

class Me {
  const Me({required this.id, required this.email, this.displayName});

  final String id;
  final String? email;
  final String? displayName;

  factory Me.fromJson(Map<String, dynamic> json) => Me(
    id: json['id'] as String,
    email: json['email'] as String?,
    displayName: json['displayName'] as String?,
  );
}

/// What a role may do, mirroring `apps/api/src/domain/permissions.js`. The API
/// checks every request again; this only decides what the UI offers.
enum Capability { read, comment, split, reclassify, create, edit, manageBook }

const _roleCapabilities = <String, Set<Capability>>{
  'viewer': {Capability.read},
  'reviewer': {Capability.read, Capability.comment, Capability.split, Capability.reclassify},
  'editor': {Capability.read, Capability.comment, Capability.split, Capability.reclassify, Capability.create, Capability.edit},
  'book_owner': {Capability.read, Capability.comment, Capability.split, Capability.reclassify, Capability.create, Capability.edit, Capability.manageBook},
  'workspace_admin': {Capability.read, Capability.comment, Capability.split, Capability.reclassify, Capability.create, Capability.edit, Capability.manageBook},
};

String roleLabel(String role) => switch (role) {
  'book_owner' => 'Owner',
  'workspace_admin' => 'Admin',
  'editor' => 'Editor',
  'reviewer' => 'Reviewer',
  'viewer' => 'Viewer',
  _ => role,
};

class Book {
  const Book({
    required this.id,
    required this.name,
    required this.visibility,
    required this.currency,
    required this.timezone,
    required this.periodStartDay,
    required this.role,
  });

  final String id;
  final String name;
  final String visibility;
  final String currency;
  final String timezone;
  final int periodStartDay;
  final String role;

  bool can(Capability capability) => _roleCapabilities[role]?.contains(capability) ?? false;

  factory Book.fromJson(Map<String, dynamic> json) => Book(
    id: json['id'] as String,
    name: json['name'] as String,
    visibility: json['visibility'] as String,
    currency: json['currency'] as String,
    timezone: json['timezone'] as String,
    periodStartDay: json['periodStartDay'] as int,
    role: json['role'] as String,
  );
}

/// The window a summary covers, as the server used it. The dashboard prints this
/// rather than working it out, so the header can never disagree with the figures.
class Period {
  const Period({required this.month, required this.startDay, required this.startsAt, required this.endsAt});

  final String month;
  final int startDay;

  /// First instant of the period.
  final DateTime startsAt;

  /// First instant of the *next* period, so the last day shown is a day before.
  final DateTime endsAt;

  factory Period.fromJson(Map<String, dynamic> json) => Period(
    month: json['month'] as String,
    startDay: json['startDay'] as int,
    startsAt: DateTime.parse(json['startsAt'] as String),
    endsAt: DateTime.parse(json['endsAt'] as String),
  );
}

/// One line of "where the money went". Includes uncategorised payments and
/// outgoing transfers, so the lines add up to spent plus saved.
class SpendLine {
  const SpendLine({required this.categoryId, required this.name, required this.groupName, required this.amountMinor});

  final String? categoryId;
  final String name;
  final String groupName;
  final BigInt amountMinor;

  factory SpendLine.fromJson(Map<String, dynamic> json) => SpendLine(
    categoryId: json['categoryId'] as String?,
    name: json['name'] as String,
    groupName: (json['groupName'] as String?)?.trim().isNotEmpty == true ? json['groupName'] as String : 'Other',
    amountMinor: parseMinor(json['amountMinor'] as String),
  );
}

class Summary {
  const Summary({
    required this.incomeMinor,
    required this.spentMinor,
    required this.movedMinor,
    required this.balanceMinor,
    required this.pendingReview,
    required this.byCategory,
    required this.period,
  });

  final BigInt incomeMinor;
  final BigInt spentMinor;

  /// Sent to the household's own accounts: not spending, but still money that left.
  final BigInt movedMinor;
  final BigInt balanceMinor;
  final int pendingReview;
  final List<SpendLine> byCategory;
  final Period? period;

  factory Summary.fromJson(Map<String, dynamic> json) => Summary(
    incomeMinor: parseMinor(json['incomeMinor'] as String),
    spentMinor: parseMinor(json['spentMinor'] as String),
    movedMinor: parseMinor((json['movedMinor'] as String?) ?? '0'),
    balanceMinor: parseMinor(json['balanceMinor'] as String),
    pendingReview: json['pendingReview'] as int,
    byCategory: [for (final line in (json['byCategory'] as List? ?? const [])) SpendLine.fromJson(line as Map<String, dynamic>)],
    period: json['period'] == null ? null : Period.fromJson(json['period'] as Map<String, dynamic>),
  );
}

class BudgetShare {
  const BudgetShare({required this.groupName, required this.percent});

  final String groupName;
  final int percent;

  factory BudgetShare.fromJson(Map<String, dynamic> json) => BudgetShare(groupName: json['groupName'] as String, percent: json['percent'] as int);
}

class BudgetPlan {
  const BudgetPlan({required this.items, required this.baseIncomeMinor});

  final List<BudgetShare> items;

  /// Monthly income expected from the recurring income plans. Zero if there are none.
  final BigInt baseIncomeMinor;

  factory BudgetPlan.fromJson(Map<String, dynamic> json) => BudgetPlan(
    items: [for (final item in (json['items'] as List? ?? const [])) BudgetShare.fromJson(item as Map<String, dynamic>)],
    baseIncomeMinor: parseMinor((json['baseIncomeMinor'] as String?) ?? '0'),
  );
}
