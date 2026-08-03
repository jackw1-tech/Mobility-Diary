import 'package:diary/network/dto/user_dto.dart';

/// DTO grezzo (shape wire) della sessione di autenticazione restituita da
/// `/auth/login` e `/auth/register`. Consumato solo da [AuthMapper].
class AuthSessionDto {
  final UserDto user;
  final String accessToken;
  final String tokenType;
  final DateTime expiresAt;

  const AuthSessionDto({
    required this.user,
    required this.accessToken,
    required this.tokenType,
    required this.expiresAt,
  });

  factory AuthSessionDto.fromJson(Map<String, dynamic> json) {
    return AuthSessionDto(
      user: UserDto.fromJson(json['user'] as Map<String, dynamic>),
      accessToken: json['access_token'] as String,
      tokenType: json['token_type'] as String? ?? 'Bearer',
      expiresAt: DateTime.parse(json['expires_at'] as String),
    );
  }
}
