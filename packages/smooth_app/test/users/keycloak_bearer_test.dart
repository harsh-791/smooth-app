import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:smooth_app/auth/bearer_request.dart';
import 'package:smooth_app/auth/keycloak_config.dart';
import 'package:smooth_app/auth/keycloak_session.dart';
import 'package:smooth_app/auth/keycloak_tokens.dart';
import 'package:smooth_app/auth/off_user.dart';

/// Token attach and refresh. The in-app browser itself is not exercised here.
///
/// Manual check, once `org.openfoodfacts.scanner://oauthredirect` and
/// `org.openfoodfacts.scanner://logout` are allowed on the `smooth-app`
/// Keycloak client:
/// 1. Sign in. Device Activity shows one session.
/// 2. Edit a product. The write sends `Authorization: Bearer` and no password.
/// 3. Device Activity still shows that same session.
/// 4. Sign out. The app and that Keycloak session are both gone.
void main() {
  test('access token is sent only for the signed-in user write', () {
    const String userId = 'alice';
    final List<int> body = utf8.encode('user_id=alice&lc=en');
    expect(
      bearerAuthorizationHeader(
        uri: Uri.https('world.openfoodfacts.org', '/cgi/product_jqm2.pl'),
        contentType: 'application/x-www-form-urlencoded',
        body: body,
        userId: userId,
        accessToken: 'access-1',
      ),
      'Bearer access-1',
    );
    expect(
      bearerAuthorizationHeader(
        uri: KeycloakConfig.tokenEndpoint(production: true),
        contentType: 'application/x-www-form-urlencoded',
        body: utf8.encode('grant_type=refresh_token&refresh_token=abc'),
        userId: userId,
        accessToken: 'access-1',
      ),
      isNull,
    );
    expect(
      bearerAuthorizationHeader(
        uri: Uri.https('world.openfoodfacts.org', '/api/v2/search'),
        contentType: null,
        body: utf8.encode(''),
        userId: userId,
        accessToken: 'access-1',
      ),
      isNull,
    );
    expect(
      bearerAuthorizationHeader(
        uri: Uri.https('notopenfoodfacts.org', '/cgi/product_jqm2.pl'),
        contentType: 'application/x-www-form-urlencoded',
        body: body,
        userId: userId,
        accessToken: 'access-1',
      ),
      isNull,
    );
  });

  test('json and multipart writes are recognised', () {
    expect(
      bodyCarriesUserId(
        utf8.encode('{"user_id":"alice","product":{}}'),
        'application/json',
        'alice',
      ),
      isTrue,
    );
    const String multipart =
        '--b\r\nContent-Disposition: form-data; name="user_id"\r\n\r\nalice\r\n'
        '--b\r\nContent-Disposition: form-data; name="imgupload_front"\r\n\r\n'
        'bytes\r\n--b--\r\n';
    expect(
      bodyCarriesUserId(
        latin1.encode(multipart),
        'multipart/form-data',
        'alice',
      ),
      isTrue,
    );
    expect(
      bodyCarriesUserId(
        latin1.encode(multipart),
        'multipart/form-data',
        'someone-else',
      ),
      isFalse,
    );
  });

  test('Robotoff basic auth for the signed-in user becomes a bearer token', () {
    final String basic = 'Basic ${base64Encode(utf8.encode('alice:'))}';
    expect(
      bearerAuthorizationHeader(
        uri: Uri.https('robotoff.openfoodfacts.org', '/api/v1/questions'),
        contentType: null,
        body: utf8.encode(''),
        userId: 'alice',
        accessToken: 'access-1',
        authorizationHeader: basic,
      ),
      'Bearer access-1',
    );
    expect(
      bearerAuthorizationHeader(
        uri: Uri.https('robotoff.openfoodfacts.org', '/api/v1/questions'),
        contentType: null,
        body: utf8.encode(''),
        userId: 'alice',
        accessToken: 'access-1',
        authorizationHeader:
            'Basic ${base64Encode(utf8.encode('smoothie-app:strawberrybanana'))}',
      ),
      isNull,
    );
  });

  test('end-session posts the refresh token for this public client', () async {
    late Map<String, String> sent;
    await logoutKeycloakSession(
      refreshToken: 'refresh-1',
      production: true,
      post: (Uri uri, Map<String, String> fields) async {
        expect(uri, KeycloakConfig.endSessionEndpoint(production: true));
        sent = fields;
        return http.Response('', 204);
      },
    );
    expect(sent, keycloakLogoutFields('refresh-1'));
    await expectLater(
      logoutKeycloakSession(
        refreshToken: 'refresh-1',
        production: true,
        post: (Uri uri, Map<String, String> fields) async =>
            http.Response('no', 400),
      ),
      throwsA(isA<KeycloakAuthException>()),
    );
  });

  test('OffUser does not put a password in the API body', () {
    const OffUser user = OffUser(userId: 'alice');
    expect(user.toData(), <String, String>{'user_id': 'alice'});
    expect(user.toJson()['password'], '');
  });

  test('expired access token is refreshed once for parallel callers', () async {
    final _MemoryStore store = _MemoryStore();
    int calls = 0;
    final DateTime now = DateTime.utc(2026, 1, 1);
    final KeycloakSession session = KeycloakSession(
      store: store,
      now: () => now,
      refresher:
          ({required String refreshToken, required bool production}) async {
            calls += 1;
            await Future<void>.delayed(const Duration(milliseconds: 20));
            return KeycloakTokenSet(
              accessToken: _jwt(<String, Object?>{
                'exp': now.millisecondsSinceEpoch ~/ 1000 + 3600,
                'preferred_username': 'alice',
              }),
              refreshToken: 'rotated',
              idToken: null,
              accessTokenExpiry: now.add(const Duration(hours: 1)),
            );
          },
    );
    await session.save(
      KeycloakTokenSet(
        accessToken: _jwt(<String, Object?>{
          'exp': 0,
          'preferred_username': 'alice',
        }),
        refreshToken: 'old',
        idToken: null,
        accessTokenExpiry: DateTime.utc(2000),
      ),
    );

    await Future.wait<void>(<Future<void>>[
      session.ensureFresh(),
      session.ensureFresh(),
    ]);

    expect(calls, 1);
    expect(session.current?.refreshToken, 'rotated');
    expect(session.userId, 'alice');
    expect(session.accessTokenNeedsRefresh, isFalse);
  });

  test('a rejected refresh token clears the session', () async {
    final KeycloakSession session = KeycloakSession(
      store: _MemoryStore(),
      now: () => DateTime.utc(2026, 1, 1),
      refresher:
          ({required String refreshToken, required bool production}) async {
            throw const KeycloakAuthException(
              'Token is not active',
              invalidGrant: true,
            );
          },
    );
    await session.save(
      KeycloakTokenSet(
        accessToken: _jwt(<String, Object?>{
          'exp': 0,
          'preferred_username': 'alice',
        }),
        refreshToken: 'old',
        idToken: null,
        accessTokenExpiry: DateTime.utc(2000),
      ),
    );

    await expectLater(
      session.ensureFresh(),
      throwsA(
        isA<KeycloakAuthException>().having(
          (KeycloakAuthException error) => error.invalidGrant,
          'invalidGrant',
          isTrue,
        ),
      ),
    );
    expect(session.current, isNull);
  });

  test('token error responses keep the invalid_grant flag', () {
    expect(
      () => tokenSetFromResponse(
        http.Response(
          '{"error":"invalid_grant","error_description":"Token is not active"}',
          400,
        ),
      ),
      throwsA(
        isA<KeycloakAuthException>().having(
          (KeycloakAuthException error) => error.invalidGrant,
          'invalidGrant',
          isTrue,
        ),
      ),
    );
  });
}

String _jwt(Map<String, Object?> payload) {
  String encode(Object value) {
    return base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  }

  return '${encode(<String, String>{'alg': 'none'})}.${encode(payload)}.sig';
}

class _MemoryStore implements KeycloakTokenStore {
  KeycloakTokenSet? tokens;

  @override
  Future<void> clear() async => tokens = null;

  @override
  Future<KeycloakTokenSet?> read() async => tokens;

  @override
  Future<void> write(KeycloakTokenSet tokens) async => this.tokens = tokens;
}
