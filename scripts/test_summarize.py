#!/usr/bin/env python3
"""`flutter test --machine` の JSON Lines を集計して短く出す（#261 / scripts/test.sh の内部部品）。

このファイル単体では使わない想定（`scripts/test.sh` から標準入力にパイプで渡される）。
ただし仕様は「`flutter test --machine` の JSON Lines を stdin から読む」だけなので、
手元で `flutter test --machine | python3 scripts/test_summarize.py` としても動く。

## イベントの読み方（判断の経緯）

`--machine` は Dart の `test` パッケージの JSON プロトコル
(https://dart.dev/go/test-docs/json_reporter.md) をそのまま吐く。ここで拾うのは：

- `testStart`: テスト ID → 名前・ソース位置（`test`/`testWidgets` の対応表を作る）
- `print` / `error`: そのテスト ID の「詳しい中身」。**どちらに乗るかがテストの
  種類で違う**（実機で確認済み）。
    - `testWidgets` の失敗（オーバーフロー・golden 不一致など、Flutter が
      `FlutterError.onError` で拾う例外）は、実体は `print` イベントに乗る
      （`══╡ EXCEPTION CAUGHT BY FLUTTER TEST FRAMEWORK ╞═...` のブロックごと）。
      同じテストの `error` イベントは `"Test failed. See exception logs above."`
      という空の要約しか持たない（`stackTrace` も空）。
    - 素の `test()`（`matcher` の `expect` が投げる普通の例外・ファイルの
      コンパイルエラー）は逆に `error` イベントの `error` / `stackTrace` に
      実体が乗り、`print` は出ない。
  → **両方拾わないと、テストの種類によって中身が消える。** print と error を
    テスト ID ごとに出現順で溜めておき、失敗時に両方まとめて出す。
- `testDone`: 合否の判定そのもの。
    - `hidden: true` は「`loading test/xxx.dart`」という擬似テスト（ファイル読み込み
      成功時のノイズ）。**ただしファイルの読み込み自体が失敗する（構文エラー等）と
      同じ擬似テストが `hidden: false` になり、`result: "error"` で本物の失敗として
      出てくる**（実機で確認済み）。素朴に「loading という名前を無視する」実装だと
      これを黙って捨ててしまうので、`hidden` フラグだけを判定に使う
    - `skipped: true` は skip（`result` 自体は `"success"` のまま）
    - それ以外は `result` が `"success"` / `"failure"` / `"error"`
- `done`: 全体の集計。`success` フィールドがあるが、**終了コードの判定には使わない**
  （`scripts/test.sh` 側で `flutter test` プロセス自身の終了コードをそのまま使う。
  こちらは JSON の解釈がどこかで漏れても嘘の 0 を返さないようにするため）。
  ここでは経過時間（`time`、開始からの累計ミリ秒）の取得にだけ使う

## 「成功しても print だけは残す」判断

当初は「成功したテストの `print`/`error` は問答無用で捨てる」実装だったが、
`test/tools/text_scale_probe_test.dart` の動作確認で問題が出た。**このテストは
何も assert しない**（`print` で計測結果を並べるだけの道具、ファイル冒頭の
コメント参照）。成功時に print を全部捨てる実装だと、**このテストは常に
出力ゼロになり、道具として機能しなくなる**。

素の `flutter test`（`--machine` を使わない既定の compact reporter）で確認すると、
print の中身はテストの合否に関わらずその場で出力に混ざる（進捗行 `00:00 +12: ...`
の間に生の print 行が割り込む形）。**この「print は合否に関係なく出る」という
既存の挙動をこのラッパーでも壊さないことにした。**

そのため成功したテストでも、`print` イベントが1件でもあれば
（`error` は成功時には基本出ないので対象外）中身を出す。ほとんどの
テストは何も print しないので、通常のスイート全体では実質的に
「緑なら集計だけ」のままになる（#261 が指している「475行問題」は
そもそも print を使わない通常のテストの話）。

## 標準入力に JSON 以外の行が混じる件

手元の環境では `flutter test --machine` の標準出力に `pub get` の
「Resolving dependencies...」のような非 JSON 行が混じる（`pub get` が
毎回律儀に依存関係を再解決するため）。JSON として読めない行は無視する
（緑のときにまで無関係なログを流したくない）。

ただし **JSON イベントを1行も観測できないまま入力が終わった**場合
（`pub get` 自体が失敗した、Dart VM がクラッシュした等、集計しようが無いケース）は、
黙って何も出さないくらいなら生ログを流したほうがまし、という判断で
非 JSON 行をそのまま出力する。

## 想定外の形をしたイベントを1件ごとに守る（PR #262 レビュー指摘）

`--machine` の出力は Dart の test パッケージのバージョンで細部が変わりうる
（このファイルの前半で書いた通り、実機で確認した挙動を前提に読んでいる）。
`testStart` に `test` キーが無い・`testDone` に `testID` が無いといった
**想定外の形のイベントが来ても、スクリプト全体を巻き込んで未捕捉例外で
落ちないようにする。** 集計目的のツールがトレースバックだけ返すのは、
「テスト結果を読みたい」という存在理由に反する。

- イベント1件の解釈（`dict` になったあとの `type` 別の処理）を丸ごと
  `try` で囲み、失敗したら**そのイベントだけ捨てて次に進む**
- 捨てた件数を最後に stderr へ1行警告として出す（スクリプト自身の警告がテスト結果と
  紛れないように stdout ではなく stderr にする）。黙って捨てると
  「テストが消えた」ことに気づけない
- **`flutter test` 自身が吐く別プロトコルの配列イベント**（`isinstance(event, dict)`
  が False になるもの）は元から無視する既知の対象なので、この警告には数えない
- `testDone` の分岐は、**カウンタを増やす前に描画関数を呼ぶ**順序にしてある。
  描画（`_render_failure`/`_render_output`）が想定外の形で例外を投げても、
  `passed`/`failed` の数字がずれない（描画に失敗した回だけ丸ごと捨てて
  カウンタも増やさない。イベント自体を無かったことにする）
"""

