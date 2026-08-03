import 'package:diary/model/entities/analytics/analytics.dart';
import 'package:diary/utils/app_result.dart';

abstract class AnalyticsRepository {
  Future<AppResult<Analytics>> fetchAnalytics({String granularity = 'day'});
}
