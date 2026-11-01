import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:bulbvpn/shared/services/firebase_analytics_service.dart';

/// Entitlement identifier configured in the RevenueCat dashboard.
const premiumEntitlementId = 'premium';

enum PremiumStatus { unknown, loading, free, active, unconfigured, error }

class PremiumState {
  final PremiumStatus status;
  final Offerings? offerings;
  final String? message;

  const PremiumState({
    this.status = PremiumStatus.unknown,
    this.offerings,
    this.message,
  });

  bool get isActive => status == PremiumStatus.active;

  /// False until RevenueCat has answered, so ads never flash for a paying
  /// account during a cold start.
  bool get isSettled =>
      status != PremiumStatus.unknown && status != PremiumStatus.loading;

  bool get isConfigured =>
      status != PremiumStatus.unconfigured && status != PremiumStatus.unknown;

  bool get hasProducts =>
      offerings?.current?.availablePackages.isNotEmpty ?? false;

  PremiumState copyWith({
    PremiumStatus? status,
    Offerings? offerings,
    String? message,
  }) {
    return PremiumState(
      status: status ?? this.status,
      offerings: offerings ?? this.offerings,
      message: message,
    );
  }
}

String _dotenv(String key) {
  try {
    return dotenv.env[key]?.trim() ?? '';
  } catch (_) {
    return '';
  }
}

String get revenueCatKey {
  const apple = String.fromEnvironment('REVENUECAT_APPLE_KEY');
  const google = String.fromEnvironment('REVENUECAT_GOOGLE_KEY');
  if (Platform.isAndroid) {
    return _dotenv('REVENUECAT_GOOGLE_KEY').isEmpty
        ? google
        : _dotenv('REVENUECAT_GOOGLE_KEY');
  }
  return _dotenv('REVENUECAT_APPLE_KEY').isEmpty
      ? apple
      : _dotenv('REVENUECAT_APPLE_KEY');
}

/// Endpoint that validates a universal promo code and grants the RevenueCat
/// entitlement server-side. Empty until the backend is deployed.
String get premiumRedeemUrl {
  const build = String.fromEnvironment('PREMIUM_REDEEM_URL');
  final env = _dotenv('PREMIUM_REDEEM_URL');
  return env.isEmpty ? build : env;
}

/// Premium state for the whole app. The VPN never requires this: free users
/// keep the full relay list. Premium removes ads and ranks less-congested
/// relays first.
class PremiumNotifier extends StateNotifier<PremiumState> {
  PremiumNotifier() : super(const PremiumState());

  final FirebaseAnalyticsService _analytics = FirebaseAnalyticsService();
  bool _started = false;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    final key = revenueCatKey;
    if (key.isEmpty) {
      state = state.copyWith(status: PremiumStatus.unconfigured);
      return;
    }
    state = state.copyWith(status: PremiumStatus.loading);
    try {
      await Purchases.setLogLevel(
        kDebugMode ? LogLevel.info : LogLevel.warn,
      );
      await Purchases.configure(PurchasesConfiguration(key));
      Purchases.addCustomerInfoUpdateListener(_onCustomerInfo);
      await refresh();
      await loadOfferings();
    } catch (error) {
      debugPrint('[Premium] RevenueCat unavailable: $error');
      state = state.copyWith(
        status: PremiumStatus.error,
        message: 'Store unavailable',
      );
    }
  }

  void _onCustomerInfo(CustomerInfo info) {
    _apply(info);
  }

  void _apply(CustomerInfo info) {
    final active = info.entitlements.active.containsKey(premiumEntitlementId);
    state = state.copyWith(
      status: active ? PremiumStatus.active : PremiumStatus.free,
    );
  }

  Future<void> refresh() async {
    if (!state.isConfigured) return;
    try {
      final info = await Purchases.getCustomerInfo();
      _apply(info);
    } catch (error) {
      debugPrint('[Premium] customer info failed: $error');
    }
  }

  Future<void> loadOfferings() async {
    if (!state.isConfigured) return;
    try {
      final offerings = await Purchases.getOfferings();
      state = state.copyWith(offerings: offerings);
    } catch (error) {
      debugPrint('[Premium] offerings failed: $error');
    }
  }

  /// Returns null on success, otherwise a message suitable for a snackbar.
  Future<String?> purchase(Package package) async {
    try {
      final result = await Purchases.purchase(PurchaseParams.package(package));
      _apply(result.customerInfo);
      if (!state.isActive) {
        return 'Purchase finished, but Premium is not active yet.';
      }
      unawaited(_analytics.logPremiumPurchase(package.storeProduct.identifier));
      return null;
    } on PlatformException catch (error) {
      final code = PurchasesErrorHelper.getErrorCode(error);
      if (code == PurchasesErrorCode.purchaseCancelledError) return null;
      return error.message ?? 'Purchase failed';
    } catch (error) {
      return 'Purchase failed: $error';
    }
  }

  /// Returns null when restore completed, otherwise an error message.
  Future<String?> restore() async {
    try {
      final info = await Purchases.restorePurchases();
      _apply(info);
      if (!state.isActive) {
        return 'No active purchase found on this account.';
      }
      unawaited(_analytics.logPremiumRestore());
      return null;
    } catch (error) {
      return 'Restore failed: $error';
    }
  }

  /// Redeems a cross-platform code through our backend. The backend marks the
  /// code used and grants the same RevenueCat entitlement a purchase would.
  Future<String?> redeemUniversal(String code) async {
    final trimmed = code.trim().toUpperCase();
    if (trimmed.isEmpty) return 'Enter a code first.';
    if (!state.isConfigured) {
      return 'Store setup is not live in this build.';
    }
    final url = premiumRedeemUrl;
    if (url.isEmpty) {
      return 'Code redemption is not available in this build yet.';
    }
    try {
      final response = await http
          .post(
            Uri.parse(url),
            headers: const {'content-type': 'application/json'},
            body: jsonEncode({
              'code': trimmed,
              'app_user_id': Purchases.appUserID,
              'platform': Platform.operatingSystem,
            }),
          )
          .timeout(const Duration(seconds: 15));
      final body = response.body.isEmpty
          ? const <String, dynamic>{}
          : jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200 || body['ok'] != true) {
        return body['error']?.toString() ?? 'That code could not be redeemed.';
      }
      await refresh();
      return state.isActive ? null : 'Code accepted; Premium is syncing.';
    } catch (error) {
      return 'Redeem failed: $error';
    }
  }
}

final premiumProvider = StateNotifierProvider<PremiumNotifier, PremiumState>((
  ref,
) {
  final notifier = PremiumNotifier();
  unawaited(notifier.start());
  return notifier;
});

final premiumActiveProvider = Provider<bool>(
  (ref) => ref.watch(premiumProvider).isActive,
);

/// Ads stay off for paying users even when the remote flag is on, and are
/// held back until the entitlement state is known.
final adsVisibleProvider = Provider<bool>((ref) {
  final premium = ref.watch(premiumProvider);
  return premium.isSettled && !premium.isActive;
});
