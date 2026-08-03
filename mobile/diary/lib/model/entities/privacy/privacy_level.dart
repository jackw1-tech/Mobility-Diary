import 'package:flutter/material.dart';

enum PrivacyLevel {
  precise('precise', 'Precisa', Icons.my_location),
  approximate('approximate', 'Approssimata', Icons.location_searching),
  aggregated('aggregated', 'Aggregata', Icons.bar_chart);

  final String wireName;
  final String label;
  final IconData icon;

  const PrivacyLevel(this.wireName, this.label, this.icon);

  static PrivacyLevel fromWire(String value) {
    return PrivacyLevel.values.firstWhere(
      (level) => level.wireName == value,
      orElse: () => PrivacyLevel.precise,
    );
  }
}
