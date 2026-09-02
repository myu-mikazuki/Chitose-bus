import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_colors_theme.dart';
import '../../core/theme/text_scale.dart';
import '../../domain/entities/bus_schedule.dart';
import '../viewmodels/banner_ad_viewmodel.dart';
import '../viewmodels/favorite_tab_viewmodel.dart';
import '../viewmodels/schedule_viewmodel.dart';
import '../viewmodels/stop_selection_viewmodel.dart';
import '../../domain/entities/stop_selection.dart';
import 'settings_screen.dart';
import 'widgets/next_bus_display.dart';
import 'widgets/offline_cache_banner.dart';
import 'widgets/schedule_list.dart';
import 'widgets/season_notice_banner.dart';
import 'widgets/weekend_warning_banner.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

/// `TabBarView`（内部は `PageView`）の各ページの一番外側を包み、縦ドラッグが
/// 横スワイプ（タブ切り替え）に奪われるのを防ぐバリア（#260）。
///
/// ## なぜ要るか
///
/// `PageView` は `HorizontalDragGestureRecognizer` を持つ。ジェスチャー
/// アリーナに縦の recognizer が1つも参加していないと、横の recognizer が
/// アリーナで唯一のメンバーになり、アリーナが閉じた時点で無条件に勝つ。
/// すると縦スワイプのわずかな横成分がすべてページ送りに使われ、隣のタブへ
/// 飛んでしまう。このバリアは「縦の recognizer を必ず1つアリーナに参加させる」
/// ための空の `onVerticalDragUpdate` ハンドラで、それ自体は何もしない
/// （縦方向の recognizer がアリーナに存在すること自体が目的）。
///
/// ## なぜ内側のスクロールを壊さないか
///
/// ヒットテストは子を先に処理してから自分を結果に加える
/// （`RenderProxyBoxWithHitTestBehavior` 系の作り）ため、`ListView` /
/// `SingleChildScrollView` のスクロール recognizer は、このバリアより**先に**
/// アリーナへ参加する。縦ドラッグが縦の slop を超えると、先に参加した内側の
/// recognizer が先に自己受理してアリーナを勝ち取るので、内側のスクロールは
/// 今までどおり動く（`ScheduleList` は有界時、自前の `SingleChildScrollView`
/// でスクロールする——`schedule_list.dart` 参照。このバリアの外側から包んでも
/// 実際にスクロールが動くことをテストで確認済み）。バリアが効くのは、
/// 内側に縦の recognizer が居ない場面
/// ——余白・見出し・(c) で中身が画面に収まっていて `SingleChildScrollView` が
/// `setCanDrag(false)` により recognizer を持たないとき——に限られる。
///
/// ## 置き場所: `_StopTab` の内側ではなく `TabBarView` の各 child の最外周
///
/// かつては `_StopTab` の内側2箇所（NEXT BUS カード・時刻表リスト）にだけ
/// 掛け、(c)（`useFullScroll`・拡大 1.3 超）のときは `active: false` で
/// 外していた。だが (c) では外側の `SingleChildScrollView` の**外**（
/// `SegmentedButton` の周り・見出しの行・フッタの余白）にバリアが無くなり、
/// そこを掴んで斜めに引くと横に取られる穴が残っていた。
///
/// ここ（`TabBarView` の各 child の最外周）に常時1つ掛ければ、(c) の
/// `SingleChildScrollView` は必ずこのバリアの子孫になる。**スクロール可能な
/// ときは内側の recognizer が先に勝ち、中身が収まってスクロール不要な
/// ときはバリアが縦を吸ってページ送りを防ぐ**——両方が同時に成り立つので、
/// `active` フラグはもう要らない。`_StopNotFetched` / `_StopHasNoBus` の
/// ような静的なページも同じ場所で一緒に守れる。
///
/// ## `HitTestBehavior.opaque` が要る理由
///
/// 既定（`HitTestBehavior.deferToChild`）は、子が自分をヒットテストしない
/// 限り自分もヒットテストされない。`RenderFlex`（`Row`/`Column`）や
/// `RenderPadding` は自分自身をヒットテストしないので、`SegmentedButton` の
/// 周りや見出し・フッタの**余白**（文字の上ではない部分）を掴んだドラッグ
/// では、このバリアがそもそもアリーナに参加せず穴が残る。`opaque` にして、
/// 子が透明でも自分がヒットテストの対象になるようにする。
///
/// [key] は呼び出し側の `Key` をそのまま渡すこと。`TabBarView.children` は
/// 停留所の並べ替え・追加で入れ替わるため、直下の要素が停留所ごとの `Key`
/// （`ValueKey(stopId)`）を持たないと、Flutter の子リスト差分検出（key に
/// よる要素の再利用）が働かず、並び替え時に State（選択中の行き先・
/// スクロール位置など）が正しい停留所に追随しなくなる。
Widget _wrapVerticalDragBarrier(Widget child, {Key? key}) {
  return GestureDetector(
    key: key,
    behavior: HitTestBehavior.opaque,
    onVerticalDragUpdate: (_) {},
    child: child,
  );
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;

  /// [_tabController] を組んだときの停留所。**タブの構成はこれが正**で、
  /// TabBar / TabBarView もこれを見る。選択そのものを直接描画すると、
  /// controller の長さと食い違ったフレームが生まれて落ちる。
  late List<String> _tabStopIds;

  bool _bannerDismissed = false;
  bool _favoriteApplied = false;

  @override
  void initState() {
    super.initState();
    // 選択の読み出しは非同期。解決するまでは既定の4停留所で組んでおく
    _tabStopIds = StopSelection.initial.stopIds;
    _tabController = TabController(length: _tabStopIds.length, vsync: this);
  }

  /// タブを [stopIds] の構成で組み直す。
  ///
  /// [focusStopId] を渡すとその停留所を開く（お気に入りの初回適用）。
  /// 指定が無ければ**いま見ている停留所を追いかける**。タブ番号で覚えると、
  /// 並べ替えや追加のたびに別の停留所へ飛んでしまう。
  ///
  /// 長さを変えるだけ（`_tabController.index = ...`）では足りず作り直す。
  /// TabBarView が未生成のまま index を動かすと、初回生成時に PageView の
  /// initialPage と TabController の内部状態がずれて SegmentedButton の高さが
  /// 0 になる（#126）。initialIndex を持つ controller を作れば起きない。
  ///
  /// **build 中から呼ぶ。** この直後に組む TabBar / TabBarView が同じ build で
  /// 新しい controller と `_tabStopIds` を読むため、setState は要らないし、
  /// 次フレームへ遅らせると1フレームだけ両者が食い違う。
  void _retuneTabs(List<String> stopIds, {String? focusStopId}) {
    final viewing = _tabController.index < _tabStopIds.length
        ? _tabStopIds[_tabController.index]
        : null;
    // 見ていた停留所が外されていれば先頭に戻す
    final index = stopIds.indexOf(focusStopId ?? viewing ?? '');

    final old = _tabController;
    _tabStopIds = stopIds;
    _tabController = TabController(
      length: stopIds.length,
      initialIndex: index < 0 ? 0 : index,
      vsync: this,
    );
    // build 中に捨てると、まだ古い controller を参照している TabBar が落ちる
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// タブ1つ。[label] が null なら停留所名がまだ分からない（初回起動）。
  ///
  /// 名前の供給元は GAS の `stopMaster` だけなので、届くまで出せる名前が無い。
  /// ID をそのまま出すと `chitose` のような英字が並ぶため、代わりに場所だけ
  /// 取っておく（#177）。
  ///
  /// 場所取りも名前と同じ幅の計算に通す。別扱いにすると、名前が届いた瞬間に
  /// 星が横並びから右端へ跳ぶ。
  Tab _buildTab(String? label, String stopId, String? favoriteStopId) {
    return Tab(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isFavorite = favoriteStopId == stopId;
          final tabWidth = constraints.maxWidth;

          // 並べ方を決めるための幅。名前はタブ内のラベルスタイルで実測する
          // （場所取りは幅が決まっているので計測しない）
          final double textWidth;
          if (label == null) {
            // **場所取りも同じ倍率で測ること**（#243）。名前側だけ拡大を見ると、
            // 拡大時に**名前が届いた瞬間に並べ方が切り替わって星が跳ぶ**
            // （[_StopLabelPlaceholder.width] の注記にある事故そのもの）。
            // **描く側と同じ関数を呼ぶ**ので、片方だけ直す事故が起きない
            textWidth = _StopLabelPlaceholder.scaledWidth(context);
          } else {
            final textStyle = DefaultTextStyle.of(context).style;
            textWidth = (TextPainter(
              text: TextSpan(text: label, style: textStyle),
              textDirection: TextDirection.ltr,
              // **文字を大きくする設定を渡すこと**（#243）。既定は
              // `TextScaler.noScaling` なので、渡さないと**常に等倍で測る**。
              // 拡大時は下の `stackFits` / `rowFits` が「収まる」と誤判定し、
              // **`Flexible` + ellipsis を持つ縮小経路を外して**タブが溢れる。
              // 375px・4タブで倍率 1.4 から実際に溢れていた
              textScaler: MediaQuery.textScalerOf(context),
            )..layout())
                .width;
          }

          const starSize = 20.0;
          const gap = 4.0;

          /// 名前、または届くまでの場所取り。**見た目の分岐はここだけ**。
          /// 3つの並べ方それぞれで書き分けると、片方だけ直す事故が起きる。
          ///
          /// ellipsis はどの並べ方でも付けてよい。収まる経路では効かず、
          /// 縮小経路（[Flexible] の中）でだけ働く。
          Widget labelWidget([TextStyle? style]) => label == null
              ? const _StopLabelPlaceholder()
              : Text(
                  label,
                  style: style,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                );

          Widget starIcon(double size) => GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => ref
                    .read(favoriteTabProvider.notifier)
                    .toggleFavorite(stopId),
                child: Icon(
                  isFavorite ? Icons.star : Icons.star_border,
                  size: size,
                  color: isFavorite ? AppColors.warning : null,
                ),
              );

          // デフォルト: ラベル中央・スター右端（重ならない場合）
          // 中央テキストの右端 = tabWidth/2 + textWidth/2
          // スターの左端 = tabWidth - starSize
          final stackFits =
              tabWidth / 2 + textWidth / 2 + gap <= tabWidth - starSize;
          if (stackFits) {
            return Stack(
              children: [
                Align(alignment: Alignment.center, child: labelWidget()),
                Align(
                    alignment: Alignment.centerRight,
                    child: starIcon(starSize)),
              ],
            );
          }

          // 横並び（重なる場合）
          final rowFits = textWidth + gap + starSize <= tabWidth;
          if (rowFits) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                labelWidget(),
                const SizedBox(width: gap),
                starIcon(starSize),
              ],
            );
          }

          // 縮小表示（横並びでも収まらない場合）。
          // ここは「入らないと分かっている」経路なので、Flexible + ellipsis で
          // 必ず幅に収める。短縮名を持たない停留所（古泉循環器内科クリニック前
          // など）を選ぶと、11px でもタブ幅を超える（#177）
          return Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 場所取りも Flexible の中では縮む（停留所を増やすとタブが狭まる）
              Flexible(child: labelWidget(const TextStyle(fontSize: 11))),
              const SizedBox(width: 2),
              starIcon(14),
            ],
          );
        },
      ),
    );
  }

  void _toggleDayTypeView() {
    final dayNotifier = ref.read(dayTypeOverrideProvider.notifier);
    final seasonNotifier = ref.read(seasonOverrideProvider.notifier);
    if (dayNotifier.state != null) {
      dayNotifier.state = null;
      seasonNotifier.state = null;
      return;
    }
    // 当日以外モードに入るときは、当日と逆のダイヤを初期表示する
    // （平日に土日祝ダイヤを確認する、が主なユースケースのため）
    final now = DateTime.now();
    final today = DayType.fromDate(now);
    dayNotifier.state =
        today == DayType.weekday ? DayType.weekendHoliday : DayType.weekday;
    // 期別は当日のものを初期値とする（主目的は曜日ダイヤの確認のため）
    seasonNotifier.state = SeasonType.fromDate(now);
  }

  @override
  Widget build(BuildContext context) {
    final scheduleAsync = ref.watch(scheduleViewModelProvider);
    final favoriteAsync = ref.watch(favoriteTabProvider);
    final favoriteStopId = favoriteAsync.valueOrNull?.stopId;
    final selectionAsync = ref.watch(stopSelectionProvider);
    final selection = selectionAsync.valueOrNull ?? StopSelection.initial;
    final dayType = ref.watch(dayTypeOverrideProvider);
    final season = ref.watch(seasonOverrideProvider);

    // お気に入りタブの初回適用（アプリ起動時のみ）。
    //
    // 停留所の選択と favorite の両方が揃ってから適用する。ref.listen は変化時に
    // しか発火しないため、片方が先に解決した時点で適用済みにすると、あとから
    // もう片方が届いても再適用されない。build で両方を watch して判定する。
    final applyFavorite =
        !_favoriteApplied && favoriteAsync.hasValue && selectionAsync.hasValue;
    if (applyFavorite) _favoriteApplied = true;

    // 設定でバス停を足す・外す・並べ替えるとここに届く
    if (applyFavorite || !listEquals(_tabStopIds, selection.stopIds)) {
      _retuneTabs(
        selection.stopIds,
        focusStopId: applyFavorite ? favoriteStopId : null,
      );
    }
    final stopIds = _tabStopIds;

    return Scaffold(
      backgroundColor: context.appColors.background,
      appBar: AppBar(
        backgroundColor: context.appColors.background,
        foregroundColor: AppColors.primary,
        title: const Text(
          'Kagi-Bus',
          style: TextStyle(
            color: AppColors.primary,
            fontSize: 18,
            letterSpacing: 3,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          if (kDebugMode) ...[
            Consumer(builder: (context, ref, _) {
              final debugTime = ref.watch(debugTimeProvider);
              return IconButton(
                icon: Icon(
                  Icons.access_time,
                  color: debugTime != null
                      ? AppColors.warning
                      : context.appColors.textDisabled,
                ),
                tooltip: debugTime != null
                    ? '時刻オーバーライド中 (タップでリセット/変更)'
                    : 'デバッグ: 時刻を設定',
                onPressed: () => _onDebugTimeTap(context, ref, debugTime),
              );
            }),
          ],
          scheduleAsync.maybeWhen(
            data: (r) => r.data.current.pdfUrl.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.open_in_browser,
                        color: AppColors.primary),
                    tooltip: '時刻表原文を開く',
                    onPressed: () => launchUrl(
                      Uri.parse(r.data.current.pdfUrl),
                      mode: LaunchMode.externalApplication,
                    ),
                  )
                : const SizedBox.shrink(),
            orElse: () => const SizedBox.shrink(),
          ),
          scheduleAsync.maybeWhen(
            data: (r) => r.data.upcoming != null
                ? IconButton(
                    icon: const Icon(Icons.calendar_month,
                        color: AppColors.warning),
                    tooltip: '来週のダイヤ',
                    onPressed: () => _showUpcomingSheet(
                      context,
                      r.data.upcoming!,
                      r.data.stopMaster,
                    ),
                  )
                : const SizedBox.shrink(),
            orElse: () => const SizedBox.shrink(),
          ),
          IconButton(
            icon: Icon(
              Icons.event_repeat,
              color: dayType != null ? AppColors.warning : AppColors.primary,
            ),
            tooltip: dayType != null ? '当日のダイヤに戻る' : '当日以外のダイヤを表示',
            onPressed: _toggleDayTypeView,
          ),
          IconButton(
            icon: const Icon(Icons.settings, color: AppColors.primary),
            tooltip: '設定',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.primary),
            onPressed: () =>
                ref.read(scheduleViewModelProvider.notifier).refresh(),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.primary,
          labelColor: AppColors.primary,
          unselectedLabelColor: context.appColors.textDisabled,
          tabs: [
            for (final id in stopIds)
              _buildTab(
                // 応答そのものがまだ無ければ名前は分からない（初回起動）。
                // 応答があって stopMaster に無い停留所は ID のまま出す
                // （GAS から消えた停留所。ずっと直らないので伏せない）
                scheduleAsync.valueOrNull?.data.stopMaster.labelOf(id),
                id,
                favoriteStopId,
              ),
          ],
        ),
      ),
      body: Stack(
        children: [
          scheduleAsync.when(
            loading: () => const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
            error: (e, _) => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('エラー: $e',
                      style: const TextStyle(color: AppColors.error)),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () =>
                        ref.read(scheduleViewModelProvider.notifier).refresh(),
                    child: const Text('再試行',
                        style: TextStyle(color: AppColors.primary)),
                  ),
                ],
              ),
            ),
            data: (result) {
              return Column(
                children: [
                  if (result.isFromCache)
                    OfflineCacheBanner(updatedAt: result.data.updatedAt),
                  if (dayType != null) ...[
                    _DayTypeSelector(dayType: dayType),
                    _SeasonSelector(
                      season: season ?? SeasonType.fromDate(DateTime.now()),
                    ),
                  ],
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        for (final id in stopIds)
                          // 縦ドラッグが横スワイプ（タブ切り替え）に奪われる
                          // のを防ぐバリア（#260）。各ページの最外周に常時
                          // 掛ける——理由は [_wrapVerticalDragBarrier] 参照。
                          // **key は中身と同じ値を付ける**（並べ替え時の
                          // State 追随のため。関数のドキュメント参照）
                          !result.data.covers(id)
                              ? _wrapVerticalDragBarrier(
                                  key: ValueKey('notFetched_$id'),
                                  // オフラインで停留所を足すと、その停留所の
                                  // 時刻を持たないキャッシュを表示すること
                                  // になる。「便が1本も無い」と区別して
                                  // 伝える（#177）
                                  _StopNotFetched(
                                    onRetry: () => ref
                                        .read(
                                            scheduleViewModelProvider.notifier)
                                        .refresh(),
                                  ),
                                )
                              : _wrapVerticalDragBarrier(
                                  key: ValueKey(id),
                                  _StopTab(
                                    timetable: result.data.current,
                                    stopId: id,
                                    stopMaster: result.data.stopMaster,
                                    updatedAt: result.data.updatedAt,
                                    dayType: dayType,
                                    season: season,
                                  ),
                                ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
          if (!kIsWeb && !_bannerDismissed)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: ref.read(bannerAdBuilderProvider)(
                () => setState(() => _bannerDismissed = true),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _onDebugTimeTap(
      BuildContext context, WidgetRef ref, DateTime? current) async {
    if (current != null) {
      // オーバーライド中: リセットか変更かを選択
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: ctx.appColors.surface,
          title: const Text('時刻オーバーライド',
              style: TextStyle(color: AppColors.primary)),
          content: Text(
            '現在: ${current.hour.toString().padLeft(2, '0')}:${current.minute.toString().padLeft(2, '0')}',
            style: TextStyle(color: ctx.appColors.textPrimary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'reset'),
              child:
                  const Text('リセット', style: TextStyle(color: AppColors.error)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'change'),
              child:
                  const Text('変更', style: TextStyle(color: AppColors.warning)),
            ),
          ],
        ),
      );
      if (choice == 'reset') {
        ref.read(debugTimeProvider.notifier).state = null;
        return;
      }
      if (choice != 'change') return;
    }

    // 時刻ピッカーを表示
    if (!context.mounted) return;
    final picked = await showTimePicker(
      context: context,
      initialTime: current != null
          ? TimeOfDay(hour: current.hour, minute: current.minute)
          : TimeOfDay.now(),
    );
    if (picked == null) return;

    final now = DateTime.now();
    ref.read(debugTimeProvider.notifier).state = DateTime(
      now.year,
      now.month,
      now.day,
      picked.hour,
      picked.minute,
    );
  }

  /// 「来週のダイヤ」シート。
  ///
  /// **ここだけ4停留所のまま**。`upcoming` も `?stops=` で絞られるので、選択から
  /// 外した停留所の節は空のまま並ぶ。
  ///
  /// GAS の `doGet` は `upcoming: null` を直書きしており（`getHardcodedTimetable`・
  /// `buildStopsResponse`）、カレンダーアイコンも `upcoming != null` でしか出ない
  /// ため、今はシート自体を開けない。実害が無いのでそのままにしてある。
  ///
  /// TODO(#202): `upcoming` を復活させるときに選択ベースへ直す。
  /// 研究棟だけ行き先で2節に分かれている作りも含めて見直しになる。
  void _showUpcomingSheet(
    BuildContext context,
    BusTimetable upcoming,
    List<BusStop> stopMaster,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.appColors.bottomSheet,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: context.appColors.textDisabled,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                '来週のダイヤ  ${upcoming.validFrom} 〜 ${upcoming.validTo}',
                style: const TextStyle(
                  color: AppColors.warning,
                  fontSize: 13,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 16),
              const Text('千歳駅発',
                  style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 12,
                      letterSpacing: 3)),
              const SizedBox(height: 8),
              ScheduleList(
                stopMaster: stopMaster,
                timetable: upcoming,
                stopId: 'chitose',
                destination: BusDestination.campus,
              ),
              const SizedBox(height: 16),
              const Text('南千歳発',
                  style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 12,
                      letterSpacing: 3)),
              const SizedBox(height: 8),
              ScheduleList(
                stopMaster: stopMaster,
                timetable: upcoming,
                stopId: 'minamiChitose',
                destination: BusDestination.campus,
              ),
              const SizedBox(height: 16),
              const Text('研究棟発 → 本部棟',
                  style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 12,
                      letterSpacing: 3)),
              const SizedBox(height: 8),
              ScheduleList(
                stopMaster: stopMaster,
                timetable: upcoming,
                stopId: 'kenkyuto',
                destination: BusDestination.campus,
              ),
              const SizedBox(height: 16),
              const Text('研究棟発 → 千歳駅',
                  style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 12,
                      letterSpacing: 3)),
              const SizedBox(height: 8),
              ScheduleList(
                stopMaster: stopMaster,
                timetable: upcoming,
                stopId: 'kenkyuto',
                destination: BusDestination.station,
              ),
              const SizedBox(height: 16),
              const Text('本部棟発',
                  style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 12,
                      letterSpacing: 3)),
              const SizedBox(height: 8),
              ScheduleList(
                stopMaster: stopMaster,
                timetable: upcoming,
                stopId: 'honbuto',
                destination: BusDestination.station,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 当日以外モードで表示するダイヤ種別（平日 / 土日祝）の切り替えボタン。
/// 全タブ共通の設定のため TabBarView の外（上部）に配置する。
class _DayTypeSelector extends ConsumerWidget {
  const _DayTypeSelector({required this.dayType});

  final DayType dayType;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: SegmentedButton<DayType>(
        segments: const [
          ButtonSegment(
            value: DayType.weekday,
            label: Text('平日ダイヤ'),
          ),
          ButtonSegment(
            value: DayType.weekendHoliday,
            label: Text('土日祝ダイヤ'),
          ),
        ],
        selected: {dayType},
        onSelectionChanged: (selection) =>
            ref.read(dayTypeOverrideProvider.notifier).state = selection.first,
        style: SegmentedButton.styleFrom(
          backgroundColor: context.appColors.surface,
          foregroundColor: context.appColors.textTertiary,
          selectedBackgroundColor: AppColors.primary,
          selectedForegroundColor: AppColors.onPrimary,
        ),
      ),
    );
  }
}

