import 'package:flutter/material.dart';
import 'package:diary/di/dependency_injector.dart';
import 'package:diary/routers/app_router.dart';
import 'package:diary/theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DiaryApp());
}

class DiaryApp extends StatelessWidget {
  const DiaryApp({super.key});

  @override
  Widget build(BuildContext context) {
    final appRouter = AppRouter();

    return DependencyInjector(
        child: MaterialApp.router(
      title: 'Diary',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      routerConfig: appRouter.config(),
    ));
  }
}
