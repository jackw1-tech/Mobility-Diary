import 'package:diary/network/service/impl/acquisition_local_database.dart';
import 'package:diary/network/service/device_identity_store.dart';
import 'package:diary/network/service/impl/secure_device_identity_store.dart';

import 'package:diary/repositories/impl/acquisition/trip_package_builder.dart';
import 'package:diary/repositories/impl/acquisition/trip_sync_queue_impl.dart';
import 'package:diary/network/service/impl/secure_auth_session_store.dart';
import 'package:diary/network/service/auth_session_store.dart';
import 'package:diary/network/service/auth_service.dart';
import 'package:diary/network/service/impl/auth_http_service.dart';
import 'package:diary/mappers/auth_mapper.dart';
import 'package:diary/mappers/analytics_mapper.dart';
import 'package:diary/network/service/analytics_service.dart';
import 'package:diary/network/service/places_service.dart';
import 'package:diary/network/service/privacy_settings_service.dart';
import 'package:diary/network/service/route_assistant_service.dart';
import 'package:diary/network/service/route_classifier_service.dart';
import 'package:diary/network/service/trip_privacy_export_service.dart';
import 'package:diary/network/service/trip_track_service.dart';
import 'package:diary/network/service/trips_service.dart';
import 'package:diary/mappers/ingestion_mapper.dart';
import 'package:diary/mappers/places_mapper.dart';
import 'package:diary/mappers/privacy_settings_mapper.dart';
import 'package:diary/mappers/route_assistant_mapper.dart';
import 'package:diary/mappers/trip_privacy_export_mapper.dart';
import 'package:diary/mappers/trips_mapper.dart';
import 'package:provider/provider.dart';
import 'package:diary/network/service/trip_ingestion_service.dart';
import 'package:diary/network/service/impl/trip_ingestion_dio_service.dart';
import 'package:diary/repositories/acquisition_repository.dart';
import 'package:diary/repositories/analytics_repository.dart';
import 'package:diary/repositories/auth_repository.dart';
import 'package:diary/repositories/impl/acquisition_repository_impl.dart';
import 'package:diary/repositories/impl/analytics_repository_impl.dart';
import 'package:diary/repositories/impl/auth_repository_impl.dart';
import 'package:diary/repositories/impl/location_repository_impl.dart';
import 'package:diary/repositories/impl/places_repository_impl.dart';
import 'package:diary/repositories/impl/privacy_settings_repository_impl.dart';
import 'package:diary/repositories/impl/route_assistant_repository_impl.dart';
import 'package:diary/repositories/impl/trip_privacy_export_repository_impl.dart';
import 'package:diary/repositories/impl/trip_track_repository_impl.dart';
import 'package:diary/repositories/impl/trips_repository_impl.dart';
import 'package:diary/repositories/location_repository.dart';
import 'package:diary/repositories/places_repository.dart';
import 'package:diary/repositories/privacy_settings_repository.dart';
import 'package:diary/repositories/route_assistant_repository.dart';
import 'package:diary/repositories/trip_privacy_export_repository.dart';
import 'package:diary/repositories/trip_track_repository.dart';
import 'package:diary/repositories/trips_repository.dart';
import 'package:diary/state_management/cubits/acquisition_cubit/acquisition_cubit.dart';
import 'package:diary/state_management/cubits/auth_cubit/auth_cubit.dart';
import 'package:diary/state_management/cubits/current_location_cubit/current_location_cubit.dart';
import 'package:diary/state_management/cubits/route_assistant_cubit/route_assistant_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pine/pine.dart';
import 'package:provider/single_child_widget.dart';

part 'blocs.dart';
part 'mappers.dart';
part 'providers.dart';
part 'repositories.dart';

class DependencyInjector extends StatelessWidget {
  final Widget child;
  final AuthRepository? authRepository;
  final AuthSessionStore? authSessionStore;

  const DependencyInjector({
    required this.child,
    this.authRepository,
    this.authSessionStore,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) => DependencyInjectorHelper(
        blocs: blocs,
        mappers: _mappers,
        repositories: buildRepositories(authRepository: authRepository),
        providers: buildProviders(authSessionStore: authSessionStore),
        child: child,
      );
}
