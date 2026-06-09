import 'package:flutter/material.dart';
import 'package:diary/di/dependency_injector.dart';
import 'package:diary/repositories/auth_repository.dart';
import 'package:diary/repositories/impl/auth_repository_impl.dart';
import 'package:diary/routers/app_router.dart';
import 'package:diary/routers/auth_guard.dart';
import 'package:diary/theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
