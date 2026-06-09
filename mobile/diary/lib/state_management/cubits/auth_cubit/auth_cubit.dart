import 'package:diary/features/auth/domain/auth_user.dart';
import 'package:diary/repositories/auth_repository.dart';
import 'package:diary/state_management/cubits/auth_cubit/auth_cubit_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class AuthCubit extends Cubit<AuthCubitState> {
  final AuthRepository _repository;

  AuthCubit(this._repository) : super(const AuthCubitState.initial());

  AuthUser? get currentUser => state.user;

  int? get currentUserId => state.user?.id;

  String? get currentUserEmail => state.user?.email;

  String? get accessToken => _repository.accessToken;

  Future<void> initialize() async {
    emit(state.copyWith(status: AuthStatus.loading, clearError: true));
    final session = await _repository.restoreSession();
    if (session == null) {
      emit(
        state.copyWith(
          status: AuthStatus.unauthenticated,
          clearError: true,
          clearUser: true,
        ),
      );
      return;
    }
    emit(
      state.copyWith(
        status: AuthStatus.authenticated,
        user: session.user,
        clearError: true,
      ),
    );
  }

  Future<void> login({
    required String email,
    required String password,
  }) async {
    await _submit(
      () => _repository.login(email: email, password: password),
    );
  }

  Future<void> register({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
  }) async {
    await _submit(
      () => _repository.register(
        email: email,
        password: password,
        firstName: firstName,
        lastName: lastName,
      ),
    );
  }

  void loginAsDev() {
    const fakeUser = AuthUser(
      id: 0,
      email: 'dev@example.com',
      firstName: 'Dev',
      lastName: 'User',
      isStaff: false,
      isSuperuser: false,
    );
    emit(state.copyWith(
      status: AuthStatus.authenticated,
      user: fakeUser,
      clearError: true,
    ));
  }

  Future<void> logout() async {
    emit(state.copyWith(status: AuthStatus.submitting, clearError: true));
    await _repository.logout();
    emit(
      state.copyWith(
        status: AuthStatus.unauthenticated,
        clearError: true,
        clearUser: true,
      ),
    );
  }

  Future<void> refreshCurrentUser() async {
    if (_repository.accessToken == null) {
      emit(
        state.copyWith(
          status: AuthStatus.unauthenticated,
          clearError: true,
          clearUser: true,
        ),
      );
      return;
    }

    try {
      final user = await _repository.loadCurrentUser();
      emit(
        state.copyWith(
          status: AuthStatus.authenticated,
          user: user,
          clearError: true,
        ),
      );
    } catch (error) {
      await _repository.logout();
      emit(
        state.copyWith(
          status: AuthStatus.unauthenticated,
          errorMessage: error.toString(),
          clearUser: true,
        ),
      );
    }
  }

  Future<void> _submit(Future<dynamic> Function() action) async {
    emit(state.copyWith(status: AuthStatus.submitting, clearError: true));
    try {
      final session = await action();
      emit(
        state.copyWith(
          status: AuthStatus.authenticated,
          user: session.user,
          clearError: true,
        ),
      );
    } catch (error) {
      emit(
        state.copyWith(
          status: AuthStatus.unauthenticated,
          errorMessage: error.toString(),
          clearUser: true,
        ),
      );
    }
  }
}
