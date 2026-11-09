class SubscriptionUpdateReport {
  final List<String> updatedIds;
  final Map<String, String> failures;
  const SubscriptionUpdateReport({
    this.updatedIds = const [],
    this.failures = const {},
  });
  bool get success => failures.isEmpty;
  Map<String, dynamic> toMap() => {
    'success': success,
    'updatedIds': updatedIds,
    'failedIds': failures.keys.toList(),
    'failures': failures,
  };
}
