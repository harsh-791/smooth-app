import 'dart:convert';

import 'package:smooth_app/auth/keycloak_config.dart';

/// Whether this request body is an authenticated call for [userId].
///
/// The Open Food Facts Dart client still puts `user_id` in write bodies. That
/// field is how we recognise a call that used to send the password, without
/// attaching the bearer token to anonymous reads.
bool bodyCarriesUserId(List<int> body, String? contentType, String userId) {
  if (body.isEmpty || userId.isEmpty) {
    return false;
  }
  final String type = (contentType ?? '').toLowerCase();
  if (type.contains('application/json')) {
    return _jsonCarriesUserId(body, userId);
  }
  if (type.contains('multipart/form-data')) {
    return _multipartCarriesUserId(body, userId);
  }
  if (type.contains('application/x-www-form-urlencoded') || type.isEmpty) {
    return _formCarriesUserId(body, userId);
  }
  return false;
}

/// `true` when [header] is HTTP Basic for [userId].
///
/// Robotoff still sends `Authorization: Basic <user>:<password>`. A signed-in
/// user has an empty password there, so that header is replaced with the
/// bearer token. The anonymous `smoothie-app` account is left alone.
bool authorizationIsBasicForUser(String? header, String userId) {
  if (header == null || userId.isEmpty) {
    return false;
  }
  const String prefix = 'basic ';
  if (!header.toLowerCase().startsWith(prefix)) {
    return false;
  }
  try {
    final String decoded = utf8.decode(
      base64.decode(header.substring(prefix.length).trim()),
    );
    final int separator = decoded.indexOf(':');
    if (separator < 0) {
      return false;
    }
    return decoded.substring(0, separator) == userId;
  } on FormatException {
    return false;
  }
}

/// Whether this call is one the signed-in user used to authenticate.
bool requestUsesSignedInSession({
  required Uri uri,
  required String? contentType,
  required List<int> body,
  required String userId,
  String? authorizationHeader,
}) {
  if (userId.isEmpty ||
      KeycloakConfig.isKeycloakHost(uri) ||
      !KeycloakConfig.isOffApiHost(uri)) {
    return false;
  }
  return authorizationIsBasicForUser(authorizationHeader, userId) ||
      bodyCarriesUserId(body, contentType, userId);
}

/// Bearer header for a request, or null when this call stays anonymous.
///
/// [accessToken] is the current Keycloak access token. Callers refresh it
/// before calling this when the token is close to expiry. [authorizationHeader]
/// is the header the caller already set, so a Basic header for this user can
/// be replaced.
String? bearerAuthorizationHeader({
  required Uri uri,
  required String? contentType,
  required List<int> body,
  required String? userId,
  required String? accessToken,
  String? authorizationHeader,
}) {
  if (userId == null ||
      accessToken == null ||
      accessToken.isEmpty ||
      !requestUsesSignedInSession(
        uri: uri,
        contentType: contentType,
        body: body,
        userId: userId,
        authorizationHeader: authorizationHeader,
      )) {
    return null;
  }
  return 'Bearer $accessToken';
}

bool _formCarriesUserId(List<int> body, String userId) {
  try {
    final Map<String, String> fields = Uri.splitQueryString(
      utf8.decode(body, allowMalformed: true),
    );
    return fields['user_id'] == userId;
  } on FormatException {
    return false;
  }
}

bool _jsonCarriesUserId(List<int> body, String userId) {
  try {
    final Object? decoded = jsonDecode(utf8.decode(body, allowMalformed: true));
    return decoded is Map && decoded['user_id'] == userId;
  } on FormatException {
    return false;
  }
}

bool _multipartCarriesUserId(List<int> body, String userId) {
  // Multipart bodies contain the image bytes. Latin-1 keeps those bytes
  // addressable without throwing on non-UTF8 sequences.
  final String raw = latin1.decode(body);
  for (final String marker in <String>['name="user_id"', "name='user_id'"]) {
    final int nameAt = raw.indexOf(marker);
    if (nameAt < 0) {
      continue;
    }
    final int separator = raw.indexOf('\r\n\r\n', nameAt);
    if (separator < 0) {
      continue;
    }
    final int valueStart = separator + 4;
    final int valueEnd = raw.indexOf('\r\n', valueStart);
    final String value = valueEnd < 0
        ? raw.substring(valueStart)
        : raw.substring(valueStart, valueEnd);
    if (value == userId) {
      return true;
    }
  }
  return false;
}