from __future__ import annotations

import json
import os
import sys


def _relativize(path: str) -> str:
    """`file://...` の絶対パスを、cwd から見た相対パスに縮める（読みやすさのため）。"""
    if path.startswith("file://"):
        path = path[len("file://") :]
    cwd = os.getcwd()
    if path.startswith(cwd + os.sep):
        path = os.path.relpath(path, cwd)
    return path


def _location_line(test: dict | None) -> str | None:
    if not test:
        return None
    # testWidgets は `root_url`/`root_line` に実際の呼び出し元（`test/xxx.dart`
    # の該当行）が入る。素の test() にはこれが無いので `url`/`line` にフォール
    # バックする（この場合は test() 自体の行になり、assert した行そのもの
    # ではないことがあるが、その行番号は下の stackTrace 側に出る）
    url = test.get("root_url") or test.get("url")
    line = test.get("root_line") or test.get("line")
    if url and line:
        return f"  {_relativize(url)}:{line}"
    return None


def _render_failure(test: dict | None, entries: list[tuple[str, object]]) -> str:
    name = test["name"] if test else "(name unknown)"
    lines = [f"FAILED: {name}"]

    loc = _location_line(test)
    if loc:
        lines.append(loc)

    for kind, payload in entries:
        if kind == "print":
            for line in payload.splitlines():
                lines.append(f"  {line}")
        else:  # "error" イベント。dict で {error, stackTrace} を持つ
            error_text = payload.get("error") or ""
            for line in error_text.splitlines():
                lines.append(f"  {line}")
            trace_text = payload.get("stackTrace") or ""
            if trace_text:
                for line in trace_text.splitlines():
                    lines.append(f"  {line}")

    return "\n".join(lines)


def _render_output(test: dict | None, entries: list[tuple[str, object]]) -> str | None:
    """成功したテストの print 出力をそのまま出す（probe テスト対策。上のドック
    コメント「成功しても print だけは残す」参照）。print が無ければ何も返さない
    （通常のテストは何も print しないので、これが多数派のまま）。"""
    print_lines = [line for kind, payload in entries if kind == "print" for line in payload.splitlines()]
    if not print_lines:
        return None

    name = test["name"] if test else "(name unknown)"
    lines = [f"{name}:"]
    lines.extend(f"  {line}" for line in print_lines)
    return "\n".join(lines)


