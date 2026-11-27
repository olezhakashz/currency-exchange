import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../widgets/status_views.dart';
import 'account_screen.dart';
import 'admin_screen.dart';
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
  // A new key makes a tab load again each time it is opened.
  Key _tabKey = UniqueKey();

  @override
  Widget build(BuildContext context) {
    final session = widget.api.session;
    // The Admin tab is only a convenience for admins. Hiding it protects
    // nothing: the service refuses /admin/... for a USER token (403).
    final isAdmin = session.user?.isAdmin ?? false;
    final tabs = <(NavigationDestination, Widget Function())>[
      (const NavigationDestination(icon: Icon(Icons.currency_exchange), label: 'Rates'),
          () => RatesScreen(api: widget.api)),
      (const NavigationDestination(icon: Icon(Icons.account_balance_wallet_outlined), label: 'Wallet'),
          () => WalletScreen(key: _tabKey, api: widget.api)),
      (const NavigationDestination(icon: Icon(Icons.person_outline), label: 'Account'),
          () => AccountScreen(key: _tabKey, api: widget.api)),
      if (isAdmin)
        (const NavigationDestination(icon: Icon(Icons.admin_panel_settings_outlined), label: 'Admin'),
            () => AdminScreen(key: _tabKey, api: widget.api)),
    ];
    final tab = _tab < tabs.length ? _tab : 0;
    return Scaffold(
      body: Column(children: [
        ListenableBuilder(
          listenable: session,
          builder: (context, _) => session.offline && session.user != null
              ? OfflineBanner(email: session.user!.email, walletAt: session.lastWalletAt)
              : const SizedBox.shrink(),
        ),
        Expanded(child: tabs[tab].$2()),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() {
          _tab = i;
          _tabKey = UniqueKey();
        }),
        destinations: [for (final t in tabs) t.$1],
      ),
    );
  }
}
