import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:smooth_app/auth/keycloak_config.dart';
import 'package:smooth_app/auth/keycloak_tokens.dart';
import 'package:smooth_app/database/dao_secured_string.dart';

const Duration _refreshSkew = Duration(seconds: 60);

/// Where the access, refresh and id tokens are kept.
abstract class KeycloakTokenStore {
  Future<KeycloakTokenSet?> read();

  Future<void> write(KeycloakTokenSet tokens);

  Future<void> clear();
}

class SecureKeycloakTokenStore implements KeycloakTokenStore {
  const SecureKeycloakTokenStore();

  static const String _access = 'kc_access_token';
  static const String _refresh = 'kc_refresh_token';
  static const String _id = 'kc_id_token';
  static const String _expiry = 'kc_access_expiry';

  @override
  Future<KeycloakTokenSet?> read() async {
    final String? access = await DaoSecuredString.get(_access);
    final String? refresh = await DaoSecuredString.get(_refresh);
    if (access == null || refresh == null) {
      return null;
    }
    final String? expiryRaw = await DaoSecuredString.get(_expiry);
    final int? expiryMs = expiryRaw == null ? null : int.tryParse(expiryRaw);
    return KeycloakTokenSet(
      accessToken: access,
      refreshToken: refresh,
      idToken: await DaoSecuredString.get(_id),
      accessTokenExpiry: expiryMs == null
          ? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)
          : DateTime.fromMillisecondsSinceEpoch(expiryMs, isUtc: true),
    );
  }

  @override
  Future<void> write(KeycloakTokenSet tokens) async {
    await DaoSecuredString.put(key: _access, value: tokens.accessToken);
    await DaoSecuredString.put(key: _refresh, value: tokens.refreshToken);
    await DaoSecuredString.put(
      key: _expiry,
      value: '${tokens.accessTokenExpiry.toUtc().millisecondsSinceEpoch}',
    );
    if (tokens.idToken == null) {
      await DaoSecuredString.remove(key: _id);
    } else {
      await DaoSecuredString.put(key: _id, value: tokens.idToken!);
    }
  }

  @override
  Future<void> clear() async {
    await DaoSecuredString.remove(key: _access);
    await DaoSecuredString.remove(key: _refresh);
    await DaoSecuredString.remove(key: _id);
    await DaoSecuredString.remove(key: _expiry);
  }
}

class KeycloakAuthException implements Exception {
  const KeycloakAuthException(this.message, {this.invalidGrant = false});

  final String message;

  /// The refresh token was rejected. The local session has to be dropped.
  final bool invalidGrant;

  @override
  String toString() => message;
}

typedef KeycloakRefresher =
    Future<KeycloakTokenSet> Function({
      required String refreshToken,
      required bool production,
    });

/// One Keycloak session for the whole app.
///
/// Refresh is single-flight: parallel API calls wait on the same token request
/// instead of opening another Device Activity session.
class KeycloakSession {
  KeycloakSession({
    KeycloakTokenStore? store,
    KeycloakRefresher? refresher,
    DateTime Function()? now,
    this.production = true,
  }) : _store = store ?? const SecureKeycloakTokenStore(),
       _refresher = refresher ?? refreshKeycloakTokens,
       _now = now ?? DateTime.now;

  static final KeycloakSession instance = KeycloakSession();

  final KeycloakTokenStore _store;
  final KeycloakRefresher _refresher;
  final DateTime Function() _now;

  /// Realm the stored tokens were issued by. Updated when the user signs in.
  bool production;

  KeycloakTokenSet? current;

  String? get userId => current?.userId;

  Future<void>? _refreshing;

  Future<void> restore() async {
    current = await _store.read();
  }

  Future<void> save(KeycloakTokenSet tokens) async {
    current = tokens;
    await _store.write(tokens);
  }

  Future<void> clear() async {
    current = null;
    _refreshing = null;
    await _store.clear();
  }

