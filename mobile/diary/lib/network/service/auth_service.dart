import 'package:diary/network/dto/auth_session_dto.dart';
import 'package:diary/network/dto/user_dto.dart';

class AuthApiException implements Exception {
  final String message;

  const AuthApiException(this.message);

  @override
  String toString() => message;
}

abstract class AuthService {
  Future<AuthSessionDto> login({
    required String email,
    required String password,
  });

  Future<AuthSessionDto> register({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
  });

  Future<UserDto> fetchCurrentUser({required String accessToken});

  Future<void> logout({required String accessToken});
}
