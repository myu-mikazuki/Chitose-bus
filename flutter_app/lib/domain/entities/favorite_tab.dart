/// お気に入りのタブ。[stopId] はその停留所の ID。
/// null は「お気に入り未設定」を表す。
///
/// #177 以前はタブ番号（0〜3）で保存していたが、停留所を並べ替えたり削除すると
/// 別の停留所を指してしまうため、停留所 ID に変えた。
class FavoriteTab {
  const FavoriteTab({this.stopId});

  final String? stopId;

  bool get hasFavorite => stopId != null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is FavoriteTab && stopId == other.stopId;

  @override
  int get hashCode => stopId.hashCode;

  @override
  String toString() => 'FavoriteTab($stopId)';
}
