import 'package:diary/repositories/acquisition_repository.dart';
import 'package:diary/repositories/auth_repository.dart';
import 'package:diary/repositories/impl/acquisition_repository_impl.dart';
import 'package:diary/repositories/impl/auth_repository_impl.dart';
import 'package:diary/state_management/cubits/acquisition_cubit/acquisition_cubit.dart';
import 'package:diary/state_management/cubits/auth_cubit/auth_cubit.dart';
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
