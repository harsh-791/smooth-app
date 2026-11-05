import 'package:openfoodfacts/openfoodfacts.dart';

/// A signed-in user identified by a Keycloak token, not a password.
///
/// [User.password] stays empty so background tasks can still round-trip the
/// user through [User.toJson]. [toData] is what the API client puts in the
/// request body, and it does not include a password.
class OffUser extends User {
  const OffUser({required super.userId}) : super(password: '');

  @override
  Map<String, String> toData() => <String, String>{'user_id': userId};
}
