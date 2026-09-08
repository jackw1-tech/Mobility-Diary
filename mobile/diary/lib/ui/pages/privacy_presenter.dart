import 'package:diary/model/entities/privacy/privacy_level.dart';
import 'package:flutter/material.dart';

IconData privacyLevelIcon(PrivacyLevel level) {
  switch (level) {
    case PrivacyLevel.precise:
      return Icons.my_location;
    case PrivacyLevel.approximate:
      return Icons.location_searching;
    case PrivacyLevel.aggregated:
      return Icons.bar_chart;
  }
}
