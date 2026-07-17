import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/ad_provider.dart';

class BannerAdWidget extends StatelessWidget {
  final AdPlacement placement;

  const BannerAdWidget({super.key, required this.placement});

  @override
  Widget build(BuildContext context) {
    return Consumer<AdProvider>(
      builder: (context, adProvider, _) {
        if (!adProvider.showAds || !adProvider.initialized) {
          return const SizedBox.shrink();
        }

        return const SizedBox.shrink();
      },
    );
  }
}
