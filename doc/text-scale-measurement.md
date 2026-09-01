# 文字拡大の限界を実フォントで測る

`doc/roadmap.md` と `flutter_app/test/widget/text_scaler_test.dart` に載っている
**「実フォント」の列を採り直すための手順**（#237 / #246）。

## なぜ実フォントで測り直すのか

**`flutter test` にはフォントが無い。** すべての文字が 1文字 = 1em の代替フォントで
描かれるため、**欧文と数字が実機よりかなり幅を食う**（`NEXT BUS` が 82px → 120px）。
CJK は全角固定なので停留所名そのものの幅はほぼ正しく、**ずれるのは欧文・数字を
含む行だけ**。

これを踏むと表が実機より厳しく出る。実際 **PR #244 では節の見出し（`◯◯ 発`）を
「375px では等倍でも切れている」と誤って読んでいた**。見出しは `NEXT BUS` と
同じ行にあるため影響がいちばん大きく、実フォントで測ると **1.15 まで持つ**。
この読み違いは v1.3.1 に何を入れるかの判断にも影響していた（PR #246 で訂正）。

> [!IMPORTANT]
> **「等倍でも壊れる」という結論も、代替フォントの結果だけで出さないこと。**
> #251 で同じ間違いを繰り返した——研究棟タブ（2方向ある停留所）が
> 375×667・等倍で 17px 縦に溢れる、という issue の報告は**代替フォント
> だけの現象**で、実フォント（Meiryo）では再現しなかった（375×667・等倍で
> overflow 無し。高さを 580px まで削って初めてわずかに溢れる程度の余裕
> だった）。原因は #244 とほぼ同じで、**代替フォントは欧文・数字をかなり
> 幅広く／高く描く**（ここでは NEXT BUS カードの時刻表示「09:00」・64px が
> 1行に収まらず折り返っていた）。
>
> **「拡大の限界」だけでなく「等倍で壊れるかどうか」の結論も、
> リリースの判断や production コードの修正に使う前に必ずここの手順で
> 実フォントに通すこと。** 代替フォントの overflow は「調べる価値がある
> 兆候」であって、それ単体では「実機で壊れる」の証拠にならない。

**リリースの範囲を決める材料にするなら、実フォントで測ること。**

## 1. TTF を用意する

`FontLoader` は **TTC（フォントコレクション）を受け付けない。** Windows の
`meiryo.ttc` などを使うときは、先頭のフォントを単体 TTF に切り出す。
ヘッダを読んで table record の offset を貼り直すだけ。

```python
import struct

src = '/mnt/c/Windows/Fonts/meiryo.ttc'   # TTC の場所は環境による
dst = '/tmp/jp.ttf'

d = open(src, 'rb').read()
tag, _maj, _min, n = struct.unpack('>4sHHI', d[:12])
assert tag == b'ttcf', tag
base = struct.unpack('>%dI' % n, d[12:12 + 4 * n])[0]

sfnt, num, sr, es, rs = struct.unpack('>IHHHH', d[base:base + 12])
recs = [struct.unpack('>4sIII', d[base + 12 + 16 * i:base + 28 + 16 * i])
        for i in range(num)]

cur = 12 + 16 * num
out, body = b'', b''
for t, cs, off, ln in recs:
    out += struct.pack('>4sIII', t, cs, cur, ln)
    body += d[off:off + ln] + b'\x00' * (-ln % 4)
    cur += ln + (-ln % 4)

open(dst, 'wb').write(struct.pack('>IHHHH', sfnt, num, sr, es, rs) + out + body)
```

**素の `.ttf` があるならこの手順は要らない。** 実機に近づけたいなら
Android は Noto Sans CJK JP、iOS はヒラギノ角ゴシックが本来の相手。

## 2. 走らせる

```
cd flutter_app
flutter test test/tools/text_scale_probe_test.dart --dart-define=JP_FONT=/tmp/jp.ttf
```

`JP_FONT` を渡さないと**丸ごと skip する**ので、CI では走らない。

## 3. 読む

このテストは**何も assert しない。** 倍率ごとに

- 節見出し（`◯◯ 発`）が**切れているか**（`Expanded` + ellipsis なので
  **溢れずに黙って切れる**＝ overflow では拾えない）
- 溢れた `RenderFlex` と、それがどのウィジェットの下にあるか（creator）

を並べるだけなので、**表は人が読み取って書き写す**。creator の
`_NextBusCard` / `_ScheduleRow` / `_StopTab` / `Tab` で場所が分かる。

倍率・画面の高さ・選ぶ停留所はファイル冒頭の定数で変える。
**縦の溢れ（#240）は実機並びの高さ（667px）でしか出ない**ので、
横だけ見たいときと2通り走らせている。

> [!IMPORTANT]
> **2方向ある停留所（`SegmentedButton` が出る）でも測ること（#251）。**
> `SegmentedButton` は縦を約40px 食うが、**#237 の実測も probe も長らく
> 乗車地を `koizumi`（1方向）でしか採っておらず、その分が勘定に入って
> いなかった。** #251 の調査時点では「研究棟タブが375×667・等倍でも
> 縦に溢れる」と疑ったが、これは実フォントで測り直すと再現しなかった
> （上の IMPORTANT 参照）——**ただし `koizumi` だけで測っていたこと
> 自体は本物の穴**なので、`SegmentedButton` の有無で条件が変わりうる
> 場所は引き続き両方測る。
>
> `text_scale_probe_test.dart` は `koizumi` に加えて `kenkyuto`（2方向）でも
> 375×667 を測るようになっている。**新しく画面のレイアウトを変えたときは
> 両方の結果を見ること**——1方向の停留所だけ見て判断すると、また同じ穴を
> 見逃す。

## 4. 表を直す

読み取った値を次の2箇所に書く。**片方だけ直さないこと。**

- `flutter_app/test/widget/text_scaler_test.dart` の冒頭
- `doc/roadmap.md` の「#237 で分かったこと」

**`text_scaler_test.dart` のテストが踏む倍率（`_deviceLimit` /
`_arrivalLimit` / `_tabLimit`）は代替フォントの値**なので、実フォントの列を
測り直しても変えない。あちらは「代替フォントで通る倍率」の下限を留めるもの。

> [!NOTE]
> 実フォントの列も**あくまで目安**。Meiryo と Noto Sans CJK / ヒラギノは
> 完全には一致しない。等倍で無傷かどうか、Android の「大」(1.15) と
> 「最大」(1.3) に届くかどうか、くらいの粒度で使うこと。
