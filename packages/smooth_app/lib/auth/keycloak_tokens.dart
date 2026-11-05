import 'dart:convert';

/// Tokens from one Keycloak session.
class KeycloakTokenSet {
  const KeycloakTokenSet({
    required this.accessToken,
    required this.refreshToken,
    required this.idToken,
    required this.accessTokenExpiry,
  });

  final String accessToken;
  final String refreshToken;
  final String? idToken;
  final DateTime accessTokenExpiry;

  /// Username Product Opener stores as `userid`.
  String? get userId {
    return usernameFromJwt(idToken) ?? usernameFromJwt(accessToken);
  }
}

/// Reads the Open Food Facts username from an access or id token.
String? usernameFromJwt(String? jwt) {
  final Map<String, dynamic>? payload = jwtPayload(jwt);
  if (payload == null) {
    return null;
  }
  for (final String claim in <String>['preferred_username', 'username']) {
    final Object? value = payload[claim];
    if (value is String && value.isNotEmpty) {
      return value;
    }
  }
  return null;
}

/// `true` when [jwt] expires within [skew].
///
/// A token we cannot decode is treated as expired so the caller refreshes it.
bool jwtExpiresWithin(String jwt, Duration skew, {DateTime Function()? now}) {
  final Map<String, dynamic>? payload = jwtPayload(jwt);
  final Object? exp = payload?['exp'];
  if (exp is! int) {
    return true;
  }
  final DateTime expiry = DateTime.fromMillisecondsSinceEpoch(
    exp * 1000,
    isUtc: true,
  );
  final DateTime clock = (now ?? DateTime.now).call().toUtc();
  return !clock.isBefore(expiry.subtract(skew));
}

Map<String, dynamic>? jwtPayload(String? jwt) {
  if (jwt == null || jwt.isEmpty) {
    return null;
  }
  final List<String> parts = jwt.split('.');
  if (parts.length < 2) {
    return null;
  }
  try {
    final String normalized = base64Url.normalize(parts[1]);
    final Object? decoded = jsonDecode(
      utf8.decode(base64Url.decode(normalized)),
    );
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return decoded.map(
        (dynamic key, dynamic value) =>
            MapEntry<String, dynamic>('$key', value),
      );
    }
  } on FormatException {
    return null;
  }
  return null;
}
