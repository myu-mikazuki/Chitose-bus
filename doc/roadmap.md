# リリース予定

対応順の記録。**着手前にこの順序を確認し、変更したらここを更新する。**

最終更新: 2026-08-15

---

## 直近の順序

| 順 | Issue | 内容 | 状態 |
|----|-------|------|------|
| — | [#158](https://github.com/myu-mikazuki/Chitose-bus/issues/158) | 祝日ダイヤの判定 | ✅ 完了・デプロイ済み |
| — | [#165](https://github.com/myu-mikazuki/Chitose-bus/issues/165) | Google Play へのアップロードを自動化 | ✅ 完了（次回リリースで初回検証） |
| — | [#198](https://github.com/myu-mikazuki/Chitose-bus/issues/198) | CI の Flutter を `pubspec.yaml` で固定（PR #199） | ✅ 完了（develop） |
| — | [#177](https://github.com/myu-mikazuki/Chitose-bus/issues/177) | 任意のバス停を乗車地として選べるようにする | ✅ 完了（develop）・**v1.3.0 で出す** |
| 1 | [#201](https://github.com/myu-mikazuki/Chitose-bus/issues/201) | 旧形式でキャッシュが空に上書きされる | **v1.3.0 に入れる** |
| 2 | [#204](https://github.com/myu-mikazuki/Chitose-bus/issues/204) | 乗車地に選べる停留所数の上限（6件） | **v1.3.0 に入れる** |
| 3 | [#146](https://github.com/myu-mikazuki/Chitose-bus/issues/146) | portal の連絡掲示から増便情報を取得 | 次 |
| 4 | [#23](https://github.com/myu-mikazuki/Chitose-bus/issues/23) | 横長画面で NEXT BUS を左・SCHEDULE を右に | |
| 5 | [#140](https://github.com/myu-mikazuki/Chitose-bus/issues/140) | お気に入り登録を研究棟タブにも対応 | |
| 6 | ログ系 | [#109](https://github.com/myu-mikazuki/Chitose-bus/issues/109) ログ収集基盤 / PR #120 Crashlytics | |

#177 は develop まで入った（PR #200）。#146（臨時便）は応答に便を追加するため、
旧アプリへの影響を確認する必要がある。

## v1.3.0

### 出すもの

| Issue | 内容 |
|-------|------|
| [#177](https://github.com/myu-mikazuki/Chitose-bus/issues/177) | 任意のバス停を乗車地として選べるようにする（`?v=4`） |
| [#201](https://github.com/myu-mikazuki/Chitose-bus/issues/201) | 旧形式でキャッシュが空に上書きされるのを防ぐ |
| [#204](https://github.com/myu-mikazuki/Chitose-bus/issues/204) | 乗車地に選べる停留所数の上限を 6 にする |

**#201 と #204 を入れる理由**は、どちらも #177 が作った状況で初めて表に出るため。

- **#201** — v1.3.0 は `v=4` を使う最初のリリースで、**GAS のデプロイ順序に依存するのが初めて**。
  順序を誤るかデプロイをロールバックすると、空のキャッシュが保存されて `_keyStops` が入り、
  `loadLegacy()` も塞がって**再インストールするまで復旧しない**。#168 が未解決で
  デプロイが手作業である以上、保険を入れておく
- **#204** — 停留所を選べるのは v1.3.0 から。上限が無いと 30 タブまで増やせて実用にならない

### リリース時にやること

1. **本番 GAS をデプロイする**（`v=4` に対応していないと新アプリが動かない）
2. ストアへ提出する
3. リリースノートに「更新後の初回起動」について記載する — #177 以前のキャッシュは
   [移行用の経路](https://github.com/myu-mikazuki/Chitose-bus/issues/186)で読めるようにしてあるため、
   オフラインでも時刻表は出る

移行用の経路は **v1.4.0 で削除する**（[#186](https://github.com/myu-mikazuki/Chitose-bus/issues/186)）。

### 併せて確認すること

- [#165](https://github.com/myu-mikazuki/Chitose-bus/issues/165)（Google Play へのアップロード自動化）は
  **v1.3.0 が初回検証**。リリース作業と自動化そのものの検証が同時に走る
- [#198](https://github.com/myu-mikazuki/Chitose-bus/issues/198)（PR #199）で Flutter を `3.41.3` に
  固定した。リリースビルドもこの版になる
- #177 / #191 / #198 は `Closes` を書いてあるが、**develop へのマージでは閉じない**
  （デフォルトブランチが main のため）。v1.3.0 の develop → main で自動的に閉じる

### 後回しにしたもの

| Issue | 内容 | 後回しの理由 |
|-------|------|------------|
| [#172](https://github.com/myu-mikazuki/Chitose-bus/issues/172) | 旧キャッシュで学休期に授業期の便が出る | 「キャッシュデータを表示中」バナーが出るため誤解が緩和される |
| [#168](https://github.com/myu-mikazuki/Chitose-bus/issues/168) | `appsscript.json` に `webapp` 設定が無い | clasp でデプロイしない限り顕在化しない |
| [#171](https://github.com/myu-mikazuki/Chitose-bus/issues/171) | ソース側の表記統一 | 表示に影響しない |
| [#155](https://github.com/myu-mikazuki/Chitose-bus/issues/155) | `doc/spec.md` の GAS 章更新 | |
| [#117](https://github.com/myu-mikazuki/Chitose-bus/issues/117) | 利用規約 | #109 でログ収集を入れる際に同意事項が必要になるため、その段階で再検討 |
| [#140](https://github.com/myu-mikazuki/Chitose-bus/issues/140) | お気に入りの停留所を選択から外しても何も伝えない | #177 が作った隙間だが、実害は星が消えるだけ |
| [#190](https://github.com/myu-mikazuki/Chitose-bus/issues/190) | 通知キーが同時刻・別系統の便で衝突する | #177 以前からの不具合で回帰ではない |
| [#192](https://github.com/myu-mikazuki/Chitose-bus/issues/192) | HomeScreen の golden が無い | 開発側の投資。利用者への影響は無い |
| [#195](https://github.com/myu-mikazuki/Chitose-bus/issues/195) | `dart format` を CI に入れる | 同上 |
| [#202](https://github.com/myu-mikazuki/Chitose-bus/issues/202) | 「来週のダイヤ」シートが4停留所固定 | `upcoming` が常に null で、シート自体を開けない |
| #124 / #83 / #73 / #56 / #2 / #22 / #108 | | 未定 |

---

## 完了

### v1.2.0（2026-08-04 リリース・審査通過済み）

| Issue | 内容 |
|-------|------|
| #153 | GAS のスクリプトキャッシュを廃止 |
| #132 | 美々空港線の学休期ダイヤに対応 |
| #147 | 時刻表の有効期間表示を削除 |

### リリース不要（GAS のみ・デプロイ済み）

| Issue | 内容 |
|-------|------|
| #158 | 祝日ダイヤの判定（`v=2` でもサーバ側で絞り、リリース済みアプリにも反映） |
| #156 | GAS プロジェクトのアカウント移行 |
| #159 | 南千歳着の削除 → **誤りだったため PR #176 で差し戻し済み** |

### リリース不要（CI・ドキュメントのみ）

アプリのコード（`flutter_app/lib` / `flutter_app/test`）に変更が無いため、
リリースを待たず develop → main（マージコミット）で main にも入れられる。

| Issue | 内容 |
|-------|------|
| #198 | CI が `build_runner` で止まる → Flutter を `pubspec.yaml` で固定（PR #199） |

---

## 判断の指針

### GAS のみで完結する変更はリリース不要

時刻表データや運行日・期別の判定は `gas/Code.gs` にあり、**GAS を再デプロイすれば
リリース済みアプリを含む全ユーザーに即座に届く**。アプリのバイナリが変わらないなら
バージョンバンプもストア審査も不要。

`?v=` のスキーマバージョンにより、期別を知らない旧アプリにもサーバ側で絞り込んだ
結果を返せる（詳細は `doc/spec.md`）。**期限のある修正はこの経路を使う。**

### 逆に、アプリ側だけの修正はリリースを待つ

更新しないユーザーには永久に届かない。ユーザー影響が大きい修正は、可能な限り
GAS 側で吸収できないか先に検討する。

### 新しい `?v=` を使う変更は、GAS の本番デプロイをリリース時に行う

アプリが新しい `v` を送り始めるより先に GAS を本番デプロイしておく必要がある。
デプロイが後になると、新アプリが知らない形式（旧形式）を受け取って動かない。

**運用**（2026-08-10 決定）:

| 段階 | GAS |
|------|-----|
| 機能ブランチでの開発・検証 | **dev プロジェクト**を使う。`.dart_defines` を dev の staging に向ける |
| develop へのマージ | 本番デプロイはしない |
| **リリース時** | **本番へ手動デプロイ**してから、ストアへ提出する |

dev への反映は `clasp push --user dev` まで Claude が行い、デプロイのバージョン更新は
Apps Script の UI で人が行う（`appsscript.json` に `webapp` が無く clasp 経由の
バージョンが 404 になるため。[#168](https://github.com/myu-mikazuki/Chitose-bus/issues/168) が直るまでの運用）。

> リリース時のデプロイ漏れは**新アプリが全く動かない**事故になる。
> リリース手順の最初に置くこと。