/// 当日以外モードで表示する期別（授業期 / 学休期）の切り替えボタン。
/// 学休期は美々空港線の直通便が大幅に減便されるため、平日/土日祝とは
/// 独立した軸として選択できるようにしている（Issue #132）。
class _SeasonSelector extends ConsumerWidget {
  const _SeasonSelector({required this.season});

  final SeasonType season;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: SegmentedButton<SeasonType>(
        segments: const [
          ButtonSegment(
            value: SeasonType.academic,
            label: Text('授業期'),
          ),
          ButtonSegment(
            value: SeasonType.vacation,
            label: Text('学休期'),
          ),
        ],
        selected: {season},
        onSelectionChanged: (selection) =>
            ref.read(seasonOverrideProvider.notifier).state = selection.first,
        style: SegmentedButton.styleFrom(
          backgroundColor: context.appColors.surface,
          foregroundColor: context.appColors.textTertiary,
          selectedBackgroundColor: AppColors.primary,
          selectedForegroundColor: AppColors.onPrimary,
        ),
      ),
    );
  }
}

/// この停留所から引ける便が1本も無いときの表示。
///
/// 「取得できていません」（[_StopNotFetched]）とは別物。取得はできている。
///
/// **バスが走っていないわけではない。** 便は「どこへ何時に着くか」の組で持つので、
/// 選んだ停留所の中に降り先が無いと引けない。停留所を1つだけ選ぶとこうなるので、
/// 次にどうすればよいかが分かる言い方にする。
class _StopHasNoBus extends StatelessWidget {
  const _StopHasNoBus();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.directions_bus_filled_outlined,
                color: context.appColors.textDisabled),
            const SizedBox(height: 12),
            Text(
              '到着地にする停留所をもう1つ選んでください。',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.appColors.textTertiary),
            ),
          ],
        ),
      ),
    );
  }
}

