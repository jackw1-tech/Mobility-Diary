import 'package:diary/network/dto/auth_session_dto.dart';
import 'package:diary/network/dto/user_dto.dart';

class AuthApiException implements Exception {
  final String message;

  const AuthApiException(this.message);

  @override
  String toString() => message;
}

/// Provider layer (Pine): accesso grezzo alle REST API di autenticazione.
/// Restituisce sempre DTO grezzi: la trasformazione in model di dominio e'
/// compito esclusivo di [AuthMapper] (layer Mapper).
abstract class AuthService {
  Future<AuthSessionDto> login({
    required String email,
    required String password,
    required String deviceName,
  });

  Future<AuthSessionDto> register({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    required String deviceName,
  });

  Future<UserDto> fetchCurrentUser({required String accessToken});

  Future<void> logout({required String accessToken});
}
