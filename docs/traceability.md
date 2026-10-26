# Requirements → use cases → components

Requirement numbers are from `requirements.md` (Lab 02).

| Requirement | Use case | Who handles it |
| --- | --- | --- |
| FR1 log in / register | Log in / register | AuthService |
| FR2 current rates with date | See current rates, Get rates from NBP | RatesScreen, RateService, NbpClient |
| FR3 convert | Convert amount | the app itself (RatesScreen) |
| FR4 wallet, starts with 1000 PLN | See wallet | WalletScreen, WalletRepository |
| FR5 buy | Buy currency | OrderScreen, OrderService |
| FR6 sell | Sell currency | OrderScreen, OrderService |
| FR7 not enough money | Buy / Sell (validate) | OrderService |
| FR8 requestId on every order | Buy / Sell | Order (app), OrderService |
| FR9 ask for order status | Check order status | PendingOrders, OrderService |
| FR10 rate changed | Buy / Sell (validate) | OrderService, RateService |
| NFR1 10 s timeout | all | ApiClient |
| NFR2 cached label | rates, wallet | LocalCache, screens |
| NFR3 stale rates | See current rates | RatesScreen, RateService |
| NFR4 block actions offline | Buy / Sell | ConnectivityMonitor, OrderScreen |
| NFR5 order runs only once | Buy / Sell | OrderService, OrderRepository |
| NFR6 retry reads only | rates, wallet | ApiClient |
| NFR7 fix things after reconnect | Check order status | ConnectivityMonitor, PendingOrders |
| NFR8 no negative balance | Buy / Sell | WalletRepository |
| NFR9 don't call NBP too often | Get rates from NBP | RateService, RateRepository |
| NFR10 HTTPS + token | everything with the wallet | AuthService, ApiClient |
