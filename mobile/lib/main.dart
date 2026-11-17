// Currency Exchange: Lab 06 mobile client.
//
// Run against the Lab 05 service (see mobile/README.md):
//   flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000   (Android emulator)
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'api/api_client.dart';
import 'screens/login_screen.dart';

/// Where the web service is. 10.0.2.2 is the host computer seen from the
/// Android emulator. Use https://... for a deployed service.
const String defaultBaseUrl = String.fromEnvironment('API_BASE_URL',
    defaultValue: kIsWeb ? 'http://127.0.0.1:8000' : 'http://10.0.2.2:8000');

void main() {
  runApp(CurrencyApp(api: ApiClient(baseUrl: defaultBaseUrl)));
}

class CurrencyApp extends StatelessWidget {
  const CurrencyApp({super.key, required this.api});
  final ApiClient api;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Currency Exchange',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
        home: LoginScreen(api: api),
      );
}
