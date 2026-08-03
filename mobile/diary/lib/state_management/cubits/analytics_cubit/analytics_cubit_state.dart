import 'package:diary/model/entities/analytics/analytics.dart';

enum AnalyticsStatus {
  initial,
  loading,
  ready,
  empty,
  error,
}

class AnalyticsCubitState {
  final AnalyticsStatus status;
  final Analytics? data;
  final String granularity;
  final String? error;

  const AnalyticsCubitState({
    required this.status,
    this.data,
    this.granularity = 'day',
    this.error,
  });

  const AnalyticsCubitState.initial()
      : status = AnalyticsStatus.initial,
        data = null,
        granularity = 'day',
        error = null;
}
