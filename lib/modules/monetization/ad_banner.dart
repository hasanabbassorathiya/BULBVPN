import 'dart:async';
import 'dart:io';

import 'package:bulbvpn/modules/monetization/ad_config.dart';
import 'package:bulbvpn/modules/monetization/ad_service.dart';
import 'package:bulbvpn/modules/monetization/ads_remote_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// An anchored adaptive banner that stays invisible until an ad is loaded.
///
/// The widget never throws into the page: a failed request, missing consent,
/// remote config still off, or unsupported platform collapses to zero height
/// and retries twice with a delay. It is intentionally placed away from the
/// connect control so a tap on the orb cannot be mistaken for an ad click.
class AdBanner extends ConsumerStatefulWidget {
  const AdBanner({super.key, this.horizontalInset = 0});

  /// Width removed from the media width before requesting the adaptive size.
  final double horizontalInset;

  @override
  ConsumerState<AdBanner> createState() => _AdBannerState();
}

class _AdBannerState extends ConsumerState<AdBanner> {
  BannerAd? _ad;
  bool _loaded = false;
  bool _loading = false;
  int _attempt = 0;
  Timer? _retry;

  bool get _adsAllowed =>
      ref.read(adsEnabledProvider) && AdConfig.canRequestAds;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted || !_adsAllowed || _loading || _loaded) return;
    _loading = true;
    try {
      final ready = await AdService.initialize();
      if (!ready || !mounted) return;
      final width = (MediaQuery.sizeOf(context).width - widget.horizontalInset)
          .truncate();
      final size =
          await AdSize.getLargeAnchoredAdaptiveBannerAdSize(width) ??
          AdSize.banner;
      if (!mounted) return;
      final ad = BannerAd(
        size: size,
        adUnitId: AdConfig.bannerUnitIdFor(isIos: Platform.isIOS),
        request: const AdRequest(),
        listener: BannerAdListener(
          onAdLoaded: (loaded) {
            if (!mounted) {
              loaded.dispose();
              return;
            }
            debugPrint('[Ads] banner loaded');
            setState(() {
              _ad = loaded as BannerAd;
              _loaded = true;
            });
          },
          onAdFailedToLoad: (failed, error) {
            failed.dispose();
            debugPrint('[Ads] banner failed (${error.code}): ${error.message}');
            _scheduleRetry();
          },
        ),
      );
      _ad?.dispose();
      _ad = ad;
      debugPrint('[Ads] requesting banner ${size.width}x${size.height}');
      await ad.load();
    } catch (error) {
      debugPrint('[Ads] banner request failed: $error');
      _scheduleRetry();
    } finally {
      _loading = false;
    }
  }

  void _scheduleRetry() {
    if (_attempt >= 2 || !mounted) return;
    _attempt++;
    _retry?.cancel();
    _retry = Timer(const Duration(seconds: 30), _load);
  }

  @override
  void dispose() {
    _retry?.cancel();
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Remote Config usually answers after the first frame; load as soon as the
    // flag flips instead of waiting for the next screen rebuild.
    ref.listen(adsEnabledProvider, (_, enabled) {
      if (enabled) _load();
    });
    final enabled = ref.watch(adsEnabledProvider) && AdConfig.canRequestAds;
    final ad = _ad;
    if (!enabled || !_loaded || ad == null) return const SizedBox.shrink();
    return Center(
      child: SizedBox(
        width: ad.size.width.toDouble(),
        height: ad.size.height.toDouble(),
        child: AdWidget(ad: ad),
      ),
    );
  }
}
