import 'package:diary/features/acquisition/data/acquisition_local_database.dart';
import 'package:diary/features/acquisition/device/device_identity_store.dart';
import 'package:diary/features/acquisition/sync/trip_ingestion_api.dart';
import 'package:diary/features/acquisition/sync/trip_package_builder.dart';
import 'package:diary/features/acquisition/sync/trip_sync_queue_impl.dart';
import 'package:diary/network/service/analytics_service.dart';
import 'package:diary/network/service/places_service.dart';
import 'package:diary/network/service/privacy_settings_service.dart';
import 'package:diary/network/service/route_assistant_service.dart';
import 'package:diary/network/service/route_classifier_service.dart';
import 'package:diary/network/service/trip_privacy_export_service.dart';
import 'package:diary/network/service/trip_track_service.dart';
import 'package:diary/network/service/trips_service.dart';
import 'package:diary/repositories/acquisition_repository.dart';
import 'package:diary/repositories/auth_repository.dart';
import 'package:diary/repositories/impl/acquisition_repository_impl.dart';
import 'package:diary/repositories/impl/auth_repository_impl.dart';
import 'package:diary/state_management/cubits/acquisition_cubit/acquisition_cubit.dart';
import 'package:diary/state_management/cubits/auth_cubit/auth_cubit.dart';
import 'package:diary/state_management/cubits/route_assistant_cubit/route_assistant_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:latlong2/latlong.dart' as ll;
import 'package:pine/pine.dart';
import 'package:provider/single_child_widget.dart';

part 'blocs.dart';
part 'mappers.dart';
part 'providers.dart';
part 'repositories.dart';

class DependencyInjector extends StatelessWidget {
  final Widget child;
  final AuthRepository? authRepository;

  const DependencyInjector({
    required this.child,
    this.authRepository,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) => DependencyInjectorHelper(
        blocs: blocs,
        mappers: _mappers,
        repositories: buildRepositories(authRepository: authRepository),
        providers: _providers,
        child: child,
      );
}