  bool get accessTokenNeedsRefresh {
    final KeycloakTokenSet? tokens = current;
    if (tokens == null) {
      return false;
    }
    return jwtExpiresWithin(tokens.accessToken, _refreshSkew, now: _now);
  }

  /// Returns a usable access token, refreshing it first when it is due.
  Future<String?> freshAccessToken() async {
    await ensureFresh();
    return current?.accessToken;
  }

  Future<void> ensureFresh() {
    if (!accessTokenNeedsRefresh) {
      return Future<void>.value();
    }
    final Future<void> inFlight = _refreshing ??= _refresh().whenComplete(() {
      _refreshing = null;
    });
    return inFlight;
  }

  Future<void> _refresh() async {
    final KeycloakTokenSet? tokens = current;
    if (tokens == null) {
      return;
    }
    try {
      final KeycloakTokenSet refreshed = await _refresher(
        refreshToken: tokens.refreshToken,
        production: production,
      );
      await save(refreshed);
    } on KeycloakAuthException catch (error) {
      if (error.invalidGrant) {
        await clear();
      }
      rethrow;
    }
  }
}

/// Drops the Keycloak session that [refreshToken] belongs to.
///
/// This is the back-channel call on the end-session endpoint. It does not
/// need the post-logout redirect, so Device Activity loses this session even
/// when the in-app browser step is dismissed.
Future<void> logoutKeycloakSession({
  required String refreshToken,
  required bool production,
  Future<http.Response> Function(Uri uri, Map<String, String> fields)? post,
}) async {
  final Future<http.Response> Function(Uri uri, Map<String, String> fields)
  send = post ?? _postForm;
  final http.Response response = await send(
    KeycloakConfig.endSessionEndpoint(production: production),
    keycloakLogoutFields(refreshToken),
  );
  if (response.statusCode != 200 && response.statusCode != 204) {
    throw KeycloakAuthException('Sign-out failed (${response.statusCode})');
  }
}

Map<String, String> keycloakLogoutFields(String refreshToken) =>
    <String, String>{
      'client_id': KeycloakConfig.clientId,
      'refresh_token': refreshToken,
    };

Future<http.Response> _postForm(Uri uri, Map<String, String> fields) {
  return http.post(
    uri,
    headers: <String, String>{
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: fields,
  );
}

Future<KeycloakTokenSet> refreshKeycloakTokens({
  required String refreshToken,
  required bool production,
}) async {
  final http.Response response = await http.post(
    KeycloakConfig.tokenEndpoint(production: production),
    headers: <String, String>{
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: <String, String>{
      'grant_type': 'refresh_token',
      'client_id': KeycloakConfig.clientId,
      'refresh_token': refreshToken,
    },
  );
  return tokenSetFromResponse(response);
}

KeycloakTokenSet tokenSetFromResponse(http.Response response) {
  Map<String, dynamic>? json;
  try {
    final Object? decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) {
      json = decoded;
    } else if (decoded is Map) {
      json = decoded.map(
        (dynamic key, dynamic value) =>
            MapEntry<String, dynamic>('$key', value),
      );
    }
  } on FormatException {
    json = null;
  }
  if (response.statusCode != 200 || json == null) {
    final Object? error = json?['error'];
    final Object? description = json?['error_description'];
    throw KeycloakAuthException(
      description?.toString() ?? error?.toString() ?? 'Token refresh failed',
      invalidGrant: error == 'invalid_grant',
    );
  }
  final Object? access = json['access_token'];
  final Object? refresh = json['refresh_token'];
  if (access is! String || refresh is! String) {
    throw const KeycloakAuthException('Token response was missing tokens');
  }
  final Object? expiresIn = json['expires_in'];
  final int seconds = expiresIn is int ? expiresIn : 60;
  final Object? idToken = json['id_token'];
  return KeycloakTokenSet(
    accessToken: access,
    refreshToken: refresh,
    idToken: idToken is String ? idToken : null,
    accessTokenExpiry: DateTime.now().toUtc().add(Duration(seconds: seconds)),
  );
}
