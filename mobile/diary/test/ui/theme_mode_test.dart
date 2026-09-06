import 'package:diary/theme/app_theme.dart';
import 'package:diary/theme/color_palette.dart';
import 'package:diary/theme/semantic_colors.dart';
import 'package:diary/ui/widgets/home/sheet_handle.dart';
import 'package:diary/ui/widgets/state_message.dart';
import 'package:diary/ui/widgets/surface_card.dart';
import 'package:diary/ui/widgets/trip_map/trip_map_overlays.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppTheme configurations', () {
    test('lightTheme has light brightness and SemanticColors.light extension', () {
      final theme = AppTheme.lightTheme;
      expect(theme.brightness, Brightness.light);
      expect(theme.colorScheme.brightness, Brightness.light);
      expect(theme.colorScheme.primary, ColorPalette.primary);
      expect(theme.colorScheme.surface, ColorPalette.surface);

      final sem = theme.extension<SemanticColors>();
      expect(sem, isNotNull);
      expect(sem!.success, ColorPalette.success);
      expect(sem.warning, ColorPalette.warning);
      expect(sem.error, ColorPalette.error);
    });

    test('darkTheme has dark brightness and SemanticColors.dark extension', () {
      final theme = AppTheme.darkTheme;
      expect(theme.brightness, Brightness.dark);
      expect(theme.colorScheme.brightness, Brightness.dark);
      expect(theme.colorScheme.primary, ColorPalette.darkPrimary);
      expect(theme.colorScheme.surface, ColorPalette.darkSurface);

      final sem = theme.extension<SemanticColors>();
      expect(sem, isNotNull);
      expect(sem!.success, ColorPalette.darkSuccess);
      expect(sem.warning, ColorPalette.darkWarning);
      expect(sem.error, ColorPalette.darkError);
    });
  });

  group('UI widgets in light and dark mode', () {
    testWidgets('SurfaceCard adapts background and border in dark mode', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeMode.dark,
          home: const Scaffold(
            body: SurfaceCard(
              title: 'Card Title',
              child: Text('Card Content'),
            ),
          ),
        ),
      );

      expect(find.text('Card Title'), findsOneWidget);
      expect(find.text('Card Content'), findsOneWidget);

      final decoratedBoxFinder = find.byType(DecoratedBox).first;
      final decoratedBox = tester.widget<DecoratedBox>(decoratedBoxFinder);
      final boxDecoration = decoratedBox.decoration as BoxDecoration;
      expect(boxDecoration.color, ColorPalette.darkSurface);
      expect((boxDecoration.border as Border).top.color, ColorPalette.darkHairline);
    });

    testWidgets('SheetHandle adapts color in dark mode', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeMode.dark,
          home: const Scaffold(
            body: SheetHandle(),
          ),
        ),
      );

      final containerFinder = find.byType(Container).first;
      final container = tester.widget<Container>(containerFinder);
      final decoration = container.decoration as BoxDecoration;
      expect(
        decoration.color,
        ColorPalette.darkTextSecondary.withValues(alpha: 0.4),
      );
    });

    testWidgets('DistanceOverlay adapts to dark theme surface and primary icon', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeMode.dark,
          home: const Scaffold(
            body: DistanceOverlay(distanceMeters: 1500),
          ),
        ),
      );

      expect(find.text('1.50 km'), findsOneWidget);

      final decoratedBox = tester.widget<DecoratedBox>(find.byType(DecoratedBox).first);
      final boxDecoration = decoratedBox.decoration as BoxDecoration;
      expect(boxDecoration.color, ColorPalette.darkSurface);

      final icon = tester.widget<Icon>(find.byIcon(Icons.route));
      expect(icon.color, ColorPalette.darkPrimary);
    });

    testWidgets('StateMessage uses onSurfaceVariant icon color', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeMode.dark,
          home: const Scaffold(
            body: StateMessage(
              icon: Icons.info,
              text: 'Message',
            ),
          ),
        ),
      );

      final icon = tester.widget<Icon>(find.byIcon(Icons.info));
      expect(icon.color, ColorPalette.darkTextSecondary);
    });
  });
}
