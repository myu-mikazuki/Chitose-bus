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
  /// **5 なのは、6 にすると名前が消えるため。** 375px の端末で最も短い
  /// 短縮名「研究棟」がどこまで残るかを実測した値:
  ///
  /// | タブ数 | 1タブ | ラベルに残る幅 | 見える名前 |
  /// |---|---|---|---|
  /// | 4（既定） | 93.8px | 33.3px | `研究棟` |
  /// | 5（上限） | 75.0px | 27.0px | `研…` |
  /// | 6 | 62.5px | 14.5px | `…`（名前が消える） |
  ///
  /// `TabBar` は各タブに `kTabLabelPadding`（左右 16px）を足すので、
  /// `HomeScreen._buildTab` の縮小経路が使える幅はタブ幅 − 32px からさらに星と間隔を
  /// 引いた残りになる。6 では `…` だけが残り、どのタブかを名前では選べない。
  ///
  /// **足していくのではなく入れ替えて使うもの**として考える。短縮名を持つのは
  /// 4停留所だけで、他は「古泉循環器内科クリニック前」のような正式名がそのまま
  /// 出るため、上限まで使う利用者ほど名前は読みにくくなる。設定画面も、上限では
  /// 「別の停留所にするには外す」と促している。
  ///
  /// スクロールするタブ（`TabBar(isScrollable: true)`）にすれば上限は要らないが、
  /// 既定4タブの見た目が変わる。#177 で通してきた方針と衝突するため採らない。
  /// レイアウトを見直す #23 の段で改めて検討する。
  ///
  /// **下限と非対称なのは承知のうえ。** 0個は StopSelectionRepository でも
  /// `initial` に戻すが、上限は設定画面でしか止めない。超えた選択が保存されて
  /// いるのは #177 を触った開発端末だけで、そこでは見出しが `6 / 5` になるが、
  /// 1つ外せば直る。読み込み時に黙って切り詰めると、利用者の選択が理由も
  /// 分からず消えるほうが分かりにくい、という判断（#204）。
  static const maxStops = 5;

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
