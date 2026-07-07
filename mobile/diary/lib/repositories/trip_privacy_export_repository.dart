import 'package:diary/features/common/domain/app_result.dart';
import 'package:diary/features/privacy/domain/trip_privacy_export.dart';

abstract class TripPrivacyExportRepository {
  Future<AppResult<TripPrivacyExport>> fetchExport(int tripId);
}
