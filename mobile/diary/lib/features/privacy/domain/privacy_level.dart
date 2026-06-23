enum PrivacyLevel {
  precise('precise', 'Precisa'),
  approximate('approximate', 'Approssimata'),
  aggregated('aggregated', 'Aggregata');

  final String wireName;
  final String label;

  const PrivacyLevel(this.wireName, this.label);

  static PrivacyLevel fromWire(String value) {
    return PrivacyLevel.values.firstWhere(
      (level) => level.wireName == value,
      orElse: () => PrivacyLevel.precise,
    );
  }
}
