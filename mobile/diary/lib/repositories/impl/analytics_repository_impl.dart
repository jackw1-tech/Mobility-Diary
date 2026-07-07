import 'package:diary/features/analytics/domain/analytics.dart';
import 'package:diary/features/common/domain/app_result.dart';
import 'package:diary/mappers/analytics_mapper.dart';
import 'package:diary/network/service/analytics_service.dart';
import 'package:diary/repositories/analytics_repository.dart';

class AnalyticsRepositoryImpl implements AnalyticsRepository {
  final AnalyticsService _service;
  final AnalyticsMapper _mapper;

  const AnalyticsRepositoryImpl({
    required AnalyticsService service,
    required AnalyticsMapper mapper,
  })  : _service = service,
        _mapper = mapper;

  @override
  Future<AppResult<Analytics>> fetchAnalytics({String granularity = 'day'}) =>
      appResultOf(
        () async => _mapper.mapAnalytics(
          await _service.fetchAnalytics(granularity: granularity),
        ),
      );
}
