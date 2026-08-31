import 'dart:async';

import 'package:diary/state_management/cubits/route_assistant_cubit/route_assistant_cubit.dart';
import 'package:diary/state_management/cubits/route_assistant_cubit/route_assistant_cubit_state.dart';
import 'package:diary/theme/dimensions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Bottom sheet di ricerca destinazione (punto B). Su "Vai" calcola il percorso
/// e si chiude, lasciando la mappa libera con pallini e selettori.
class RouteAssistantSearchSheet extends StatefulWidget {
  const RouteAssistantSearchSheet({super.key});

  @override
  State<RouteAssistantSearchSheet> createState() =>
      _RouteAssistantSearchSheetState();
}

class _RouteAssistantSearchSheetState extends State<RouteAssistantSearchSheet> {
  final _controller = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 300),
      () => context.read<RouteAssistantCubit>().search(value),
    );
  }

  Future<void> _confirm() async {
    final cubit = context.read<RouteAssistantCubit>();
    await cubit.confirmDestination();
    if (!mounted) return;
    final state = cubit.state;
    if (state.errorMessage == null && state.routePoints.isNotEmpty) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<RouteAssistantCubit>();
    return Padding(
      padding: EdgeInsets.only(
        left: Dimensions.paddingMedium,
        right: Dimensions.paddingMedium,
        top: Dimensions.paddingMedium,
        bottom:
            MediaQuery.of(context).viewInsets.bottom + Dimensions.paddingMedium,
      ),
      child: BlocBuilder<RouteAssistantCubit, RouteAssistantState>(
        builder: (context, state) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _controller,
                autofocus: true,
                onChanged: _onChanged,
                decoration: InputDecoration(
                  hintText: 'Cerca una destinazione',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: state.isSearching
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : null,
                ),
              ),
              const SizedBox(height: Dimensions.paddingSmall),
              ..._results(cubit, state),
              if (state.errorMessage != null) ...[
                const SizedBox(height: Dimensions.paddingSmall),
                Text(
                  state.errorMessage!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                ),
              ],
              const SizedBox(height: Dimensions.paddingSmall),
              FilledButton.icon(
                onPressed: state.destination == null || state.isRouting
                    ? null
                    : _confirm,
                icon: state.isRouting
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.navigation_outlined),
                label: const Text('Vai'),
              ),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _results(RouteAssistantCubit cubit, RouteAssistantState state) {
    return state.searchResults.map((place) {
      final selected = identical(place, state.destination);
      return ListTile(
        dense: true,
        leading: Icon(
          selected ? Icons.radio_button_checked : Icons.place_outlined,
        ),
        title: Text(place.label, maxLines: 2, overflow: TextOverflow.ellipsis),
        selected: selected,
        onTap: () => cubit.selectDestination(place),
      );
    }).toList();
  }
}

/// Apre il bottom sheet di ricerca fornendo il RouteAssistantCubit gia' esistente.
Future<void> showRouteAssistantSearch(BuildContext context) {
  final cubit = context.read<RouteAssistantCubit>()..openSearch();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => BlocProvider.value(
      value: cubit,
      child: const RouteAssistantSearchSheet(),
    ),
  ).whenComplete(cubit.closeSearch);
}
