import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../views/widgets/banner_ad_widget.dart';

/// 画面下端のバナー広告を組み立てる。**テストで差し替えるための継ぎ目**（#192）。
///
/// 既定は実物の [BannerAdWidget]。`initState` で `BannerAd.load()` を呼ぶため、
/// テスト環境では実装が無く `MissingPluginException` になる。google_mobile_ads は
/// 独自のメッセージコーデックを使っていてメソッドチャネルの差し替えが効かないので、
/// ウィジェットごと差し替えられるようにしてある。
///
/// HomeScreen 全体を widget テスト・golden で扱うには、この経路を塞ぐ必要がある。
///
/// ```dart
/// bannerAdBuilderProvider.overrideWithValue((_) => const SizedBox.shrink()),
/// ```
final bannerAdBuilderProvider =
    Provider<Widget Function(VoidCallback onDismissed)>(
  (ref) => (onDismissed) => BannerAdWidget(onDismissed: onDismissed),
);
