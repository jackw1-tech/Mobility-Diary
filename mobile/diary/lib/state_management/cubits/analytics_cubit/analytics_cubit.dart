import 'package:diary/repositories/analytics_repository.dart';
import 'package:diary/state_management/cubits/analytics_cubit/analytics_cubit_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class AnalyticsCubit extends Cubit<AnalyticsCubitState> {
  final AnalyticsRepository _repository;

  AnalyticsCubit(this._repository) : super(const AnalyticsCubitState.initial());

  Future<void> load() => _fetch(state.granularity);

  Future<void> setGranularity(String granularity) => _fetch(granularity);

  Future<void> _fetch(String granularity) async {
    emit(AnalyticsCubitState(
      status: AnalyticsStatus.loading,
      granularity: granularity,
    ));
    final result = await _repository.fetchAnalytics(granularity: granularity);
    final failure = result.failure;
    if (failure != null) {
      emit(AnalyticsCubitState(
        status: AnalyticsStatus.error,
        granularity: granularity,
        error: failure.message,
      ));
      return;
    }
    final data = result.requireValue;
    emit(AnalyticsCubitState(
      status: data.hasData ? AnalyticsStatus.ready : AnalyticsStatus.empty,
      data: data,
      granularity: granularity,
    ));
  }
}
