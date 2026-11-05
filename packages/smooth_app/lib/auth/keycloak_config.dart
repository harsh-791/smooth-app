/// Keycloak settings for the Smooth app.
///
/// `smooth-app` is the existing public client on the production and staging
/// realms. It has no client secret. The authorization endpoint currently
/// rejects [redirectUri]; that URI has to be allowed on the client before
/// login can return to the app.
class KeycloakConfig {
  const KeycloakConfig._();

  static const String clientId = 'smooth-app';
  static const String realm = 'openfoodfacts';

  /// Custom scheme shared by the Android application id and the iOS bundle id.
  /// Lower case, which AppAuth requires.
  static const String redirectScheme = 'org.openfoodfacts.scanner';
  static const String redirectUri = '$redirectScheme://oauthredirect';
  static const String logoutRedirectUri = '$redirectScheme://logout';

  /// Same scopes as Open Food Facts Explorer. `offline_access` is what makes
  /// Keycloak return a refresh token for this public client.
  static const List<String> scopes = <String>[
    'openid',
    'profile',
    'offline_access',
  ];

  static Uri issuer({required bool production}) {
    final String host = production
        ? 'auth.openfoodfacts.org'
        : 'auth.openfoodfacts.net';
    return Uri.https(host, '/realms/$realm');
  }

  static Uri discoveryUri({required bool production}) => issuer(
    production: production,
  ).replace(path: '/realms/$realm/.well-known/openid-configuration');

  static Uri authorizationEndpoint({required bool production}) => issuer(
    production: production,
  ).replace(path: '/realms/$realm/protocol/openid-connect/auth');

  static Uri registrationEndpoint({required bool production}) => issuer(
    production: production,
  ).replace(path: '/realms/$realm/protocol/openid-connect/registrations');

  static Uri tokenEndpoint({required bool production}) => issuer(
    production: production,
  ).replace(path: '/realms/$realm/protocol/openid-connect/token');

  static Uri endSessionEndpoint({required bool production}) => issuer(
    production: production,
  ).replace(path: '/realms/$realm/protocol/openid-connect/logout');

  static Uri accountUri({required bool production}) =>
      issuer(production: production).replace(path: '/realms/$realm/account');

  /// Keycloak account-console route for deleting the signed-in account.
  static Uri deleteAccountUri({required bool production}) {
    final Uri account = accountUri(production: production);
    return account.replace(
      path: '${account.path}/',
      fragment: '/delete-account',
    );
  }

  static bool isKeycloakHost(Uri uri) {
    final String host = uri.host;
    return host == 'auth.openfoodfacts.org' || host == 'auth.openfoodfacts.net';
  }

  /// Product Opener, Prices, Robotoff, Folksonomy and the other OFF APIs.
  static bool isOffApiHost(Uri uri) {
    final String host = uri.host;
    return _isHost(host, 'openfoodfacts.org') ||
        _isHost(host, 'openfoodfacts.net') ||
        _isHost(host, 'openbeautyfacts.org') ||
        _isHost(host, 'openbeautyfacts.net') ||
        _isHost(host, 'openpetfoodfacts.org') ||
        _isHost(host, 'openpetfoodfacts.net') ||
        _isHost(host, 'openproductsfacts.org') ||
        _isHost(host, 'openproductsfacts.net');
  }

  static bool _isHost(String host, String domain) =>
      host == domain || host.endsWith('.$domain');
}
