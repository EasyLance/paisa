// Hand-written on purpose: a model that fails loudly on a missing field is a
// better contract check than generated code nobody reads. Shapes come from the
// recorded responses in test/fixtures/. Add a model with the phase that uses it.

class Me {
  const Me({required this.id, required this.email, this.displayName});

  final String id;
  final String? email;
  final String? displayName;

  factory Me.fromJson(Map<String, dynamic> json) => Me(
    id: json['id'] as String,
    email: json['email'] as String?,
    displayName: json['displayName'] as String?,
  );
}

/// What a role may do, mirroring `apps/api/src/domain/permissions.js`. The API
/// checks every request again; this only decides what the UI offers.
enum Capability { read, comment, split, reclassify, create, edit, manageBook }

const _roleCapabilities = <String, Set<Capability>>{
  'viewer': {Capability.read},
  'reviewer': {Capability.read, Capability.comment, Capability.split, Capability.reclassify},
  'editor': {Capability.read, Capability.comment, Capability.split, Capability.reclassify, Capability.create, Capability.edit},
  'book_owner': {Capability.read, Capability.comment, Capability.split, Capability.reclassify, Capability.create, Capability.edit, Capability.manageBook},
  'workspace_admin': {Capability.read, Capability.comment, Capability.split, Capability.reclassify, Capability.create, Capability.edit, Capability.manageBook},
};

class Book {
  const Book({
    required this.id,
    required this.name,
    required this.visibility,
    required this.currency,
    required this.timezone,
    required this.periodStartDay,
    required this.role,
  });

  final String id;
  final String name;
  final String visibility;
  final String currency;
  final String timezone;
  final int periodStartDay;
  final String role;

  bool can(Capability capability) => _roleCapabilities[role]?.contains(capability) ?? false;

  factory Book.fromJson(Map<String, dynamic> json) => Book(
    id: json['id'] as String,
    name: json['name'] as String,
    visibility: json['visibility'] as String,
    currency: json['currency'] as String,
    timezone: json['timezone'] as String,
    periodStartDay: json['periodStartDay'] as int,
    role: json['role'] as String,
  );
}
