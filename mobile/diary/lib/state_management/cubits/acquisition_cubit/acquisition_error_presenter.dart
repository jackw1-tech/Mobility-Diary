import 'package:diary/repositories/acquisition_repository.dart';

/// Traduce in messaggio utente le eccezioni che l'AcquisitionCubit rilancia ai
/// chiamanti. Sta nel layer di state management e non nella UI: i tipi di
/// eccezione appartengono al layer repository, la UI deve vederne solo il testo.
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
