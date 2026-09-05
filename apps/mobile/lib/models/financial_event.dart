class FinancialEvent {
  const FinancialEvent({
    required this.sourceHash,
    required this.kind,
    required this.amountMinor,
    required this.occurredAt,
    this.merchant,
    this.externalRef,
  });

  final String sourceHash;
  final String kind;
  final String amountMinor;
  final DateTime occurredAt;
  final String? merchant;
  final String? externalRef;

  Map<String, dynamic> toJson() => {
    'sourceType': 'sms',
    'sourceHash': sourceHash,
    'kind': kind,
    'amountMinor': amountMinor,
    'occurredAt': occurredAt.toUtc().toIso8601String(),
    if (merchant != null) 'merchant': merchant,
    if (externalRef != null) 'externalRef': externalRef,
  };

  factory FinancialEvent.fromJson(Map<String, dynamic> json) => FinancialEvent(
    sourceHash: json['sourceHash'] as String,
    kind: json['kind'] as String,
    amountMinor: json['amountMinor'] as String,
    occurredAt: DateTime.parse(json['occurredAt'] as String),
    merchant: json['merchant'] as String?,
    externalRef: json['externalRef'] as String?,
  );
}
