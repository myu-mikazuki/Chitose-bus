import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'data/services/widget_update_service.dart';
import 'presentation/views/home_screen.dart';
import 'presentation/viewmodels/schedule_viewmodel.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await WidgetUpdateService.instance.initialize();
  runApp(const ProviderScope(child: ChitoseBusApp()));
}

class ChitoseBusApp extends StatelessWidget {
  const ChitoseBusApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CIST シャトルバス',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00FF88),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF0A0A0A),
        fontFamily: 'monospace',
      ),
      home: const _AppLifecycleWrapper(child: HomeScreen()),
    );
  }
}

/// フォアグラウンド復帰時にウィジェットを更新する
class _AppLifecycleWrapper extends ConsumerStatefulWidget {
  const _AppLifecycleWrapper({required this.child});
  final Widget child;

  @override
  ConsumerState<_AppLifecycleWrapper> createState() =>
      _AppLifecycleWrapperState();
}

class _AppLifecycleWrapperState extends ConsumerState<_AppLifecycleWrapper> {
  late final AppLifecycleListener _lifecycleListener;

  @override
  void initState() {
    super.initState();
    _lifecycleListener = AppLifecycleListener(
      onResume: _onResume,
    );
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    super.dispose();
  }

  void _onResume() {
    // フォアグラウンド復帰時はキャッシュ済みデータでウィジェットを即時更新する。
    // 次のバスが変わっている場合は古い情報を一瞬表示する可能性があるが、
    // ScheduleViewModel の自動リフレッシュ（30分ごと）により間もなく正しい値に更新される。
    // 復帰のたびに API を叩かないことで不要なネットワーク通信を避ける設計。
    final scheduleState = ref.read(scheduleViewModelProvider);
    scheduleState.whenData((response) {
      WidgetUpdateService.instance.updateWidget(response.current).ignore();
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
