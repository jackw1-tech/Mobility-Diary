import 'package:diary/features/common/domain/app_result.dart';
import 'package:diary/features/analytics/domain/analytics.dart';
import 'package:diary/repositories/analytics_repository.dart';
import 'package:diary/state_management/cubits/analytics_cubit/analytics_cubit.dart';
import 'package:diary/state_management/cubits/analytics_cubit/analytics_cubit_state.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeAnalyticsService implements AnalyticsRepository {
  Analytics? result;
  Object? error;
  String? lastGranularity;

  @override
  Future<AppResult<Analytics>> fetchAnalytics(
      {String granularity = 'day'}) async {
    lastGranularity = granularity;
    final failure = error;
    if (failure != null) return AppResult.failure(toAppFailure(failure));
    return AppResult.success(result!);
  }
}

Analytics _analytics({bool hasData = true}) => Analytics(
      granularity: 'day',
      hasData: hasData,
      buckets: const [],
      prevalentMode: null,
      frequentRoutes: const [],
      heatmap: const [],
    );

void main() {
  group('AnalyticsCubit', () {
    test('emits ready when the user has data', () async {
      final service = FakeAnalyticsService()..result = _analytics();
      final cubit = AnalyticsCubit(service);
      addTearDown(cubit.close);

      await cubit.load();

      expect(cubit.state.status, AnalyticsStatus.ready);
      expect(cubit.state.data, isNotNull);
    });

    test('emits empty when the user has no data', () async {
      final service = FakeAnalyticsService()
        ..result = _analytics(hasData: false);
      final cubit = AnalyticsCubit(service);
      addTearDown(cubit.close);

      await cubit.load();

      expect(cubit.state.status, AnalyticsStatus.empty);
    });

    test('emits error when the service fails', () async {
      final service = FakeAnalyticsService()..error = Exception('boom');
      final cubit = AnalyticsCubit(service);
      addTearDown(cubit.close);

      await cubit.load();

      expect(cubit.state.status, AnalyticsStatus.error);
      expect(cubit.state.error, contains('boom'));
    });

    test('setGranularity refetches with the new granularity', () async {
      final service = FakeAnalyticsService()..result = _analytics();
      final cubit = AnalyticsCubit(service);
      addTearDown(cubit.close);

      await cubit.setGranularity('week');

      expect(service.lastGranularity, 'week');
      expect(cubit.state.granularity, 'week');
    });
  });
}
