import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_colors_theme.dart';
import '../../domain/entities/bus_schedule.dart';
import '../../domain/entities/stop_selection.dart';
import '../viewmodels/schedule_viewmodel.dart';
import '../viewmodels/stop_selection_viewmodel.dart';

/// タブに出す停留所を選ぶ画面（Issue #177）。
///
/// 選択肢は GAS の `stopMaster` から取る。アプリ側に対応表を持つと、
/// 停留所が増えるたびにリリースが必要になる。
///
/// **編集は下書きで、「適用」を押すまで反映しない。** 反映すると時刻表を
/// 取り直すため、1操作ごとに適用すると停留所を3つ足すだけで3往復する。
class StopSettingsScreen extends ConsumerStatefulWidget {
  const StopSettingsScreen({super.key});

  @override
  ConsumerState<StopSettingsScreen> createState() => _StopSettingsScreenState();
}

class _StopSettingsScreenState extends ConsumerState<StopSettingsScreen> {
  /// 編集中の並び。表示は常にこれを見る
  List<String>? _draft;

  /// 適用済みの並び。「適用」を出すかどうかの判定に使う
  List<String>? _applied;

  /// 直近に受け取った停留所マスタ。
  ///
  /// 適用すると [scheduleViewModelProvider] が作り直されて一時的に loading に
  /// なる。そのたびに選択肢が消えると操作できないため保持する。
  List<BusStop> _master = const [];

  List<String> get _selected => _draft ?? const [];

  bool get _dirty {
    final applied = _applied;
    if (applied == null) return false;
    if (applied.length != _selected.length) return true;
    for (var i = 0; i < applied.length; i++) {
      if (applied[i] != _selected[i]) return true;
    }
    return false;
  }

  /// 追加できる停留所。路線の並び（stopMaster の順）で出す。
  ///
  /// ラピダス前のように乗車地として使えない停留所は [BusStop.boardable] が
  /// false で、選択肢に出さない。
  List<BusStop> get _candidates => _master
      .where((s) => s.boardable && !_selected.contains(s.id))
      .toList(growable: false);

  /// 上限に達しているか。達したら「追加する」の一覧を出さない（#204）
  bool get _full => _selected.length >= StopSelection.maxStops;

  void _edit(List<String> next) => setState(() => _draft = next);

  void _add(String id) {
    // 一覧を出さないので通常は押せないが、判定はここにも置く
    if (_full) return;
    _edit([..._selected, id]);
  }

  void _remove(String id) =>
      _edit(_selected.where((e) => e != id).toList(growable: false));

  void _reorder(int oldIndex, int newIndex) {
    final next = [..._selected];
    // ReorderableListView は「取り除く前」の位置で newIndex を渡してくる
    if (newIndex > oldIndex) newIndex -= 1;
    next.insert(newIndex, next.removeAt(oldIndex));
    _edit(next);
  }

