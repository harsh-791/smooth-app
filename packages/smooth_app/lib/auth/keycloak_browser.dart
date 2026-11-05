import 'package:flutter/services.dart';
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:smooth_app/auth/keycloak_config.dart';
import 'package:smooth_app/auth/keycloak_session.dart';
import 'package:smooth_app/auth/keycloak_tokens.dart';

/// Opens Keycloak in the system in-app browser (Custom Tabs / Safari session).
class KeycloakBrowser {
  KeycloakBrowser({FlutterAppAuth? appAuth})
    : _appAuth = appAuth ?? const FlutterAppAuth();

  final FlutterAppAuth _appAuth;

  /// Signs in, or registers when [register] is true.
  ///
  /// Returns null when the user closes the browser.
  Future<KeycloakTokenSet?> authenticate({
    required bool production,
    required bool register,
    String? languageCode,
  }) async {
    const List<String> scopes = KeycloakConfig.scopes;
    try {
      return await _authorize(
        production: production,
        register: register,
        scopes: scopes,
        languageCode: languageCode,
      );
    } on FlutterAppAuthUserCancelledException {
      return null;
    } on PlatformException catch (error) {
      if (_isCancelled(error)) {
        return null;
      }
      // Some clients cannot request offline_access. Retry once without it;
      // refresh then lasts only as long as the Keycloak SSO session.
      final String details = '${error.message} ${error.details}';
      if (details.contains('invalid_scope') &&
          scopes.contains('offline_access')) {
        return _authorize(
          production: production,
          register: register,
          scopes: scopes
              .where((String scope) => scope != 'offline_access')
              .toList(),
          languageCode: languageCode,
        );
      }
      throw KeycloakAuthException(error.message ?? 'Sign-in failed');
    }
  }

  Future<void> endSession({
    required bool production,
    required String? idToken,
  }) async {
    if (idToken == null || idToken.isEmpty) {
      return;
    }
    try {
      await _appAuth.endSession(
        EndSessionRequest(
          idTokenHint: idToken,
          postLogoutRedirectUrl: KeycloakConfig.logoutRedirectUri,
          discoveryUrl: KeycloakConfig.discoveryUri(
            production: production,
          ).toString(),
        ),
      );
    } on FlutterAppAuthUserCancelledException {
      return;
    } on PlatformException catch (error) {
      if (_isCancelled(error)) {
        return;
      }
      throw KeycloakAuthException(error.message ?? 'Sign-out failed');
    }
  }

  Future<KeycloakTokenSet> _authorize({
    required bool production,
    required bool register,
    required List<String> scopes,
    required String? languageCode,
  }) async {
    final AuthorizationServiceConfiguration configuration =
        AuthorizationServiceConfiguration(
          authorizationEndpoint:
              (register
                      ? KeycloakConfig.registrationEndpoint(
                          production: production,
                        )
                      : KeycloakConfig.authorizationEndpoint(
                          production: production,
                        ))
                  .toString(),
          tokenEndpoint: KeycloakConfig.tokenEndpoint(
            production: production,
          ).toString(),
          endSessionEndpoint: KeycloakConfig.endSessionEndpoint(
            production: production,
          ).toString(),
        );
    final AuthorizationTokenResponse result = await _appAuth
        .authorizeAndExchangeCode(
          AuthorizationTokenRequest(
            KeycloakConfig.clientId,
            KeycloakConfig.redirectUri,
            serviceConfiguration: configuration,
            scopes: scopes,
            additionalParameters: languageCode == null
                ? null
                : <String, String>{'ui_locales': languageCode},
            externalUserAgent: ExternalUserAgent.asWebAuthenticationSession,
          ),
        );
    final String? access = result.accessToken;
    final String? refresh = result.refreshToken;
    if (access == null || refresh == null) {
      throw const KeycloakAuthException(
        'Keycloak did not return an access token and a refresh token',
      );
    }
    return KeycloakTokenSet(
      accessToken: access,
      refreshToken: refresh,
      idToken: result.idToken,
      accessTokenExpiry:
          result.accessTokenExpirationDateTime?.toUtc() ??
          DateTime.now().toUtc().add(const Duration(minutes: 5)),
    );
  }

  bool _isCancelled(PlatformException error) {
    if (error is FlutterAppAuthUserCancelledException) {
      return true;
    }
    final String code = error.code.toLowerCase();
    return code.contains('cancel') || code.contains('canceled');
  }
}
