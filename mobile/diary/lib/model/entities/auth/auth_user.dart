class AuthUser {
  final int id;
  final String email;
  final String firstName;
  final String lastName;
  final bool isStaff;
  final bool isSuperuser;

  const AuthUser({
    required this.id,
    required this.email,
    required this.firstName,
    required this.lastName,
    required this.isStaff,
    required this.isSuperuser,
  });

  String get displayName {
    final fullName = '$firstName $lastName'.trim();
    if (fullName.isNotEmpty) {
      return fullName;
    }
    if (email.isNotEmpty) {
      return email;
    }
    return 'Utente';
  }

  /// Serializzazione per la cache locale (vedi `AuthSessionStore.saveUser`).
  /// La deserializzazione dal wire format del backend e' compito di
  /// `UserDto.fromJson` + `AuthMapper` (layer Mapper), non del model.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'first_name': firstName,
      'last_name': lastName,
      'is_staff': isStaff,
      'is_superuser': isSuperuser,
    };
  }
}