/// 節の見出し（`NEXT BUS` `TODAY'S SCHEDULE` `SCHEDULE`）の文字。
TextStyle _sectionTitleStyle(BuildContext context) => TextStyle(
      color: context.appColors.textTertiary,
      fontSize: 12,
      letterSpacing: 3,
    );

/// 節の見出しと、いま見ている停留所の名前を1行に並べる。
///
/// ## 経緯（#208 → #245）
///
/// **#208**: タブは短縮名（#207）でもさらに省略される。375px・上限の5タブでは
/// ラベルに 27px しか残らず、どれも1字＋`…` に切れるため、**タブだけでは見ている
/// 停留所を確定できない**。そこでここだけは幅が足りるとみて、`labelOf`
/// （= `shortLabel ?? label`）ではなく [BusStopLookup.officialLabelOf]（正式名）を
/// 常時出すことにした。
///
/// **#245（今回）**: #237 で拡大設定を実測すると、375px・1.15倍（Android の
/// 「大」）から正式名が `古泉循環器内科クリニ…` のように切れ始めていた。
/// `Expanded` + ellipsis は overflow を起こさず黙って切るので、#208 の
/// 「削らずに正式名を出す」という約束は**拡大設定を掛けた瞬間に破れていた**。
///
/// #208 が正式名を置いた理由（「タブだけでは停留所を確定できない」）自体は
/// 消えていない。ただし**常時出さなくても、タップで出せれば同じ用を足せる**
/// （`ArrivalRow` の #241 と同じ考え方）。そこで既定を短縮名
/// （[BusStopLookup.labelOf]）に戻し、**タップした場所でその場でトグル**して
/// 正式名に切り替える形にした。短縮名は最長5文字（`O･A入口`）なので、375px なら
/// 拡大設定を掛けてもまず溢れない。
///
/// **見出しと同じ行に置く。** 独立した1行にすると縦が 35px 増え、短い画面
/// （800x600）で `_StopTab` の Column が溢れる。この画面は NEXT BUS のサイズが
/// そのまま下を押す作りで縦の余裕がほとんど無い（#124）ため、行を増やさずに済む
/// 置き方を採る。**#245 でトグルにした後も、1行下や独立行には出さない**——
/// 縦を1pxも増やさないのは、#240（`_StopTab` の縦の溢れ）と縦の予算を奪い合う
/// ため。正式名を出した状態＋高倍率では入りきらないことがあり、そこは
/// ellipsis で切れてよい（タップして自分で開いた状態なので）。
///
/// 読み上げ（`Semantics`）はトグルの状態に関わらず**常に正式名**を渡す。画面には
/// 短縮名しか出ないタイミングがある以上、スクリーンリーダー利用者には最初から
/// 正式名で確定させておく（`_StopLabelPlaceholder`・`ArrivalRow` に前例がある）。
///
/// 使うのは**一番上の見出しだけ**。同じ停留所を2度書いても情報は増えない。
class _StopSectionHeader extends StatefulWidget {
  const _StopSectionHeader({
    required this.title,
    required this.stopId,
    required this.stopMaster,
  });

