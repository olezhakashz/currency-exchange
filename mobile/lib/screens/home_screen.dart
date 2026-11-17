import 'package:flutter/material.dart';

import '../api/api_client.dart';
import 'rates_screen.dart';
import 'wallet_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.api});
  final ApiClient api;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  // A new key makes the wallet load again each time its tab is opened.
  Key _walletKey = UniqueKey();

  @override
  Widget build(BuildContext context) => Scaffold(
        body: _tab == 0
            ? RatesScreen(api: widget.api)
            : WalletScreen(key: _walletKey, api: widget.api),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() {
            _tab = i;
            if (i == 1) _walletKey = UniqueKey();
          }),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.currency_exchange), label: 'Rates'),
            NavigationDestination(
                icon: Icon(Icons.account_balance_wallet_outlined), label: 'Wallet'),
          ],
        ),
      );
}
