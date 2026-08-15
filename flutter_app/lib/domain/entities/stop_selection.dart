/// タブに表示する停留所の選択。
///
/// **並び順がそのままタブの並びになる。** 順序が違えば別の選択として扱う。
///
/// 既定は現行の4停留所で、設定を触らないユーザーの見た目は変わらない。
/// GAS へは `?stops=` として渡し、応答を必要な停留所だけに絞る（Issue #177）。
class StopSelection {
  const StopSelection({required this.stopIds});

  /// 初期値。この4停留所は #177 以前からアプリが扱っていたもの。
  static const initial = StopSelection(stopIds: defaultStopIds);

  static const defaultStopIds = <String>[
    'chitose',
    'minamiChitose',
    'kenkyuto',
    'honbuto',
  ];

  /// 選べる停留所の上限。
  ///
  /// タブは画面幅を等分するので、増やすほど1つあたりが狭くなる。乗車可能な
  /// 停留所は30あり、上限が無いと 375px の端末で1タブ約 12.5px になって
  /// 名前も星も判別できない（#204）。
  ///
  /// スクロールするタブ（`TabBar(isScrollable: true)`）にすれば上限は要らないが、
  /// 既定4タブの見た目が変わる。#177 で通してきた方針と衝突するため採らない。
  static const maxStops = 6;

  final List<String> stopIds;

  /// GAS の `?stops=` に渡す形。キャッシュのキーにも使う
  String get query => stopIds.join(',');

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! StopSelection) return false;
    if (other.stopIds.length != stopIds.length) return false;
    for (var i = 0; i < stopIds.length; i++) {
      if (other.stopIds[i] != stopIds[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(stopIds);

  @override
  String toString() => 'StopSelection($query)';
}
