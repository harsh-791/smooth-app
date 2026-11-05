import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:matomo_tracker/matomo_tracker.dart';
import 'package:provider/provider.dart';
import 'package:smooth_app/data_models/login_result.dart';
import 'package:smooth_app/data_models/preferences/user_preferences.dart';
import 'package:smooth_app/data_models/user_management_provider.dart';
import 'package:smooth_app/generic_lib/design_constants.dart';
import 'package:smooth_app/generic_lib/widgets/smooth_card.dart';
import 'package:smooth_app/helpers/analytics_helper.dart';
import 'package:smooth_app/helpers/app_helper.dart';
import 'package:smooth_app/l10n/app_localizations.dart';
import 'package:smooth_app/pages/user_management/sign_up_page.dart';
import 'package:smooth_app/resources/app_icons.dart' as icons;
import 'package:smooth_app/themes/smooth_theme_colors.dart';
import 'package:smooth_app/themes/theme_provider.dart';
import 'package:smooth_app/widgets/smooth_app_bar.dart';
import 'package:smooth_app/widgets/smooth_scaffold.dart';

/// Sign-in screen. Credentials are entered on the Keycloak page, not here.
class LoginPage extends StatefulWidget {
  const LoginPage();

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with TraceableClientMixin {
  bool _runningQuery = false;
  LoginResult? _loginResult;

  Future<void> _signIn() async {
    setState(() {
      _runningQuery = true;
      _loginResult = null;
    });
    final LoginResult result = await context
        .read<UserManagementProvider>()
        .signIn(context.read<UserPreferences>());
    if (!mounted) {
      return;
    }
    setState(() {
      _runningQuery = false;
      _loginResult = result.type == LoginResultType.cancelled ? null : result;
    });
    if (result.type != LoginResultType.successful) {
      return;
    }
    AnalyticsHelper.trackEvent(AnalyticsEvent.loginAction);
    Navigator.pop(context);
  }

  @override
  String get actionName => 'Opened login_page';

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppLocalizations appLocalizations = AppLocalizations.of(context);
    final Size size = MediaQuery.sizeOf(context);
    final SmoothColorsThemeExtension extension = context
        .extension<SmoothColorsThemeExtension>();
    final bool lightTheme = context.lightTheme();

    return SmoothScaffold(
      fixKeyboard: true,
      appBar: SmoothAppBar(title: Text(appLocalizations.sign_in)),
      body: SafeArea(
        child: Scrollbar(
          child: SingleChildScrollView(
            child: Container(
              alignment: Alignment.topCenter,
              width: double.infinity,
              padding: EdgeInsetsDirectional.only(
                top: LARGE_SPACE,
                start: size.width * 0.05,
                end: size.width * 0.05,
                bottom: MediaQuery.viewInsetsOf(context).bottom * 0.25,
              ),
              child: Column(
                children: <Widget>[
                  SvgPicture.asset(
                    'assets/preferences/login.svg',
                    height: MediaQuery.sizeOf(context).height * .15,
                    package: AppHelper.APP_PACKAGE,
                  ),
                  const SizedBox(height: SMALL_SPACE),
                  Padding(
                    padding: const EdgeInsetsDirectional.symmetric(
                      horizontal: SMALL_SPACE,
                      vertical: SMALL_SPACE,
                    ),
                    child: Text(
                      appLocalizations.sign_in_text,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.displayLarge?.copyWith(
                        fontSize: VERY_LARGE_SPACE,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: LARGE_SPACE),
                  SizedBox(
                    width: double.infinity,
                    child: Material(
                      color: lightTheme
                          ? extension.primaryLight
                          : extension.primaryUltraBlack,
                      borderRadius: HEADER_BORDER_RADIUS,
                      child: Padding(
                        padding: const EdgeInsetsDirectional.symmetric(
                          horizontal: LARGE_SPACE,
                          vertical: LARGE_SPACE,
                        ),
                        child: Column(
                          children: <Widget>[
                            if (_loginResult != null &&
                                _loginResult!.type !=
                                    LoginResultType.successful)
                              Padding(
                                padding: const EdgeInsets.only(
                                  bottom: BALANCED_SPACE + LARGE_SPACE * 2,
                                ),
                                child: SmoothCard(
                                  padding: const EdgeInsets.all(BALANCED_SPACE),
                                  color: const Color(0xFFEB0004),
                                  child: Text(
                                    _loginResult!.getErrorMessage(
                                      appLocalizations,
                                    ),
                                    style: theme.textTheme.bodyMedium
                                        ?.copyWith(
                                          fontSize: 18.0,
                                          color: const Color(0xFF000000),
                                        ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                            if (_runningQuery)
                              const CircularProgressIndicator.adaptive()
                            else
                              ElevatedButton(
                                onPressed: _signIn,
                                style: ButtonStyle(
                                  minimumSize: WidgetStateProperty.all<Size>(
                                    Size(
                                      size.width * 0.5,
                                      theme.buttonTheme.height + 10,
                                    ),
                                  ),
                                  shape:
                                      WidgetStateProperty.all<
                                        RoundedRectangleBorder
                                      >(
                                        const RoundedRectangleBorder(
                                          borderRadius: CIRCULAR_BORDER_RADIUS,
                                        ),
                                      ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  spacing: SMALL_SPACE,
                                  children: <Widget>[
                                    Text(
                                      appLocalizations.sign_in,
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            fontSize: 18.0,
                                            fontWeight: FontWeight.bold,
                                            color: theme.colorScheme.onPrimary,
                                          ),
                                    ),
                                    icons.CircledArrow.right(
                                      type: icons.CircledArrowType.normal,
                                      circleColor: lightTheme
                                          ? Colors.white
                                          : extension.primaryUltraBlack,
                                      color: lightTheme
                                          ? extension.primaryTone
                                          : Colors.white,
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: LARGE_SPACE * 4),
                  SizedBox(
                    height: size.height * 0.06,
                    child: OutlinedButton(
                      onPressed: _runningQuery
                          ? null
                          : () async {
                              final bool? registered =
                                  await Navigator.push<bool>(
                                    context,
                                    MaterialPageRoute<bool>(
                                      builder: (BuildContext context) =>
                                          const SignUpPage(),
                                    ),
                                  );
                              if (registered == true && context.mounted) {
                                Navigator.of(context).pop();
                              }
                            },
                      style: ButtonStyle(
                        side: WidgetStateProperty.all<BorderSide>(
                          BorderSide(
                            color: theme.colorScheme.primary,
                            width: 2.0,
                          ),
                        ),
                        minimumSize: WidgetStateProperty.all<Size>(
                          Size(size.width * 0.5, theme.buttonTheme.height),
                        ),
                        shape:
                            WidgetStateProperty.all<RoundedRectangleBorder>(
                              const RoundedRectangleBorder(
                                borderRadius: CIRCULAR_BORDER_RADIUS,
                              ),
                            ),
                      ),
                      child: Text(
                        appLocalizations.create_account,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontSize: VERY_LARGE_SPACE,
                          fontWeight: FontWeight.w500,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
