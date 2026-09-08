import 'package:diary/repositories/acquisition_repository.dart';

String trackingErrorMessage(Object error) {
  if (error is ActiveTripOnAnotherDeviceException) {
    return error.message;
  }
  if (error is PendingTripSyncException) {
    return error.message;
  }
  if (error is StartRequiresConnectionException) {
    return error.message;
  }
  if (error is AcquisitionPermissionException) {
    return error.message;
  }
  return 'Errore durante la comunicazione HTTP: $error';
}
