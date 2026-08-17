import 'package:flutter_test/flutter_test.dart';
import 'package:kagi_bus/domain/entities/bus_schedule.dart';

/// `labelOf` と `officialLabelOf` の出し分け（#208）。
///
/// 短縮名は全停留所に付いている（#207）ため、`labelOf` だけでは正式名を
/// 取り出せない。幅の足りる場所で停留所を確定させたい呼び出し側が
/// `officialLabelOf` を引く。
void main() {
  const master = [
    BusStop(id: 'chitose', label: '千歳駅前', shortLabel: '千歳駅'),
    // 正式名と同じなら GAS は shortLabel を返さない
    BusStop(id: 'honbuto', label: '本部棟'),
  ];

  group('BusStopLookup', () {
    test('labelOf は短縮名を優先する', () {
      expect(master.labelOf('chitose'), '千歳駅');
    });

    test('officialLabelOf は短縮名があっても正式名を返す', () {
      expect(master.officialLabelOf('chitose'), '千歳駅前');
    });

    test('短縮名が無ければ両方とも正式名', () {
      expect(master.labelOf('honbuto'), '本部棟');
      expect(master.officialLabelOf('honbuto'), '本部棟');
    });

    test('引けなければ ID をそのまま返す（両方）', () {
      // GAS から消えた停留所。null を返して呼び出し側に埋めさせない
      expect(master.labelOf('unknown'), 'unknown');
      expect(master.officialLabelOf('unknown'), 'unknown');
    });
  });
}
