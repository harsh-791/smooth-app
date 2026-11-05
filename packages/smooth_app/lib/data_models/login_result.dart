import 'package:openfoodfacts/openfoodfacts.dart';
import 'package:smooth_app/l10n/app_localizations.dart';

/// How did the login attempt work?
enum LoginResultType {
  successful,
  unsuccessful,
  serverIssue,
  exception,

  /// The user closed the Keycloak browser. Not an error.
  cancelled,
}

/// Result of a log in attempt, more subtle than a `bool`.
class LoginResult {
  const LoginResult(this.type, {this.user, this.text});

  final LoginResultType type;
  final User? user;
  final String? text;

  String getErrorMessage(final AppLocalizations appLocalizations) =>
      switch (type) {
        LoginResultType.successful => 'not supposed to happen',
        LoginResultType.unsuccessful => appLocalizations.incorrect_credentials,
        LoginResultType.serverIssue =>
          appLocalizations.login_result_type_server_issue,
        LoginResultType.exception =>
          isNoNetworkException(text!)
              ? appLocalizations.login_result_type_server_unreachable
              : text!,
        LoginResultType.cancelled => '',
      };

  static bool isNoNetworkException(final String text) =>
      text == 'Network is unreachable' ||
      text.startsWith('Failed host lookup: ');
}
