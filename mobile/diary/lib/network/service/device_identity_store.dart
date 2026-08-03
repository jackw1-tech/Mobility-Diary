/// Provider layer (Pine): accesso grezzo allo storage sicuro del dispositivo
/// per leggere/creare l'identificativo univoco del device usato
/// dall'acquisizione (correlazione delle sessioni di tracking lato backend).
abstract class DeviceIdentityStore {
  Future<String> getOrCreateDeviceId();
}
