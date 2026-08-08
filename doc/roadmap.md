# リリース予定

対応順の記録。**着手前にこの順序を確認し、変更したらここを更新する。**

最終更新: 2026-08-08

---

## 直近の順序

| 順 | Issue | 内容 | 状態 |
|----|-------|------|------|
| — | [#158](https://github.com/myu-mikazuki/Chitose-bus/issues/158) | 祝日ダイヤの判定 | ✅ 完了・デプロイ済み |
| — | [#165](https://github.com/myu-mikazuki/Chitose-bus/issues/165) | Google Play へのアップロードを自動化 | ✅ 完了（次回リリースで初回検証） |
| 1 | [#146](https://github.com/myu-mikazuki/Chitose-bus/issues/146) | portal の連絡掲示から増便情報を取得 | 次 |
| 2 | [#177](https://github.com/myu-mikazuki/Chitose-bus/issues/177) | 任意のバス停を乗車地として選べるようにする | 方針決定済み |
| 3 | [#23](https://github.com/myu-mikazuki/Chitose-bus/issues/23) | 横長画面で NEXT BUS を左・SCHEDULE を右に | |
| 4 | [#140](https://github.com/myu-mikazuki/Chitose-bus/issues/140) | お気に入り登録を研究棟タブにも対応 | |
| 5 | ログ系 | [#109](https://github.com/myu-mikazuki/Chitose-bus/issues/109) ログ収集基盤 / PR #120 Crashlytics | |

#177 は `?v=` を上げずに済む見込み（`stops` パラメータが無ければ現在の挙動を維持するため）。
一方 #146（臨時便）は応答に便を追加するため、旧アプリへの影響を確認する必要がある。
どちらも GAS 側だけで大半が完結し、アプリのリリースを待たずに進められる。

### 後回しにしたもの

| Issue | 内容 | 後回しの理由 |
|-------|------|------------|
| [#172](https://github.com/myu-mikazuki/Chitose-bus/issues/172) | 旧キャッシュで学休期に授業期の便が出る | 「キャッシュデータを表示中」バナーが出るため誤解が緩和される |
| [#168](https://github.com/myu-mikazuki/Chitose-bus/issues/168) | `appsscript.json` に `webapp` 設定が無い | clasp でデプロイしない限り顕在化しない |
| [#171](https://github.com/myu-mikazuki/Chitose-bus/issues/171) | ソース側の表記統一 | 表示に影響しない |
| [#155](https://github.com/myu-mikazuki/Chitose-bus/issues/155) | `doc/spec.md` の GAS 章更新 | |
| [#117](https://github.com/myu-mikazuki/Chitose-bus/issues/117) | 利用規約 | #109 でログ収集を入れる際に同意事項が必要になるため、その段階で再検討 |
| #124 / #83 / #73 / #56 / #2 / #22 / #108 | | 未定 |

---

## 完了

### v1.2.0（2026-08-04 リリース / App Store 審査中）

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
