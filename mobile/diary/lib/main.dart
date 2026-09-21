import 'package:flutter/material.dart';
import 'package:diary/di/dependency_injector.dart';
import 'package:diary/repositories/impl/auth_repository_impl.dart';
import 'package:diary/routers/app_router.dart';
import 'package:diary/routers/auth_guard.dart';
import 'package:diary/state_management/cubits/acquisition_cubit/acquisition_cubit.dart';
import 'package:diary/state_management/cubits/auth_cubit/auth_cubit.dart';
import 'package:diary/state_management/cubits/auth_cubit/auth_cubit_state.dart';
import 'package:diary/theme/app_theme.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

const String _mapboxAccessToken = String.fromEnvironment(
  'MAPBOX_ACCESS_TOKEN',
  defaultValue: 'pk.eyJ1IjoicXEyMzI0MTI0MTI1IiwiYSI6ImNtbXFjaTJmMDB1NHkyd3NicHdqaDVuMTEifQ.3REx7uFtnUIaaSCpwgSCLg',
);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (_mapboxAccessToken.isNotEmpty) {
    MapboxOptions.setAccessToken(_mapboxAccessToken);
  }
  runApp(const DiaryApp());
}

class DiaryApp extends StatefulWidget {
  const DiaryApp({super.key});

  @override
  State<DiaryApp> createState() => _DiaryAppState();
}

class _DiaryAppState extends State<DiaryApp> {
  final AuthRepositoryImpl _authRepository = AuthRepositoryImpl();
  late final AppRouter _appRouter = AppRouter(
    authGuard: AuthGuard(_authRepository),
  );
  late final _routerConfig = _appRouter.config();

  @override
  Widget build(BuildContext context) {
    return DependencyInjector(
      authRepository: _authRepository,
      child: BlocListener<AuthCubit, AuthCubitState>(
        listenWhen: (previous, current) =>
            previous.status != AuthStatus.authenticated &&
            current.status == AuthStatus.authenticated,
        listener: (context, _) => //eseguita quando listen when è vera
            context.read<AcquisitionCubit>().restoreActiveTrip(),
        child: MaterialApp.router(
          title: 'Diary',
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeMode.system,
          routerConfig: _routerConfig,
        ),
      ),
    );
  }
}
