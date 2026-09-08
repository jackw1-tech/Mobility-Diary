import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Icona + colore per una categoria di luogo abituale (valori backend:
/// mobility.models.HabitualPlace.Category).
class CategoryMarker {
  final String category;
  final IconData icon;
  final Color color;

  const CategoryMarker({
    required this.category,
    required this.icon,
    required this.color,
  });
}

const List<CategoryMarker> categoryMarkers = [
  CategoryMarker(category: 'casa', icon: Icons.home, color: Color(0xFF2979FF)),
  CategoryMarker(
    category: 'universita',
    icon: Icons.school,
    color: Color(0xFF9C27B0),
  ),
  CategoryMarker(
    category: 'lavoro',
    icon: Icons.work,
    color: Color(0xFF00897B),
  ),
  CategoryMarker(
    category: 'palestra',
    icon: Icons.fitness_center,
    color: Color(0xFFFF5722),
  ),
  CategoryMarker(
    category: 'altro',
    icon: Icons.place,
    color: Color(0xFF757575),
  ),
];

const String _fallbackCategory = 'altro';
final Set<String> _knownCategories =
    categoryMarkers.map((m) => m.category).toSet();

/// Id dell'immagine registrata sullo style Mapbox per una categoria. Le
/// categorie sconosciute o vuote (il campo backend e' opzionale) ricadono
/// sull'icona generica 'altro'.
String iconIdForCategory(String category) {
  final resolved =
      _knownCategories.contains(category) ? category : _fallbackCategory;
  return 'habitual-place-icon-$resolved';
}

/// Disegna un pallino colorato con l'icona della categoria al centro, e lo
/// rasterizza in RGBA 32-bit con alpha premoltiplicato (formato richiesto da
/// MbxImage/addStyleImage).
Future<Uint8List> renderCategoryIconRgba(
  CategoryMarker marker, {
  double size = 96,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final radius = size / 2;
  final center = Offset(radius, radius);

  canvas.drawCircle(center, radius, Paint()..color = marker.color);
  canvas.drawCircle(
    center,
    radius - 1.5,
    Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3,
  );

  final textPainter = TextPainter(textDirection: TextDirection.ltr)
    ..text = TextSpan(
      text: String.fromCharCode(marker.icon.codePoint),
      style: TextStyle(
        fontSize: size * 0.5,
        fontFamily: marker.icon.fontFamily,
        package: marker.icon.fontPackage,
        color: Colors.white,
      ),
    )
    ..layout();
  textPainter.paint(
    canvas,
    Offset(radius - textPainter.width / 2, radius - textPainter.height / 2),
  );

  final picture = recorder.endRecording();
  final image = await picture.toImage(size.round(), size.round());
  final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final straight = byteData!.buffer.asUint8List();

  // MbxImage vuole alpha premoltiplicato: colore * (alpha / 255).
  final premultiplied = Uint8List(straight.length);
  for (var i = 0; i < straight.length; i += 4) {
    final a = straight[i + 3];
    premultiplied[i] = (straight[i] * a) ~/ 255;
    premultiplied[i + 1] = (straight[i + 1] * a) ~/ 255;
    premultiplied[i + 2] = (straight[i + 2] * a) ~/ 255;
    premultiplied[i + 3] = a;
  }
  return premultiplied;
}
