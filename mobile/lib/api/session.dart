// Session: what the phone knows about the signed-in user (Lab 07).
//
// Rules for the signed-in view when the connection is lost:
//   - No connection or a timeout NEVER signs the user out. The token stays,
//     the user stays on their screens, and an offline banner says so.
//   - Only an answer from the service ends the session: 401 (token missing,
//     expired, revoked) or 403 ACCOUNT_DISABLED. Then the app goes back to
//     the login screen and says why.
//   - The wallet shown offline is the last one the SERVICE confirmed (from
//     GET /wallet or from a CONFIRMED order answer), with its time. The phone
//     never changes balances by itself and never shows an order as done
//     without the service's answer.
// Kept in memory only: closing the app logs out (a stored token is a later lab).
import 'package:flutter/foundation.dart';

import 'models.dart';

class Session extends ChangeNotifier {
  UserAccount? user;

  /// Code of the reason the last session ended (TOKEN_EXPIRED, LOGGED_OUT, ...).
  String? endedReason;

  /// Email of the last signed-in user, to fill in the login form again.
  String? lastEmail;

  Wallet? lastWallet;
  DateTime? lastWalletAt;

  /// True after a request got no HTTP answer; false again after any answer.
  bool offline = false;

  bool get signedIn => user != null;

  void start(UserAccount u) {
    user = u;
    endedReason = null;
    lastWallet = null;
    lastWalletAt = null;
    offline = false;
    notifyListeners();
  }

  /// Only call with balances that came from the service.
  void walletConfirmed(Wallet w, [DateTime? at]) {
    lastWallet = w;
    lastWalletAt = at ?? DateTime.now();
    notifyListeners();
  }

  void reachable() {
    if (offline) {
      offline = false;
      notifyListeners();
    }
  }

  void unreachable() {
    if (!offline) {
      offline = true;
      notifyListeners();
    }
  }

  void end(String reason) {
    if (user == null && endedReason == reason) return;
    lastEmail = user?.email ?? lastEmail;
    user = null;
    endedReason = reason;
    lastWallet = null;
    lastWalletAt = null;
    notifyListeners();
  }
}
