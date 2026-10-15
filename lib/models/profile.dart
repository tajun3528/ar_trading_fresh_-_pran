enum UserRole {
  owner,
  salesman,
  deliveryman;

  static UserRole parse(String value) => UserRole.values.byName(value);
}

enum UserStatus {
  pending,
  active,
  inactive;

  static UserStatus parse(String value) => UserStatus.values.byName(value);
}

class Profile {
  Profile({
    required this.userId,
    required this.name,
    required this.mobile,
    this.email,
    required this.role,
    required this.status,
    this.pairedDeliverymanId,
    this.companyId,
  });

  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      userId: json['user_id'] as String,
      name: json['name'] as String? ?? '',
      mobile: json['mobile'] as String?,
      email: json['email'] as String?,
      role: UserRole.parse(json['role'] as String),
      status: UserStatus.parse(json['status'] as String),
      pairedDeliverymanId: json['paired_deliveryman_id'] as String?,
      companyId: json['company_id'] as String?,
    );
  }

  final String userId;
  final String name;
  final String? mobile;
  final String? email;
  final UserRole role;
  final UserStatus status;
  final String? pairedDeliverymanId;

  /// The company (vendor) this salesman is assigned to. Null for
  /// owner/deliveryman, and for a salesman not yet assigned one.
  final String? companyId;

  bool get isActive => status == UserStatus.active;
}