  /// 保存が終わるまで閉じない。**待たずに閉じると、保存に失敗しても
  /// 適用されたように見え**、次の起動で元に戻る理由が分からなくなる。
  Future<void> _apply() async {
    final next = _selected;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    try {
      await ref
          .read(stopSelectionProvider.notifier)
          .select(StopSelection(stopIds: next));
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('バス停の設定を保存できませんでした')),
      );
      return;
    }
    if (!mounted) return;
    setState(() => _applied = next);
    navigator.pop();
  }

  /// 適用せずに戻ろうとしたときの確認。
  /// 下書きのまま消えると、操作した分が黙って無かったことになる。
  Future<bool> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.appColors.surface,
        title:
            const Text('変更を破棄しますか', style: TextStyle(color: AppColors.primary)),
        content: Text(
          'バス停の変更はまだ適用されていません。',
          style: TextStyle(color: ctx.appColors.textPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child:
                const Text('編集に戻る', style: TextStyle(color: AppColors.primary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('破棄', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    return discard ?? false;
  }

  @override
  Widget build(BuildContext context) {
    // 最初に解決した選択を編集の起点にする。以降は _draft が正とする
    final saved = ref.watch(stopSelectionProvider).valueOrNull?.stopIds;
    if (_draft == null && saved != null) {
      _draft = saved;
      _applied = saved;
    }

    final master =
        ref.watch(scheduleViewModelProvider).valueOrNull?.data.stopMaster;
    if (master != null && master.isNotEmpty) _master = master;

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        // await をまたいで context を触らないよう先に取っておく
        final navigator = Navigator.of(context);
        if (await _confirmDiscard() && mounted) navigator.pop();
      },
      child: Scaffold(
        backgroundColor: context.appColors.background,
        appBar: AppBar(
          backgroundColor: context.appColors.background,
          foregroundColor: AppColors.primary,
          title: const Text(
            'バス停',
            style: TextStyle(
              color: AppColors.primary,
              fontSize: 16,
              letterSpacing: 2,
            ),
          ),
          actions: [
            TextButton(
              onPressed: _dirty ? _apply : null,
              child: Text(
                '適用',
                style: TextStyle(
                  color: _dirty
                      ? AppColors.primary
                      : context.appColors.textDisabled,
                  letterSpacing: 1,
                ),
              ),
            ),
          ],
        ),
        // 選択が読めるまで操作させない。空の状態で追加を押すと、
        // あとから解決した選択を上書きしてしまう
        body: _draft == null
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.primary))
            : _master.isEmpty
                ? const _MasterUnavailable()
                : _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final candidates = _candidates;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_dirty) ...[
          const _PendingNotice(),
          const SizedBox(height: 16),
        ],
        // 上限は先に見せる。押せなくなってから知らせると、なぜ足せないのか
        // 分からないまま「追加する」を探すことになる
        _SectionHeader(
          label: 'タブに表示する（${_selected.length} / ${StopSelection.maxStops}）',
        ),
        Text(
          '長押しで並べ替えられます。並びがそのままタブの並びになります。',
          style: TextStyle(color: context.appColors.textTertiary, fontSize: 12),
        ),
        const SizedBox(height: 8),
        _SectionCard(
          child: ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            onReorder: _reorder,
            children: [
              for (final id in _selected)
                _SelectedStopTile(
                  // ReorderableListView は子ごとに一意な key を要求する
                  key: ValueKey(id),
                  stop: _master.byId(id),
                  id: id,
                  // 0個になると時刻表が全く出せなくなるため最後の1つは外せない
                  onRemove: _selected.length > 1 ? () => _remove(id) : null,
                ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const _SectionHeader(label: '追加する'),
        const SizedBox(height: 8),
        // 候補が無いことを先に見る。上限と同時に成り立つとき「外せば足せる」は
        // 嘘になる（足す先がもう無い）
        if (candidates.isEmpty)
          Text(
            '追加できる停留所はありません',
            style:
                TextStyle(color: context.appColors.textTertiary, fontSize: 12),
          )
        else if (_full)
          Text(
            'タブは ${StopSelection.maxStops} 件までです。'
            '別の停留所にするには、上のどれかを外してください。',
            style:
                TextStyle(color: context.appColors.textTertiary, fontSize: 12),
          )
        else
          _SectionCard(
            child: Column(
              children: [
                for (var i = 0; i < candidates.length; i++) ...[
                  if (i > 0)
                    Divider(height: 1, color: context.appColors.border),
                  ListTile(
                    title: Text(
                      candidates[i].label,
                      style: TextStyle(color: context.appColors.textPrimary),
                    ),
                    trailing: const Icon(Icons.add, color: AppColors.primary),
                    onTap: () => _add(candidates[i].id),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

/// 未適用の変更があることを伝える。
/// 「適用」がヘッダにしか無いと、変更が保存されたと思われかねない。
class _PendingNotice extends StatelessWidget {
  const _PendingNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.warning),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.edit_outlined, color: AppColors.warning, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '「適用」を押すと時刻表を取り直します',
              style:
                  TextStyle(color: context.appColors.textPrimary, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

/// stopMaster がまだ届いていないときの表示。
///
/// 停留所の名前の供給元は GAS だけなので、一度も取得できていないと選べない。
class _MasterUnavailable extends StatelessWidget {
  const _MasterUnavailable();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          '停留所の一覧を取得できていません。\n通信できる場所で時刻表を読み込んでから開いてください。',
          textAlign: TextAlign.center,
          style: TextStyle(color: context.appColors.textTertiary),
        ),
      ),
    );
  }
}

class _SelectedStopTile extends StatelessWidget {
  const _SelectedStopTile({
    super.key,
    required this.stop,
    required this.id,
    required this.onRemove,
  });

  /// stopMaster に無い ID（GAS から消えた停留所）は null になる
  final BusStop? stop;
  final String id;

  /// null なら外せない
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final label = stop?.label ?? id;
    // タブでは短縮名が出るので、正式名と違うときだけ添える
    final short = stop?.shortLabel;

    return ListTile(
      leading: Icon(Icons.drag_handle, color: context.appColors.textDisabled),
      title: Text(
        label,
        style: TextStyle(color: context.appColors.textPrimary),
      ),
      subtitle: short == null
          ? null
          : Text(
              'タブ表示: $short',
              style: TextStyle(
                  color: context.appColors.textTertiary, fontSize: 12),
            ),
      trailing: IconButton(
        icon: const Icon(Icons.remove_circle_outline),
        color:
            onRemove == null ? context.appColors.textDisabled : AppColors.error,
        tooltip: onRemove == null ? '最後の1つは外せません' : '外す',
        onPressed: onRemove,
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.primary,
          fontSize: 12,
          letterSpacing: 2,
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: context.appColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: child,
    );
  }
}
