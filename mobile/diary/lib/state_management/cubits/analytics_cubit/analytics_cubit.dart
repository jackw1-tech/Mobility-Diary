import 'package:diary/network/service/analytics_service.dart';
import 'package:diary/state_management/cubits/analytics_cubit/analytics_cubit_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class AnalyticsCubit extends Cubit<AnalyticsCubitState> {
  final AnalyticsService _service;

  AnalyticsCubit(this._service) : super(const AnalyticsCubitState.initial());

  Future<void> load() => _fetch(state.granularity);

  Future<void> setGranularity(String granularity) => _fetch(granularity);

  Future<void> _fetch(String granularity) async {
    emit(AnalyticsCubitState(
      status: AnalyticsStatus.loading,
      granularity: granularity,
    ));
    try {
      final data = await _service.fetchAnalytics(granularity: granularity);
      emit(AnalyticsCubitState(
        status: data.hasData ? AnalyticsStatus.ready : AnalyticsStatus.empty,
        data: data,
        granularity: granularity,
      ));
    } catch (error) {
      emit(AnalyticsCubitState(
        status: AnalyticsStatus.error,
        granularity: granularity,
        error: error.toString(),
      ));
    }
  }
}
