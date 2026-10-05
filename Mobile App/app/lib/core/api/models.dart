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

class Category {
  const Category({required this.id, required this.name, required this.groupName, required this.color});

  final String id;
  final String name;
  final String groupName;
  final String color;

  factory Category.fromJson(Map<String, dynamic> json) => Category(
    id: json['id'] as String,
    name: json['name'] as String,
    groupName: (json['groupName'] as String?)?.trim().isNotEmpty == true ? json['groupName'] as String : 'Other',
    color: json['color'] as String,
  );
}

class Account {
  const Account({required this.id, required this.name, required this.accountType, this.accountMask});

  final String id;
  final String name;
  final String accountType;
  final String? accountMask;

  /// `Primary bank ····0042`, so two accounts with one name stay tellable apart.
  String get label => accountMask == null || accountMask!.isEmpty ? name : '$name ····$accountMask';

  factory Account.fromJson(Map<String, dynamic> json) => Account(
    id: json['id'] as String,
    name: json['name'] as String,
    accountType: json['accountType'] as String,
    accountMask: json['accountMask'] as String?,
  );
}

/// Where a payment came from. The bank's own figure is kept here forever, even
/// after the payment is edited.
class TxSource {
  const TxSource({required this.sourceType, required this.importedAmount});

  final String sourceType;
  final BigInt importedAmount;

  factory TxSource.fromJson(Map<String, dynamic> json) => TxSource(
    sourceType: json['sourceType'] as String,
    importedAmount: parseMinor(json['importedAmount'] as String),
  );
}

class TxSplit {
  const TxSplit({required this.categoryId, required this.amountMinor, this.note});

  final String categoryId;
  final BigInt amountMinor;
  final String? note;

  factory TxSplit.fromJson(Map<String, dynamic> json) => TxSplit(
    categoryId: json['categoryId'] as String,
    amountMinor: parseMinor(json['amountMinor'] as String),
    note: json['note'] as String?,
  );
}

class TxComment {
  const TxComment({required this.id, required this.authorId, required this.body, required this.createdAt});

  final String id;
  final String authorId;
  final String body;
  final DateTime createdAt;

  factory TxComment.fromJson(Map<String, dynamic> json) => TxComment(
    id: json['id'] as String,
    authorId: json['authorId'] as String,
    body: json['body'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
  );
}

class Transaction {
  const Transaction({
    required this.id,
    required this.kind,
    required this.state,
    required this.amountMinor,
    required this.occurredAt,
    required this.sources,
    required this.splits,
    required this.comments,
    this.merchant,
    this.note,
    this.categoryId,
    this.accountId,
    this.counterAccountId,
  });

  final String id;

  /// expense, income, transfer or refund.
  final String kind;

  /// pending_review, confirmed, reconciled, excluded or voided.
  final String state;

  /// Signed: expenses negative, income and refunds positive.
  final BigInt amountMinor;
  final DateTime occurredAt;
  final String? merchant;
  final String? note;
  final String? categoryId;
  final String? accountId;
  final String? counterAccountId;
  final List<TxSource> sources;
  final List<TxSplit> splits;
  final List<TxComment> comments;

  /// `previous` fills in what a response leaves out. The category and split
  /// routes return the payment without its comments (and the category route
  /// without its splits), and there is no route to fetch one payment on its own,
  /// so dropping the old values would lose them from the screen.
  factory Transaction.fromJson(Map<String, dynamic> json, {Transaction? previous}) {
    List<T> list<T>(String key, T Function(Map<String, dynamic>) read, List<T> fallback) =>
        json[key] is List ? [for (final item in json[key] as List) read(item as Map<String, dynamic>)] : fallback;
    return Transaction(
      id: json['id'] as String,
      kind: json['kind'] as String,
      state: json['state'] as String,
      amountMinor: parseMinor(json['amountMinor'] as String),
      occurredAt: DateTime.parse(json['occurredAt'] as String),
      merchant: json['merchant'] as String?,
      note: json['note'] as String?,
      categoryId: json['categoryId'] as String?,
      accountId: json['accountId'] as String?,
      counterAccountId: json['counterAccountId'] as String?,
      sources: list('sources', TxSource.fromJson, previous?.sources ?? const []),
      splits: list('splits', TxSplit.fromJson, previous?.splits ?? const []),
      comments: list('comments', TxComment.fromJson, previous?.comments ?? const []),
    );
  }

  Transaction withComment(TxComment comment) => Transaction(
    id: id, kind: kind, state: state, amountMinor: amountMinor, occurredAt: occurredAt, merchant: merchant, note: note,
    categoryId: categoryId, accountId: accountId, counterAccountId: counterAccountId,
    sources: sources, splits: splits, comments: [...comments, comment],
  );
}

class TransactionPage {
  const TransactionPage({required this.items, required this.nextCursor});

  final List<Transaction> items;

  /// Null on the last page.
  final String? nextCursor;

  factory TransactionPage.fromJson(Map<String, dynamic> json) => TransactionPage(
    items: [for (final item in json['items'] as List) Transaction.fromJson(item as Map<String, dynamic>)],
    nextCursor: json['nextCursor'] as String?,
  );
}
