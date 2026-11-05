import 'package:flutter/material.dart';
import 'package:matomo_tracker/matomo_tracker.dart';
import 'package:provider/provider.dart';
import 'package:smooth_app/data_models/login_result.dart';
import 'package:smooth_app/data_models/preferences/user_preferences.dart';
import 'package:smooth_app/data_models/user_management_provider.dart';
import 'package:smooth_app/generic_lib/design_constants.dart';
import 'package:smooth_app/generic_lib/widgets/smooth_card.dart';
import 'package:smooth_app/helpers/analytics_helper.dart';
import 'package:smooth_app/l10n/app_localizations.dart';
import 'package:smooth_app/widgets/smooth_app_bar.dart';
import 'package:smooth_app/widgets/smooth_scaffold.dart';

/// Registration screen. The form itself is the Keycloak registration page.
class SignUpPage extends StatefulWidget {
  const SignUpPage();

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> with TraceableClientMixin {
  bool _runningQuery = false;
  LoginResult? _result;

  Future<void> _register() async {
    setState(() {
      _runningQuery = true;
      _result = null;
    });
    final LoginResult result = await context
        .read<UserManagementProvider>()
        .signIn(context.read<UserPreferences>(), register: true);
    if (!mounted) {
      return;
    }
    setState(() {
      _runningQuery = false;
      _result = result.type == LoginResultType.cancelled ? null : result;
    });
    if (result.type != LoginResultType.successful) {
      return;
    }
    AnalyticsHelper.trackEvent(AnalyticsEvent.registerAction);
    Navigator.of(context).pop<bool>(true);
  }

  @override
  String get actionName => 'Opened sign_up_page';

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppLocalizations appLocalizations = AppLocalizations.of(context);
    final Size size = MediaQuery.sizeOf(context);

    return SmoothScaffold(
      appBar: SmoothAppBar(title: Text(appLocalizations.sign_up_page_title)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsetsDirectional.all(LARGE_SPACE),
          child: Column(
            children: <Widget>[
              Text(
                appLocalizations.sign_in_text,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: LARGE_SPACE),
              if (_result != null &&
                  _result!.type != LoginResultType.successful)
                Padding(
                  padding: const EdgeInsets.only(bottom: LARGE_SPACE),
                  child: SmoothCard(
                    padding: const EdgeInsets.all(BALANCED_SPACE),
                    color: const Color(0xFFEB0004),
                    child: Text(
                      _result!.getErrorMessage(appLocalizations),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF000000),
                      ),
                    ),
                  ),
                ),
              if (_runningQuery)
                const CircularProgressIndicator.adaptive()
              else
                ElevatedButton(
                  onPressed: _register,
                  style: ButtonStyle(
                    minimumSize: WidgetStateProperty.all<Size>(
                      Size(size.width * 0.7, theme.buttonTheme.height + 10),
                    ),
                  ),
                  child: Text(appLocalizations.sign_up_page_action_button),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
