// Currency Exchange: Lab 07 mobile client (Lab 06 + registration, login,
// account view, admin view, and the signed-in view while offline).
//
// Run against the service (see mobile/README.md):
//   flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000   (Android emulator)
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'api/api_client.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';

/// Where the web service is. 10.0.2.2 is the host computer seen from the
/// Android emulator. Use https://... for a deployed service.
const String defaultBaseUrl = String.fromEnvironment('API_BASE_URL',
    defaultValue: kIsWeb ? 'http://127.0.0.1:8000' : 'http://10.0.2.2:8000');

void main() {
  runApp(CurrencyApp(api: ApiClient(baseUrl: defaultBaseUrl)));
}

class CurrencyApp extends StatefulWidget {
  const CurrencyApp({super.key, required this.api});
  final ApiClient api;

  @override
  State<CurrencyApp> createState() => _CurrencyAppState();
}

class _CurrencyAppState extends State<CurrencyApp> {
  final _nav = GlobalKey<NavigatorState>();
  bool _wasSignedIn = false;

  @override
  void initState() {
    super.initState();
    widget.api.session.addListener(_onSession);
  }

  @override
  void dispose() {
    widget.api.session.removeListener(_onSession);
    super.dispose();
  }

  // When the service ends the session, close any open screen (an order form,
  // for example) and show the login screen with the reason.
  void _onSession() {
    final signedIn = widget.api.session.signedIn;
    if (signedIn != _wasSignedIn) {
      _wasSignedIn = signedIn;
      _nav.currentState?.popUntil((r) => r.isFirst);
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        navigatorKey: _nav,
        title: 'Currency Exchange',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
        home: widget.api.session.signedIn
            ? HomeScreen(key: ValueKey(widget.api.session.user!.id), api: widget.api)
            : LoginScreen(api: widget.api),
      );
}
