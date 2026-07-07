import 'package:diary/features/analytics/domain/analytics.dart';
import 'package:diary/features/common/domain/app_result.dart';

abstract class AnalyticsRepository {
  Future<AppResult<Analytics>> fetchAnalytics({String granularity = 'day'});
}
