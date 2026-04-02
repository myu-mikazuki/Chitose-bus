/// お気に入りタブの設定。
/// [tabIndex] は HomeScreen のタブインデックス (0〜3)。
/// null は「お気に入り未設定」を表す。
class FavoriteTab {
  const FavoriteTab({this.tabIndex});

  final int? tabIndex;

  bool get hasFavorite => tabIndex != null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FavoriteTab && tabIndex == other.tabIndex;

  @override
  int get hashCode => tabIndex.hashCode;
}
