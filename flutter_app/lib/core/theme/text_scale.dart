import 'package:flutter/material.dart';

/// 文字を大きくする設定（`TextScaler`）の比率を出す共通の作法（#240）。
///
/// `_StopTab`（`home_screen.dart`）と `_NextBusCard`（`next_bus_display.dart`）の
/// 両方が「拡大時だけ縦の余白を詰める」ために同じしきい値・同じ比率の出し方を
/// 使う。**2箇所に同じ計算を書くと片方だけ直す事故が起きる**
/// （`_StopLabelPlaceholder.scaledWidth`・#243 で踏んだのと同じ話）ので、
/// 定義はここ1つにまとめる。

/// [baseFontSize] の文字が、いまの `TextScaler` でどれだけ拡大されるかの比率。
///
/// **`TextScaler.scale()` に任意の px（余白の高さなど）を直接渡してはいけない**——
/// あれは「素のフォントサイズ → 拡大後のフォントサイズ」を返すもので、任意の
/// 長さを倍率で伸ばす関数ではない。Android 14 以降の非線形スケーリングでは
/// **倍率が元のフォントサイズごとに違う**（大きい字ほど伸びを抑える曲線）ため、
/// `scale(42)` は 42pt の字の曲線を引いてしまい、実際に伸ばしたい要素（14px の
/// 文字など）に掛かる倍率とは別物になる。
///
/// **比率は「素の文字の大きさ」から出し、出た比率を他の長さに掛けること。**
/// `TextScaler.linear` では素直に一致するので、間違えても**テストは緑のまま
/// 実機だけずれる**（`_StopLabelPlaceholder.scaledWidth`・#243 と同じ作法）。
double textScaleRatio(BuildContext context, {double baseFontSize = 14.0}) {
  return MediaQuery.textScalerOf(context).scale(baseFontSize) / baseFontSize;
}

/// このしきい値を超えたら、余白を詰めるのをやめて `_StopTab` ごと
/// スクロールに切り替える（#240 の方式 (c)）。
///
/// 375×667・実フォント（Meiryo）での実測（#240 着手前・`_StopTab` の
/// `Column` が縦に溢れる量）:
///
/// | 倍率 | 状態 | 溢れ |
/// |---|---|---|
/// | 1.3（Android の「最大」） | 到着行を全部開く | 7px |
/// | 1.4 | 到着行を1つ開く | 13px |
/// | 1.5 | 閉じたまま | 15px |
/// | 2.0 | 閉じたまま | 323px |
///
/// **Android の「最大」(1.3) を余白を詰めるだけ（(a)）で確実に通すことを
/// 目標にした。** 1.3〜1.5 は数十px 級で余白を詰めれば吸収できる範囲だが、
/// 2.0 の 323px は文字そのものが折り返して増えた分なので、(a) では届かない
/// （(c) が要る）。**しきい値は Android の実際の上限である 1.3 ちょうどに
/// 置き、それを超えたら (a) を追い込まず (c) の全体スクロールに任せる**
/// ——1.4 以降まで (a) を伸ばそうとすると、詰める量が視覚的に行き過ぎる
/// わりに実際の対象（Android は 1.3 が上限）を超えて意味が薄い。
///
/// 実装後の実測（375×667・実フォント・到着行を全部開いた状態）では
/// **2.0 まで縦の overflow が出ない**——1.3 を超えた分は (c) がそのまま
/// 吸収する。`doc/roadmap.md`「#237 で分かったこと」に表がある。
const kVerticalScrollThreshold = 1.3;

/// 詰め方の下限。しきい値ちょうど（[kVerticalScrollThreshold]）でこの倍率まで
/// 詰まる。0.35 = 最大65%詰める。
///
/// 対象は「安全な余白」（カードの padding・`SizedBox` の高さ）だけで、文字は
/// 一切触らない。カード＋`_StopTab` 側を合わせた詰められる余白の合計は
/// 約180px（等倍時）あるので、しきい値ちょうどでも大半が残る。
const _minSqueezeFactor = 0.35;

/// [ratio] に応じて縦の余白を詰める倍率を返す。
///
/// - 等倍（[ratio] <= 1.0）では **1.0**（1pxも変えない）
/// - [kVerticalScrollThreshold] 以上では [_minSqueezeFactor]（詰め方の下限）で
///   頭打ちにする。**呼び出し側は [kVerticalScrollThreshold] を超えたら
///   この関数を使わず、代わりに全体スクロール（(c)）へ切り替えること**
///   ——詰めた状態のままスクロールに切り替えると、余白を残せるのに
///   窮屈な見た目のままになる
double verticalSqueezeFactor(double ratio) {
  if (ratio <= 1.0) return 1.0;
  final t = ((ratio - 1.0) / (kVerticalScrollThreshold - 1.0)).clamp(0.0, 1.0);
  return 1.0 - t * (1.0 - _minSqueezeFactor);
}

/// 縦の余白を詰める倍率を、**しきい値の判定込み**で返す（#240）。
///
/// **余白を詰める側はこちらを呼ぶこと。**[verticalSqueezeFactor] を直に呼ぶと、
/// [kVerticalScrollThreshold] を超えたときに下限（35%）で頭打ちになったまま
/// 返ってくる。その状態で (c) の全体スクロールに切り替わると、**縦は
/// いくらでも使えるのに余白だけ詰まったまま**という窮屈な見た目になる。
///
/// **実際に踏んだ**（PR #252 のレビュー指摘）。`_StopTab` は呼び出し側で
/// `useFullScroll ? 1.0 : ...` と判定していたが、`_NextBusCard` は
/// [verticalSqueezeFactor] を直に呼んでいたため、**しきい値を超えると
/// タブの余白は元に戻るのにカードの中だけ詰まったまま**になっていた。
/// **判定を2箇所に書いたせいで片方だけ落ちた**——このファイルが防ぐはずの
/// 事故そのものなので、判定ごとここに引き取る。
///
/// スクロールに切り替えるかどうかは [useVerticalScroll] で別に取る。
double verticalSqueezeOf(BuildContext context) {
  final ratio = textScaleRatio(context);
  if (ratio > kVerticalScrollThreshold) return 1.0;
  return verticalSqueezeFactor(ratio);
}

/// (c) の全体スクロールに切り替えるかどうか（#240）。
bool useVerticalScroll(BuildContext context) =>
    textScaleRatio(context) > kVerticalScrollThreshold;
