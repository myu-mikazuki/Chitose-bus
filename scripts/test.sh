#!/bin/bash
# flutter test の出力を圧縮するラッパー（#261）
#
# いまの `flutter test` は1テストごとに1行出るので、緑でも 475行(*) 流れる。
# エージェント（Claude Code）がこれを読むとそのままトークンになるうえ、
# このリポジトリは1つの PR でテストを10回以上走らせる（限界値の二分探索など）
# ので効いてくる。緑の情報量はほぼゼロ（「全部通った」以外に読むものが無い）
# なので、緑なら集計だけ・赤なら中身を全部、という非対称な圧縮をする。
# (*) develop の現在値。中身は `doc/roadmap.md` 参照
#
#   $ scripts/test.sh
#   475 passed, 1 skipped (16s)
#
#   $ scripts/test.sh
#   FAILED: 文字拡大設定（TextScaler） ...
#     test/widget/text_scaler_test.dart:593
#     ══╡ EXCEPTION CAUGHT BY FLUTTER TEST FRAMEWORK ╞═...
#     ...
#   474 passed, 1 failed, 1 skipped (16s)
#
# ## なぜ `--machine` か（`--reporter compact/expanded/failures-only` ではなく）
#
# `flutter test --help -v` で見える reporter は
# compact / expanded / failures-only / github / json / silent。
# `failures-only` は一見近いが、**人間向けの整形済みテキスト**でしかなく、
# 「テスト名」「ファイル:行」「エラー本文」の境目をこちらで正規表現などで
# 割り出す必要がある。将来 Dart の test パッケージが表示を変えたら静かに壊れる。
#
# `--machine`（`--reporter json` も同じ JSON Lines プロトコルを吐く。
# https://dart.dev/go/test-docs/json_reporter.md）は `testStart` / `testDone` /
# `print` / `error` のようにイベントが構造化されていて、テスト名・合否・
# ソース位置（`root_url`/`root_line`。testWidgets の場合、代理実行される
# 実体ではなく呼び出し元の行が入る）がフィールドとして取れる。パースが
# 表示の揺れに引きずられない。集計ロジックの詳しい判断（`print` と `error`
# のどちらに失敗の中身が乗るかがテストの種類で違う、など）は
# scripts/test_summarize.py のドックコメントに書いた
#
# ## 引数の素通し方法
#
# `flutter test` に渡す引数（ファイル指定・`--plain-name`・`--dart-define` 等）を
# このスクリプトが個別に知る必要は無い。**そのまま `"$@"` で右から渡すだけ**
# にして、`--machine` だけこちらで追加する。オプションを1つずつ定義すると
# `flutter test` 側にオプションが増えるたびにここも直す羽目になる
#
#   scripts/test.sh test/widget/text_scaler_test.dart --plain-name "タブは倍率"
#   scripts/test.sh test/tools/text_scale_probe_test.dart --dart-define=JP_FONT=/path/to/font.ttf
#
# ## CI で使わない理由
#
# `.github/workflows/test.yml` は素の `flutter test` のまま変えていない。
# CI のログは人が後から（失敗した時だけ）読むもので、実行のたびに圧縮すると
# 逆に調査しづらくなる。圧縮が効くのはエージェントが同じセッション内で
# 何度も回すとき

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$REPO_ROOT/flutter_app" || exit 1

# `flutter test --machine` の標準出力を scripts/test_summarize.py にその場で
# パイプする。stderr も同じストリームに混ぜる（2>&1）: pub get が失敗する等
# JSON が1行も出ないまま終わる場合、その説明は stderr にしか出ないため。
# summarize 側は JSON として読めない行は無視し、JSON を1行も読めなかった
# ときだけ生ログとして出す（「集計できないので黙る」を避けるフォールバック）
flutter test --machine "$@" 2>&1 | python3 "$SCRIPT_DIR/test_summarize.py"

# パイプの左右それぞれの終了コードを見る。
# **返す終了コードは `flutter test` 自身のもの（PIPESTATUS[0]）。**
# summarize 側（Python）の判定結果ではなく、こちらを正とする。JSON の解釈が
# どこかで漏れて summarize が「全部 passed」と誤読しても、`flutter test` が
# 非0で終わっていれば呼び出し側（CI 代わりに使うスクリプト等）はちゃんと
# 赤だと分かる。
# `PIPESTATUS` は参照した時点の直前コマンドで毎回上書きされるので、
# 1行で配列ごと退避してから中身を取り出す（2行に分けると1行目の代入自体が
# 単発コマンド扱いになり、2行目で読む頃には `PIPESTATUS[1]` が消えている）
pipe_status=("${PIPESTATUS[@]}")
flutter_exit="${pipe_status[0]}"
summarize_exit="${pipe_status[1]}"

if [ "$summarize_exit" -ne 0 ]; then
  echo "[scripts/test.sh] 集計スクリプト(test_summarize.py)が異常終了しました(exit $summarize_exit)。上の出力が不完全な可能性があります。" >&2
fi

exit "$flutter_exit"
