import 'package:diary/model/entities/auth/auth_user.dart';

class AuthSession {
  final AuthUser user;
  final String accessToken;
  final String tokenType;
  final DateTime expiresAt;

  const AuthSession({
    required this.user,
    required this.accessToken,
    required this.tokenType,
    required this.expiresAt,
  });

  // La deserializzazione dal wire format del backend e' compito di
  // `AuthSessionDto.fromJson` + `AuthMapper` (layer Mapper), non del model.
}