def _handle_event(
    event: dict,
    tests: dict[int, dict],
    buffers: dict[int, list[tuple[str, object]]],
    blocks: list[str],
    counts: dict[str, int],
) -> int | None:
    """1件のイベントを解釈して `tests`/`buffers`/`blocks`/`counts` を更新する。

    想定外の形（キー欠落など）なら例外を投げて構わない。呼び出し側
    （`main`）がイベント単位で捕まえて次に進む。ここでは
    **カウンタ（`counts`）を増やすのは描画が成功したあと**にすること
    （ドックコメント「想定外の形をしたイベントを1件ごとに守る」参照）。
    戻り値は現在の `elapsed_ms`（更新しなければ None）。
    """
    elapsed_ms = event["time"] if "time" in event else None

    etype = event.get("type")
    if etype == "testStart":
        test = event["test"]
        tests[test["id"]] = test
        buffers[test["id"]] = []
    elif etype == "print":
        buffers.setdefault(event["testID"], []).append(("print", event["message"]))
    elif etype == "error":
        buffers.setdefault(event["testID"], []).append(("error", event))
    elif etype == "testDone":
        tid = event["testID"]
        entries = buffers.pop(tid, [])
        if event.get("hidden"):
            pass  # 読み込み成功のノイズ。中身も要らない
        elif event.get("skipped"):
            counts["skipped"] += 1
        elif event.get("result") == "success":
            # 先に描画（失敗しうる）、成功したらカウンタを増やす
            output = _render_output(tests.get(tid), entries)
            counts["passed"] += 1
            if output:
                blocks.append(output)
        else:
            # "failure"（assert 失敗）/ "error"（例外・コンパイルエラー等）
            failure_block = _render_failure(tests.get(tid), entries)
            counts["failed"] += 1
            blocks.append(failure_block)

    return elapsed_ms


def main() -> int:
    tests: dict[int, dict] = {}
    buffers: dict[int, list[tuple[str, object]]] = {}
    blocks: list[str] = []  # 失敗の詳細と、成功でも print があるものを出現順で溜める
    raw_fallback: list[str] = []
    counts = {"passed": 0, "failed": 0, "skipped": 0}
    elapsed_ms = 0
    saw_json = False
    discarded = 0  # 想定外の形で解釈を諦めたイベントの数

    for raw_line in sys.stdin:
        line = raw_line.rstrip("\n")
        if not line:
            continue
        try:
            event = json.loads(line)
        except ValueError:
            raw_fallback.append(line)
            continue

        saw_json = True
        if not isinstance(event, dict):
            # `flutter test` 自身が吐く別プロトコルのイベント（例:
            # `[{"event":"test.startedProcess",...}]`。配列で来る）。
            # `test` パッケージの JSON reporter とは別物なので無視する
            # （既知の無視対象。discarded には数えない）
            continue

        try:
            new_elapsed = _handle_event(event, tests, buffers, blocks, counts)
        except Exception:
            # 想定外の形のイベント。このイベントだけ捨てて次に進む
            # （集計・終了コードを壊さない。件数は最後にまとめて警告する）
            discarded += 1
            continue
        if new_elapsed is not None:
            elapsed_ms = new_elapsed

    if discarded:
        print(
            f"警告: 解釈できないイベントを {discarded} 件捨てました"
            "（--machine の出力形式が想定と違う可能性があります）。",
            file=sys.stderr,
        )

    if not saw_json:
        # JSON を1行も読めなかった＝ flutter test が集計以前に落ちている。
        # 情報を捨てるくらいなら生ログをそのまま出す
        for line in raw_fallback:
            print(line)
        return 0

    for block in blocks:
        print(block)
        print()

    parts = [f"{counts['passed']} passed"]
    if counts["failed"]:
        parts.append(f"{counts['failed']} failed")
    if counts["skipped"]:
        parts.append(f"{counts['skipped']} skipped")
    elapsed_s = round(elapsed_ms / 1000)
    print(f"{', '.join(parts)} ({elapsed_s}s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
