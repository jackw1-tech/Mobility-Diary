import 'package:flutter/material.dart';
import 'package:diary/di/dependency_injector.dart';
import 'package:diary/repositories/auth_repository.dart';
import 'package:diary/repositories/impl/auth_repository_impl.dart';
import 'package:diary/routers/app_router.dart';
import 'package:diary/routers/auth_guard.dart';
import 'package:diary/theme/app_theme.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

/// Token PUBBLICO Mapbox (pk....), passato a runtime con
/// `--dart-define=MAPBOX_ACCESS_TOKEN=pk....`. NON committare il token nel codice.
const String _mapboxAccessToken = String.fromEnvironment('MAPBOX_ACCESS_TOKEN');

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (_mapboxAccessToken.isNotEmpty) {
    MapboxOptions.setAccessToken(_mapboxAccessToken);
  }
  runApp(const DiaryApp());
}

class DiaryApp extends StatelessWidget {
  final AuthRepository? authRepository;

  const DiaryApp({
    this.authRepository,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final resolvedAuthRepository = authRepository ?? AuthRepositoryImpl();
    final appRouter = AppRouter(
      authGuard: AuthGuard(resolvedAuthRepository),
    );

    return DependencyInjector(
      authRepository: resolvedAuthRepository,
      child: MaterialApp.router(
        title: 'Diary',
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.system,
        routerConfig: appRouter.config(),
      ),
    );
  }
}