  final String title;

  /// 乗車地の停留所 ID
  final String stopId;

  /// 停留所の表示名の供給元（GAS の stopMaster）
  final List<BusStop> stopMaster;

  @override
  State<_StopSectionHeader> createState() => _StopSectionHeaderState();
}

class _StopSectionHeaderState extends State<_StopSectionHeader> {
  // タップで正式名を出すかどうか。既定は短縮名（false）
  bool _showOfficial = false;

  @override
  void didUpdateWidget(_StopSectionHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 停留所を切り替えたら開いた状態を持ち越さない。前の停留所で正式名を
    // 出したままだと、切り替え後もタップした覚えのない停留所の正式名が
    // 出て混乱する（`ArrivalRow` の #241 と同じ考え方）
    if (oldWidget.stopId != widget.stopId) {
      _showOfficial = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final shortLabel = widget.stopMaster.labelOf(widget.stopId);
    final officialLabel = widget.stopMaster.officialLabelOf(widget.stopId);
    final displayLabel = _showOfficial ? officialLabel : shortLabel;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        // **`title` に `Flexible` を付けないこと。** 名前側が `Expanded`（tight）
        // なので、両方 flex にすると自由幅が 1:1 に割られ、`title` が使い残した
        // ぶんは名前へ回らない。375px で名前に使える幅は **211px → 165.5px**
        // まで落ちる（実測）。`title` は 'NEXT BUS' / 'SCHEDULE' の固定文字列で、
        // 縮むべきは名前のほうではない
        Text(widget.title, style: _sectionTitleStyle(context)),
        const SizedBox(width: 12),
        // タップ領域は Expanded の中に GestureDetector を置く。右寄せテキスト
        // だが、当たり判定は Expanded の幅いっぱい（HitTestBehavior.opaque）
        // なので、文字の外側をタップしても反応する
        Expanded(
          // **`MergeSemantics` で自分だけの境界を作る。** `GestureDetector`
          // 単体では自分の tap アクションの SemanticsNode を独立させない
          // ——このヘッダーの左右に他の操作可能な要素が無いため、
          // 何もしないと tap アクションと正式名ラベルが
          // 一番近い既存の境界（`TabBarView` の各ページ＝`role: tabPanel`）
          // までそのまま這い上がり、'NEXT BUS' や
          // "TODAY'S SCHEDULE"・フッタの更新日時まで**1つの読み上げ単位に
          // 巻き込んで**しまう（`debugDumpSemanticsTree()` で実際に確認した。
          // その状態だとタブパネル全体のどこをダブルタップしても
          // このトグルが起動してしまい、'NEXT BUS' 等の周辺テキストも
          // 個別に読み上げられなくなる）。`MergeSemantics` は
          // `isSemanticBoundary = true` を立てるので、この Widget 自身を
          // 上への巻き込みから切り離せる
          child: MergeSemantics(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _showOfficial = !_showOfficial),
              child: Semantics(
                // 画面には短縮名しか出ないタイミングがあるので、読み上げは
                // トグルの状態に関わらず常に正式名で確定させる。子の Text
                // 自身の読み上げ（短縮名 or 正式名）は二重に読ませないよう
                // 除外する（`GestureDetector` は既定で子孫の `Semantics` を
                // 自分のタップ操作のノードにマージするため、ここで
                // `excludeSemantics` しないと二重に読まれる。`ArrivalRow`
                // の #241 で実際に確認済みの罠）
                label: '$officialLabel 発',
                excludeSemantics: true,
                child: Text(
                  '$displayLabel 発',
                  textAlign: TextAlign.end,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  style: TextStyle(
                    color: context.appColors.textPrimary,
                    fontSize: 14,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 停留所名が届くまでタブに置くもの。
class _StopLabelPlaceholder extends StatelessWidget {
  const _StopLabelPlaceholder();

  /// 既定の停留所の短縮名（`千歳駅` `南千歳` `研究棟` `本部棟`）の実測幅。
  /// 3文字 × タブのラベル 14sp = 42px。
  ///
  /// **見た目を整える値ではなく、並べ方を名前と揃えるための値。** タブは
  /// この幅で中央寄せ / 横並び / 縮小を決めるので、名前とずらすと画面幅に
  /// よっては名前が届いた瞬間に並べ方が切り替わり、星が跳ぶ。
  ///
  /// **等倍のときの値。**拡大設定を掛けた幅は [scaledWidth] で取る。
  static const width = 42.0;

  /// 文字を大きくする設定を掛けた場所取りの幅（#243）。
  ///
  /// **`_buildTab` の計測と、下の描画の両方がこれを呼ぶ。** 名前の側は
  /// `TextScaler` で伸びるのに場所取りが伸びないと、拡大時だけ両者がずれて
  /// [width] の注記にある「星が跳ぶ」が起きる。**2箇所に同じ計算を書くと
  /// 片方だけ直す事故が起きる**ので、定義はここ1つ。
  ///
  /// **`TextScaler.scale()` に 42.0 を渡してはいけない。** あれは
  /// 「素のフォントサイズ → 拡大後のフォントサイズ」を返すもので、任意の長さを
  /// 倍率で伸ばす関数ではない。**Android 14 以降の非線形スケーリングでは倍率が
  /// 元のフォントサイズごとに違う**（大きい字ほど伸びを抑える曲線）ため、
  /// `scale(42)` は 42pt の字の曲線を引いてしまい、実際のラベル（14px）に
  /// 掛かる倍率とは別物になる。**ラベル自身の字の大きさから比率を出すこと。**
  /// `TextScaler.linear` では一致するので、**テストは緑のまま実機だけずれる。**
  ///
  /// 比率の出し方自体は `core/theme/text_scale.dart` の [textScaleRatio] に
  /// まとめた（#240）。ここは元のフォントサイズ（`DefaultTextStyle`）を渡すだけ。
  static double scaledWidth(BuildContext context) {
    final fontSize = DefaultTextStyle.of(context).style.fontSize ?? 14.0;
    return width * textScaleRatio(context, baseFontSize: fontSize);
  }

  @override
  Widget build(BuildContext context) {
    // 画面に英字を出さないためのものなので、読み上げでも ID は読ませない。
    // ラベルが無いと「タブ 1/4」としか読まれず、待てば出ると分からない
    return Semantics(
      label: '読み込み中',
      child: Container(
        // 文字ではないので `TextScaler` は自動では効かない。名前と同じ幅で
        // 並べ方を決めている以上、描く側も手で合わせる（#243）
        width: scaledWidth(context),
        height: 10,
        decoration: BoxDecoration(
          color: context.appColors.textDisabled,
          borderRadius: BorderRadius.circular(5),
        ),
      ),
    );
  }
}

/// キャッシュにこの停留所の時刻が入っていないときの表示。
///
/// オフラインで停留所を足すと起きる。「時刻表データなし」（便が1本も無い）とは
/// 別物なので、取得すれば出ることが分かる言い方にする。
class _StopNotFetched extends StatelessWidget {
  // key はここでは受けない。呼び出し側（`_HomeScreenState`）は
  // `TabBarView` の並べ替え対応のため、`_wrapVerticalDragBarrier` の
  // 外側の `GestureDetector` に key を付ける（#260）
  const _StopNotFetched({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, color: context.appColors.textDisabled),
            const SizedBox(height: 12),
            Text(
              'このバス停の時刻はまだ取得できていません。\n通信できる場所で読み込んでください。',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.appColors.textTertiary),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: onRetry,
              child:
                  const Text('再試行', style: TextStyle(color: AppColors.primary)),
            ),
          ],
        ),
      ),
    );
  }
}

class _StopTab extends StatefulWidget {
  // key はここでは受けない。理由は [_StopNotFetched] の注記と同じ（#260）
  const _StopTab({
    required this.stopId,
    required this.stopMaster,
    required this.timetable,
    required this.updatedAt,
    this.dayType,
    this.season,
  });
  final String stopId;
  final List<BusStop> stopMaster;
  final BusTimetable timetable;
  final String updatedAt;
  final DayType? dayType;
  final SeasonType? season;

  /// この停留所から行ける行き先。途中の停留所は上下両方向のバスが通るため、
  /// 複数あるときは利用者に選ばせる。データから導くのでハードコードしない。
  List<String> get destinations {
    final seen = <String>{};
    for (final e in timetable.schedules) {
      if (e.boardingStopId == stopId) seen.add(e.destination);
    }
    // 表示順を安定させる（科技大 → 千歳駅）
    const order = [BusDestination.campus, BusDestination.station];
    final out = order.where(seen.contains).toList();
    for (final d in seen) {
      if (!out.contains(d)) out.add(d);
    }
    return out;
  }

  /// [destination] へ向かうとき、この停留所から見た終点の表示名。
  /// 「→ 本部棟」のように出す。
  ///
  /// 終点は便ごとの属性で、GAS が絞り込みの前に決めて返す（[BusEntry.terminusStopId]）。
  /// **到着地の末尾から導いてはいけない** — 選んだ停留所で変わってしまう。
  /// 古い供給元（未デプロイの GAS・#177 以前のキャッシュ）だけ末尾に頼る。
  ///
  /// 同じ行き先でも便によって終点が違うことはある（もりもと本店前から千歳駅方面
  /// なら、多くは千歳駅前止まりで長都行きだけ先へ続く）。見出しは1つなので
  /// 最初の便のものを使う。
  String terminusLabel(String destination) {
    for (final e in timetable.schedules) {
      if (e.boardingStopId != stopId || e.destination != destination) continue;
      final last = e.terminusStopId ?? e.arrivals.keys.lastOrNull;
      if (last == null) continue;
      return stopMaster.labelOf(last);
    }
    return destination;
  }

  @override
  State<_StopTab> createState() => _StopTabState();
}

class _StopTabState extends State<_StopTab> {
  String? _selected;

  /// 時刻表の全便を走査するので、build のたびに数えない
  late List<String> _destinations;

  @override
  void initState() {
    super.initState();
    _destinations = widget.destinations;
  }

  @override
  void didUpdateWidget(_StopTab old) {
    super.didUpdateWidget(old);
    if (!identical(old.timetable, widget.timetable) ||
        old.stopId != widget.stopId) {
      _destinations = widget.destinations;
    }
  }

  String get _destination =>
      _selected ?? _destinations.firstOrNull ?? BusDestination.campus;

  @override
  Widget build(BuildContext context) {
    // 行き先が1つも無いと、この下の IndexedStack はどちらも children が空になり、
    // 見出しだけが並んで下が無言の空白になる。ScheduleList 自体が作られないので
    // その中の「時刻表データなし」にも辿り着かない。
    //
    // 取得はできているので「取得できていません」でもない。**この停留所を通る
    // 便が1本も無い**という状態で、ここでだけ言える（#177）
    if (_destinations.isEmpty) return const _StopHasNoBus();

    // 拡大時の縦の溢れへの対処（#240）。まず (a) 余白を詰めて凌ぎ、
    // `kVerticalScrollThreshold` を超えたら (c) 画面ごとスクロールに切り替える
    // （下の `Expanded` を外し、`_buildScheduleSection` が入れ替える）。
    // 比率の出し方・しきい値・詰め方は `core/theme/text_scale.dart` にまとめてある
    // ——`_NextBusCard`（`next_bus_display.dart`）も同じしきい値を見ている。
    // **等倍（ratio <= 1.0）では useFullScroll は false・squeeze は 1.0 になり、
    // 何も変わらない。**
    // **判定は `core/theme/text_scale.dart` に置いてある。** ここで
    // `ratio > kVerticalScrollThreshold ? 1.0 : ...` と書くと、同じ判定を
    // 書き忘れた側（`_NextBusCard`）だけ詰まったままになる事故が起きる
    // （PR #252 のレビュー指摘で実際に踏んだ）
    final useFullScroll = useVerticalScroll(context);
    final squeeze = verticalSqueezeOf(context);

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(16, 16 * squeeze, 16, 0),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 現在は無効化中だが、再有効化したときにここへ出る
              WeekendWarningBanner(),
              SeasonNoticeBanner(),
            ],
          ),
        ),
        // 行き先が複数ある停留所だけ切り替えを出す。
        // 終点や片方向しか通らない停留所では選ぶものが無い
        if (_destinations.length > 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: SegmentedButton<String>(
              segments: [
                for (final d in _destinations)
                  ButtonSegment(
                    value: d,
                    label: Text('→ ${widget.terminusLabel(d)}'),
                  ),
              ],
              selected: {_destination},
              onSelectionChanged: (selection) =>
                  setState(() => _selected = selection.first),
              style: SegmentedButton.styleFrom(
                backgroundColor: context.appColors.surface,
                foregroundColor: context.appColors.textTertiary,
                selectedBackgroundColor: AppColors.primary,
                selectedForegroundColor: AppColors.onPrimary,
              ),
            ),
          ),
        Padding(
          padding: EdgeInsets.fromLTRB(16, 16 * squeeze, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 当日以外のダイヤ表示では NEXT BUS の概念がないため非表示
              if (widget.dayType == null) ...[
                _StopSectionHeader(
                  title: 'NEXT BUS',
                  stopId: widget.stopId,
                  stopMaster: widget.stopMaster,
                ),
                SizedBox(height: 8 * squeeze),
                // IndexedStack で両方向の NextBusDisplay を常時保持し、
                // 本部棟↔千歳駅切り替え時のレイアウトガタつきを防ぐ。
                //
                // **縦ドラッグバリアはここには無い。** かつてはここにも
                // `_wrapVerticalDragBarrier` を掛けていたが、(c) では外さ
                // ざるを得ず、`SegmentedButton` の周りや余白も含めて穴に
                // なっていた（#260）。いまは `TabBarView` の各 child の
                // 最外周でトップレベルの `_wrapVerticalDragBarrier`
                // を1つだけ掛けている——ヒットテスト順で内側のスクロール
                // 可能な要素が先に勝つので、ここに個別のバリアは要らない
                IndexedStack(
                  index: _destinations.indexOf(_destination).clamp(0, 99),
                  children: [
                    for (final d in _destinations)
                      NextBusDisplay(
                        timetable: widget.timetable,
                        stopId: widget.stopId,
                        stopMaster: widget.stopMaster,
                        destination: d,
                      ),
                  ],
                ),
                SizedBox(height: 24 * squeeze),
                // 乗車地は上の NEXT BUS 側に出ているので、ここでは繰り返さない
                Text("TODAY'S SCHEDULE", style: _sectionTitleStyle(context)),
              ] else
                // 当日以外のダイヤ表示では NEXT BUS ごと消える。一番上の見出しは
                // こちらになるので、乗車地はここに乗せる
                _StopSectionHeader(
                  title: 'SCHEDULE',
                  stopId: widget.stopId,
                  stopMaster: widget.stopMaster,
                ),
              SizedBox(height: 8 * squeeze),
            ],
          ),
        ),
        // IndexedStack で両 ScheduleList の State を常時保持することで
        // 本部棟↔千歳駅切り替え時にスクロール位置が独立して維持される。
        // PageStorageKey でスクロール位置を方向ごとに永続化する
        // （当日/ダイヤ種別ごとに独立させるため dayType もキーに含める）。
        _buildScheduleSection(expand: !useFullScroll),
        Padding(
          padding: EdgeInsets.fromLTRB(16, 8 * squeeze, 16, 16 * squeeze),
          child: Text(
            '更新: ${widget.updatedAt}',
            style:
                TextStyle(color: context.appColors.textDisabled, fontSize: 11),
          ),
        ),
      ],
    );

    if (!useFullScroll) return content;

    // (c) 拡大がしきい値を超えたときだけ画面ごとスクロールにする（#240）。
    // `ScheduleList` は自分の `LayoutBuilder` で有界/非有界を見て、非有界
    // （= `Expanded` を外した状態）なら自動で `ListView(shrinkWrap: true,
    // physics: NeverScrollableScrollPhysics)` に切り替わる作り
    // （`schedule_list.dart`・来週シートの `SingleChildScrollView` 直下と同じ
    // 経路）なので、ここでは `Expanded` を外して `SingleChildScrollView` で
    // 包むだけでよい。**(b) のように常時これを使うわけではない**——等倍を含む
    // 大半の経路は元の `Expanded` + `IndexedStack` のままで、スクロール位置の
    // 永続化（#177 以来の作り）を崩さない。
    //
    // **縦ドラッグバリアを外側に置くのが安全な理由（#260）。** この
    // `SingleChildScrollView` は `TabBarView` の各 child の最外周に掛けた
    // `_wrapVerticalDragBarrier`（このファイルのトップレベル関数）の子孫になる。
    // 中身が画面に収まっていれば `SingleChildScrollView` は
    // `setCanDrag(false)` で自分の drag recognizer を持たない——その場合は
    // 外側のバリアだけがアリーナに残り、縦ドラッグを吸って横スワイプ
    // （タブ切り替え）に取られるのを防ぐ。逆に中身が画面より大きければ
    // `SingleChildScrollView` 自身が recognizer を持ち、ヒットテスト順で
    // バリアより先にアリーナへ参加するため、こちらが勝って通常どおり
    // スクロールできる。**バリアをこの内側（`SingleChildScrollView` の
    // 中）に置くと、この二択が成り立たない**——中身が収まっている場面では
    // どこにもバリアが無い状態に戻ってしまう。
    return SingleChildScrollView(
      // **内側の `ScheduleList` の `ValueKey` と同じ粒度にする。**停留所だけを
      // キーにすると、行き先を切り替えても同じスクロール位置を共有してしまう
      // （PR #252 のレビュー指摘）。内側のリストは行き先・ダイヤ種別・季節ごとに
      // 位置を分けているので、外側だけ粗いと**切り替えた瞬間に外と内が別々の
      // 位置を主張する**。上のしきい値を超えたときだけ通る経路だが、揃えておく
      key: PageStorageKey('stopTabScroll_${widget.stopId}_${_destination}_'
          '${widget.dayType?.name ?? 'today'}_${widget.season?.name ?? ''}'),
      child: content,
    );
  }

  /// 時刻表リスト部分。`expand: true`（既定の等倍〜しきい値まで）では従来どおり
  /// `Expanded` + `IndexedStack` に収め、`expand: false`（(c) の全体スクロール時）
  /// では `Expanded` を外す——`SingleChildScrollView` の中で `Expanded` は使えない
  /// （unbounded な高さに対して flex を要求してエラーになる）。
  ///
  /// **縦ドラッグバリアはここには無い。** 上の NEXT BUS 側と同じ理由で、
  /// `TabBarView` の各 child の最外周に1つ掛けるだけで足りる（#260）。
  ///
  /// **`expand: false` では、`ScheduleList` の初回の `ensureVisible`（NEXT 行を
  /// 見える位置に出す）が走らない**（#266）。`ScheduleList` は
  /// `constraints.maxHeight.isFinite` で有界/非有界を見ており、`Expanded` を外すと
  /// 非有界（`_isBounded == false`）になって `initState` の postFrame が早期
  /// return する（`schedule_list.dart` 参照）。**あの早期 return はもともと
  /// 来週ダイヤの BottomSheet のために置いたもので、(c) を足したことで
  /// こちらも同じ経路に入るようになった。**
  ///
  /// **意図した挙動として受け入れている。** (c) では外側の
  /// `SingleChildScrollView` が先頭——すなわち NEXT BUS カード——から始まるので、
  /// NEXT の情報自体は最初から見えている。むしろ拡大している状態で開いた直後に
  /// リストの途中まで飛ぶほうが、いま何を見ているのか分かりにくい。
  /// **ここを変えるなら、外側のスクロールごと動かすことになる**ので、
  /// `ScheduleList` 側の早期 return を緩めるだけでは済まない。
  Widget _buildScheduleSection({required bool expand}) {
    final stack = IndexedStack(
      index: _destinations.indexOf(_destination).clamp(0, 99),
      children: [
        for (final d in _destinations)
          ScheduleList(
            key: ValueKey(
                '${widget.stopId}_${d}_${widget.dayType?.name ?? 'today'}_${widget.season?.name ?? ''}'),
            timetable: widget.timetable,
            stopId: widget.stopId,
            stopMaster: widget.stopMaster,
            destination: d,
            dayType: widget.dayType,
            season: widget.season,
          ),
      ],
    );
    return expand ? Expanded(child: stack) : stack;
  }
}
