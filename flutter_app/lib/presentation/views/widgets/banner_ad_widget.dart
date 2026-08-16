import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../../core/constants/app_constants.dart';

/// 画面下端の AdMob バナー。読み込みに失敗したら何も出さない。
///
/// **差し替えの継ぎ目は `bannerAdBuilderProvider`**（`viewmodels/banner_ad_viewmodel.dart`）。
/// `initState` で `BannerAd.load()` を呼ぶため、テスト環境では実装が無く
/// `MissingPluginException` になる。これを含む画面を widget テスト・golden で
/// 扱うには、あちらで差し替える（#192）。
class BannerAdWidget extends StatefulWidget {
  const BannerAdWidget({super.key, required this.onDismissed});

  final VoidCallback onDismissed;

  @override
  State<BannerAdWidget> createState() => _BannerAdWidgetState();
}

class _BannerAdWidgetState extends State<BannerAdWidget> {
  BannerAd? _bannerAd;

  static String get _adUnitId {
    if (Platform.isAndroid) {
      return AppConstants.admobAndroidAdUnitId;
    } else {
      return AppConstants.admobIosAdUnitId;
    }
  }

  @override
  void initState() {
    super.initState();
    _bannerAd = BannerAd(
      adUnitId: _adUnitId,
      request: const AdRequest(),
      size: AdSize.banner,
      listener: BannerAdListener(
        onAdLoaded: (ad) => setState(() {}),
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          setState(() => _bannerAd = null);
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_bannerAd == null) return const SizedBox.shrink();
    return Stack(
      alignment: Alignment.topRight,
      children: [
        SizedBox(
          width: double.infinity,
          height: _bannerAd!.size.height.toDouble(),
          child: AdWidget(ad: _bannerAd!),
        ),
        GestureDetector(
          onTap: widget.onDismissed,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Center(
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, size: 16, color: Colors.white),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
