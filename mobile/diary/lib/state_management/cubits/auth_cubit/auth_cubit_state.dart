import 'package:diary/features/auth/domain/auth_user.dart';

enum AuthStatus {
  initial,
  loading,
  authenticated,
  unauthenticated,
  submitting,
}

class AuthCubitState {
  final AuthStatus status;
  final AuthUser? user;
  final String? errorMessage;

  const AuthCubitState({
    required this.status,
    this.user,
    this.errorMessage,
  });

  const AuthCubitState.initial()
      : status = AuthStatus.initial,
        user = null,
        errorMessage = null;

  bool get isLoading =>
      status == AuthStatus.loading || status == AuthStatus.submitting;

  bool get isAuthenticated => status == AuthStatus.authenticated;

  AuthCubitState copyWith({
    AuthStatus? status,
    AuthUser? user,
    String? errorMessage,
    bool clearError = false,
    bool clearUser = false,
  }) {
    return AuthCubitState(
      status: status ?? this.status,
      user: clearUser ? null : user ?? this.user,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}
