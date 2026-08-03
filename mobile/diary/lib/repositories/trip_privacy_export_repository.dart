import 'package:diary/utils/app_result.dart';
import 'package:diary/model/entities/privacy/trip_privacy_export.dart';

abstract class TripPrivacyExportRepository {
  Future<AppResult<TripPrivacyExport>> fetchExport(int tripId);
}
