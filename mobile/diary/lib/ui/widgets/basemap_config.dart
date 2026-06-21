/// Sorgente dei tiles della mappa.
///
/// Default: Carto "Voyager" — mappa curata e leggibile, nessuna chiave API,
/// attiva subito. Buona per sviluppo e demo.
///
/// Produzione: passare a MapTiler (free 100k/mese, niente carta di credito,
/// si ferma da solo al limite) avviando con:
///   flutter run --dart-define=MAPTILER_KEY=la_tua_chiave
/// Non serve modificare il codice della pagina: se la chiave e' presente,
/// vengono usati automaticamente i tiles MapTiler.
class BasemapConfig {
  const BasemapConfig._();

  static const String _maptilerKey = String.fromEnvironment('MAPTILER_KEY');

  static bool get usesMapTiler => _maptilerKey.isNotEmpty;

  static String get urlTemplate => usesMapTiler
      ? 'https://api.maptiler.com/maps/streets-v2/{z}/{x}/{y}.png?key=$_maptilerKey'
      : 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png';

  /// Carto distribuisce i tiles su piu' sottodomini; MapTiler no.
  static List<String> get subdomains =>
      usesMapTiler ? const <String>[] : const <String>['a', 'b', 'c', 'd'];

  static String get attribution => usesMapTiler
      ? '© MapTiler © OpenStreetMap'
      : '© CARTO © OpenStreetMap';
}
