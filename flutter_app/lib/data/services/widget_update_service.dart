import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import '../../domain/entities/bus_schedule.dart';

class WidgetUpdateService {
  WidgetUpdateService._();

  static final WidgetUpdateService instance = WidgetUpdateService._();

  static const String _appGroupId = 'group.com.example.chitoseBus';
  static const String _androidWidgetName = 'BusWidgetProvider';
  static const String _iosWidgetName = 'BusWidget';

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    await HomeWidget.setAppGroupId(_appGroupId);
    _initialized = true;
  }

  Future<void> updateWidget(BusTimetable timetable) async {
    try {
      await _doUpdateWidget(timetable);
    } catch (e, st) {
      debugPrint('[WidgetUpdateService] updateWidget failed: $e\n$st');
    }
  }

  Future<void> _doUpdateWidget(BusTimetable timetable) async {
    await initialize();

    // 最も早い次のバスを全方面から探す
    const directions = [
      BusDirection.fromChitose,
      BusDirection.fromMinamiChitose,
      BusDirection.fromKenkyutoToHonbuto,
      BusDirection.fromKenkyutoToStation,
      BusDirection.fromHonbuto,
    ];
    const directionLabels = {
      BusDirection.fromChitose: '千歳駅発',
      BusDirection.fromMinamiChitose: '南千歳発',
      BusDirection.fromKenkyutoToHonbuto: '研究棟発 → 本部棟',
      BusDirection.fromKenkyutoToStation: '研究棟発 → 千歳駅',
      BusDirection.fromHonbuto: '本部棟発',
    };

    BusEntry? primaryNext;
    String primaryLabel = '';

    final candidates = directions
        .map((d) => (bus: timetable.nextBus(d), label: directionLabels[d]!))
        .where((p) => p.bus != null)
        .toList();

    if (candidates.isNotEmpty) {
      candidates.sort(
        (a, b) => a.bus!.minutesFromNow().compareTo(b.bus!.minutesFromNow()),
      );
      primaryNext = candidates.first.bus;
      primaryLabel = candidates.first.label;
    }

    await HomeWidget.saveWidgetData<String>(
      'nextBusTime',
      primaryNext?.time ?? '--:--',
    );
    await HomeWidget.saveWidgetData<String>(
      'nextBusDirection',
      primaryNext != null ? primaryLabel : '本日の運行終了',
    );
    await HomeWidget.saveWidgetData<String>(
      'nextBusDestination',
      primaryNext?.destination ?? '',
    );
    await HomeWidget.saveWidgetData<String>(
      'updatedAt',
      DateTime.now().toUtc().toIso8601String(),
    );

    await HomeWidget.updateWidget(
      name: _androidWidgetName,
      iOSName: _iosWidgetName,
      qualifiedAndroidName: 'com.example.chitose_bus.$_androidWidgetName',
    );
  }
}
