import 'package:diary/model/entities/auth/auth_session.dart';
import 'package:diary/model/entities/auth/auth_user.dart';
import 'package:diary/network/dto/auth_session_dto.dart';
import 'package:diary/network/dto/user_dto.dart';

class AuthMapper {
  AuthUser mapUser(UserDto dto) => AuthUser(
        id: dto.id,
        email: dto.email,
        firstName: dto.firstName,
        lastName: dto.lastName,
        isStaff: dto.isStaff,
        isSuperuser: dto.isSuperuser,
      );

  AuthSession mapSession(AuthSessionDto dto) => AuthSession(
        user: mapUser(dto.user),
        accessToken: dto.accessToken,
        tokenType: dto.tokenType,
        expiresAt: dto.expiresAt,
      );
}
