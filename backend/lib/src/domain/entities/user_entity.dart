import '../enums/user_role.dart';

class UserEntity {
  const UserEntity({
    required this.id,
    required this.name,
    required this.cpfHash,
    required this.birthDate,
    required this.role,
    this.microAreaId,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String cpfHash;
  final DateTime birthDate;
  final UserRole role;
  final String? microAreaId;
  final DateTime createdAt;
  final DateTime updatedAt;
}
