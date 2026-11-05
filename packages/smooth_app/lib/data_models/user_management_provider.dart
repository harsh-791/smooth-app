import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:openfoodfacts/openfoodfacts.dart';
import 'package:smooth_app/auth/bearer_http_client.dart';
import 'package:smooth_app/auth/keycloak_browser.dart';
import 'package:smooth_app/auth/keycloak_session.dart';
import 'package:smooth_app/auth/keycloak_tokens.dart';
import 'package:smooth_app/auth/off_user.dart';
import 'package:smooth_app/data_models/login_result.dart';
import 'package:smooth_app/data_models/preferences/user_preferences.dart';
import 'package:smooth_app/database/dao_secured_string.dart';
import 'package:smooth_app/pages/preferences/user_preferences_dev_mode.dart';
import 'package:smooth_app/query/product_query.dart';
import 'package:smooth_app/services/smooth_services.dart';

class UserManagementProvider with ChangeNotifier {
  UserManagementProvider({KeycloakBrowser? browser, KeycloakSession? session})
    : _browser = browser ?? KeycloakBrowser(),
      _session = session ?? KeycloakSession.instance;

  /// Legacy secure-storage keys. The password key is misspelled on purpose:
  /// that is the key already in the wild.
  static const String _legacyUserId = 'user_id';
  static const String _legacyPassword = 'pasword';
  static const String _legacyCookie = 'user_cookie';

  final KeycloakBrowser _browser;
  final KeycloakSession _session;

  /// Opens Keycloak. [register] uses the registration endpoint.
  ///
  /// A cancelled browser is [LoginResultType.cancelled], not an error.
  Future<LoginResult> signIn(
    UserPreferences preferences, {
    bool register = false,
  }) async {
    final bool production = _production(preferences);
    _session.production = production;
    try {
      final KeycloakTokenSet? tokens = await _browser.authenticate(
        production: production,
        register: register,
        languageCode: _languageCode(),
      );
      if (tokens == null) {
        return const LoginResult(LoginResultType.cancelled);
      }
      final String? userId = tokens.userId;
      if (userId == null) {
        return const LoginResult(
          LoginResultType.exception,
          text: 'Signed in, but the account has no username.',
        );
      }
      await _session.save(tokens);
      await _forgetLegacyPassword();
      OpenFoodAPIConfiguration.globalUser = OffUser(userId: userId);
      notifyListeners();
      return LoginResult(
        LoginResultType.successful,
        user: OffUser(userId: userId),
      );
    } on KeycloakAuthException catch (error) {
      return LoginResult(LoginResultType.exception, text: error.message);
    } on Object catch (error) {
      return LoginResult(LoginResultType.exception, text: error.toString());
    }
  }

  /// Clears the local session and ends the Keycloak session.
  ///
  /// Local tokens are removed even when the browser step is dismissed, so the
  /// app stops sending the access token. The Keycloak session is what Device
  /// Activity drops when the end-session page completes.
  Future<bool> logout() async {
    final String? idToken = _session.current?.idToken;
    final String? refreshToken = _session.current?.refreshToken;
    final bool production = _session.production;
    if (refreshToken != null && refreshToken.isNotEmpty) {
      try {
        await logoutKeycloakSession(
          refreshToken: refreshToken,
          production: production,
        );
      } on KeycloakAuthException catch (error) {
        Logs.w('Keycloak end-session failed', ex: error);
      } on Object catch (error) {
        Logs.w('Keycloak end-session failed', ex: error);
      }
    }
    try {
      await _browser.endSession(production: production, idToken: idToken);
    } on KeycloakAuthException catch (error) {
      Logs.w('Keycloak end-session failed', ex: error);
    } on PlatformException catch (error) {
      Logs.w('Keycloak end-session failed', ex: error);
    }
    OpenFoodAPIConfiguration.globalUser = null;
    await _session.clear();
    await _forgetLegacyPassword();
    notifyListeners();
    return !await _sessionHasTokens();
  }

  /// Restores a previous Keycloak session. Passwords saved by older versions
  /// are deleted: they cannot be exchanged for a token without another login.
  static Future<void> mountCredentials() async {
    BearerHttpOverrides.install();
    final KeycloakSession session = KeycloakSession.instance;
    try {
      await session.restore();
    } on PlatformException {
      await session.clear();
      Logs.e('Credentials query failed, you have been logged out');
    }
    await _forgetLegacyPassword();
    final String? userId = session.userId;
    if (userId == null) {
      OpenFoodAPIConfiguration.globalUser = null;
      return;
    }
    OpenFoodAPIConfiguration.globalUser = OffUser(userId: userId);
  }

  /// Refreshes the access token. An rejected refresh token signs the user out.
  Future<void> checkUserLoginValidity(UserPreferences preferences) async {
    if (!ProductQuery.isLoggedIn()) {
      return;
    }
    _session.production = _production(preferences);
    try {
      await _session.ensureFresh();
    } on KeycloakAuthException catch (error) {
      // The refresh token was revoked. Don't open the end-session browser
      // during startup; there is no Keycloak session left to close.
      if (error.invalidGrant) {
        OpenFoodAPIConfiguration.globalUser = null;
        await _session.clear();
        await _forgetLegacyPassword();
        notifyListeners();
      }
    } on Object catch (error) {
      // Offline, or Keycloak is down. Keep the stored session.
      Logs.w('Could not refresh the access token', ex: error);
    }
    if (_session.current == null) {
      OpenFoodAPIConfiguration.globalUser = null;
    }
  }

  /// Whether a Keycloak session is stored on this device.
  Future<bool> credentialsInStorage() async => _session.current != null;

  Future<bool> _sessionHasTokens() => credentialsInStorage();

  static bool _production(UserPreferences preferences) =>
      preferences.getFlag(UserPreferencesDevMode.userPreferencesFlagProd) ??
      true;

  static String? _languageCode() {
    final String tag = ProductQuery.getLanguage().offTag;
    if (tag.length == 2) {
      return tag;
    }
    return null;
  }

  static Future<void> _forgetLegacyPassword() async {
    await DaoSecuredString.remove(key: _legacyUserId);
    await DaoSecuredString.remove(key: _legacyPassword);
    await DaoSecuredString.remove(key: _legacyCookie);
  }
}
