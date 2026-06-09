import 'package:diary/state_management/cubits/auth_cubit/auth_cubit.dart';
import 'package:diary/state_management/cubits/auth_cubit/auth_cubit_state.dart';
import 'package:diary/theme/color_palette.dart';
import 'package:diary/theme/dimensions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();

  bool _isRegister = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<AuthCubit, AuthCubitState>(
      listenWhen: (previous, current) =>
          previous.errorMessage != current.errorMessage &&
          current.errorMessage != null,
      listener: (context, state) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(state.errorMessage!),
            backgroundColor: ColorPalette.error,
          ),
        );
      },
      builder: (context, state) {
        return Scaffold(
          backgroundColor: ColorPalette.background,
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(Dimensions.paddingLarge),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Material(
                    color: ColorPalette.surface,
                    elevation: Dimensions.cardElevation,
                    borderRadius: BorderRadius.circular(
                      Dimensions.borderRadiusMedium,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(Dimensions.paddingLarge),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _Header(isRegister: _isRegister),
                            const SizedBox(height: Dimensions.paddingLarge),
                            SegmentedButton<bool>(
                              segments: const [
                                ButtonSegment(
                                  value: false,
                                  icon: Icon(Icons.login),
                                  label: Text('Login'),
                                ),
                                ButtonSegment(
                                  value: true,
                                  icon: Icon(Icons.person_add_alt_1),
                                  label: Text('Registrati'),
                                ),
                              ],
                              selected: {_isRegister},
                              onSelectionChanged: state.isLoading
                                  ? null
                                  : (selection) {
                                      setState(() {
                                        _isRegister = selection.first;
                                      });
                                    },
                            ),
                            const SizedBox(height: Dimensions.paddingMedium),
                            if (_isRegister) ...[
                              TextFormField(
                                controller: _firstNameController,
                                textInputAction: TextInputAction.next,
                                decoration: const InputDecoration(
                                  prefixIcon: Icon(Icons.badge_outlined),
                                  labelText: 'Nome',
                                ),
                              ),
                              const SizedBox(height: Dimensions.paddingSmall),
                              TextFormField(
                                controller: _lastNameController,
                                textInputAction: TextInputAction.next,
                                decoration: const InputDecoration(
                                  prefixIcon: Icon(Icons.badge),
                                  labelText: 'Cognome',
                                ),
                              ),
                              const SizedBox(height: Dimensions.paddingSmall),
                            ],
                            TextFormField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              autofillHints: const [AutofillHints.email],
                              decoration: const InputDecoration(
                                prefixIcon: Icon(Icons.mail_outline),
                                labelText: 'Email',
                              ),
                              validator: _validateEmail,
                            ),
                            const SizedBox(height: Dimensions.paddingSmall),
                            TextFormField(
                              controller: _passwordController,
                              obscureText: _obscurePassword,
                              textInputAction: _isRegister
                                  ? TextInputAction.next
                                  : TextInputAction.done,
                              autofillHints: const [AutofillHints.password],
                              decoration: InputDecoration(
                                prefixIcon: const Icon(Icons.lock_outline),
                                labelText: 'Password',
                                suffixIcon: IconButton(
                                  tooltip: _obscurePassword
                                      ? 'Mostra password'
                                      : 'Nascondi password',
                                  onPressed: () {
                                    setState(() {
                                      _obscurePassword = !_obscurePassword;
                                    });
                                  },
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility
                                        : Icons.visibility_off,
                                  ),
                                ),
                              ),
                              validator: _validatePassword,
                              onFieldSubmitted: (_) {
                                if (!_isRegister) {
                                  _submit();
                                }
                              },
                            ),
                            if (_isRegister) ...[
                              const SizedBox(height: Dimensions.paddingSmall),
                              TextFormField(
                                controller: _confirmPasswordController,
                                obscureText: _obscurePassword,
                                textInputAction: TextInputAction.done,
                                decoration: const InputDecoration(
                                  prefixIcon: Icon(Icons.lock_reset),
                                  labelText: 'Conferma password',
                                ),
                                validator: _validateConfirmPassword,
                                onFieldSubmitted: (_) => _submit(),
                              ),
                            ],
                            const SizedBox(height: Dimensions.paddingLarge),
                            FilledButton.icon(
                              onPressed: state.isLoading ? null : _submit,
                              icon: state.isLoading
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Icon(
                                      _isRegister
                                          ? Icons.person_add_alt_1
                                          : Icons.login,
                                    ),
                              label: Text(
                                _isRegister ? 'Crea account' : 'Entra',
                              ),
                            ),
                            if (kDebugMode) ...[
                              const SizedBox(height: Dimensions.paddingSmall),
                              TextButton.icon(
                                onPressed: () =>
                                    context.read<AuthCubit>().loginAsDev(),
                                icon: const Icon(Icons.developer_mode),
                                label: const Text('[DEV] Salta login'),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  String? _validateEmail(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) {
      return 'Inserisci email';
    }
    if (!text.contains('@') || !text.contains('.')) {
      return 'Email non valida';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    final text = value ?? '';
    if (text.length < 8) {
      return 'Almeno 8 caratteri';
    }
    return null;
  }

  String? _validateConfirmPassword(String? value) {
    if (!_isRegister) {
      return null;
    }
    if (value != _passwordController.text) {
      return 'Le password non coincidono';
    }
    return null;
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final cubit = context.read<AuthCubit>();
    if (_isRegister) {
      cubit.register(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
      );
    } else {
      cubit.login(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
    }
  }
}

class _Header extends StatelessWidget {
  final bool isRegister;

  const _Header({required this.isRegister});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: ColorPalette.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(Dimensions.borderRadiusMedium),
          ),
          child: Icon(
            isRegister ? Icons.person_add_alt_1 : Icons.lock_open,
            color: ColorPalette.primary,
          ),
        ),
        const SizedBox(width: Dimensions.paddingMedium),
        Expanded(
          child: Text(
            isRegister ? 'Nuovo account' : 'Mobility Diary',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
      ],
    );
  }
}
