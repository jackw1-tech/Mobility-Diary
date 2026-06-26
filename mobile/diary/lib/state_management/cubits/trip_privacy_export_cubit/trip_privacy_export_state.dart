part of 'trip_privacy_export_cubit.dart';

enum TripPrivacyExportStatus {
  initial,
  loading,
  ready,
  error,
}

class TripPrivacyExportState {
  final TripPrivacyExportStatus status;
  final TripPrivacyExportDto? export;
  final String? error;

  const TripPrivacyExportState({
    required this.status,
    this.export,
    this.error,
  });

  const TripPrivacyExportState.initial()
      : status = TripPrivacyExportStatus.initial,
        export = null,
        error = null;

  bool get isLoading =>
      status == TripPrivacyExportStatus.initial ||
      status == TripPrivacyExportStatus.loading;

  TripPrivacyExportState copyWith({
    TripPrivacyExportStatus? status,
    TripPrivacyExportDto? export,
    String? error,
    bool clearError = false,
  }) {
    return TripPrivacyExportState(
      status: status ?? this.status,
      export: export ?? this.export,
      error: clearError ? null : error ?? this.error,
    );
  }
}
