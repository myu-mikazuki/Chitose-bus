# テスト実行ガイド

## ユニット・ウィジェットテスト

```bash
cd flutter_app
flutter test
```

Goldenテストのみ実行する場合:

```bash
flutter test test/widget/golden/
```

## Goldenスナップショットの更新

UIを意図的に変更した際は、Goldenファイルを更新してからコミットする:

```bash
flutter test --update-goldens test/widget/golden/
```

更新後は `git diff test/widget/golden/goldens/` で画像差分を確認してからコミットすること。

> **注意**: Goldenテストはフォントレンダリングに依存するため、Linux / macOS / CI 間で実行環境が
> 異なると False Failure が発生する場合があります。Golden スナップショットは必ず CI と同じ
> 環境（`ubuntu-latest` 相当）で生成・更新してください。

## 統合テスト

統合テストは実デバイス・エミュレータ、またはデスクトップ環境が必要。

```bash
# 接続済みデバイスを確認
flutter devices

# デバイスを指定して実行
flutter test integration_test/app_test.dart -d <device_id>

# Linux デスクトップで実行（CI向け）
flutter test integration_test/app_test.dart -d linux
```

## タイマーを含むテスト（fake_async）

`CountdownNotifier` や `ScheduleViewModel` の自動リフレッシュタイマーをテストする場合は
`fake_async` パッケージを使うと実時間を待たずにタイマーを進められる:

```dart
import 'package:fake_async/fake_async.dart';

test('タイマーが一定間隔で発火する', () {
  fakeAsync((async) {
    // テスト対象をセットアップ
    final notifier = CountdownNotifier();
    final initialTime = notifier.state;

    // タイマーを10秒進める
    async.elapse(const Duration(seconds: 10));

    // タイマー発火後の状態を検証
    expect(notifier.state, isNot(equals(initialTime)));

    notifier.dispose();
  });
});
```

`pubspec.yaml` の `dev_dependencies` に追加が必要:

```yaml
dev_dependencies:
  fake_async: ^1.3.1
```

## CI

push / pull_request 時に GitHub Actions でウィジェットテストが自動実行される
（`.github/workflows/test.yml`）。

ワークフローの内容:

```yaml
name: Flutter Tests
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
          cache: true
      - name: Install dependencies
        run: flutter pub get
        working-directory: flutter_app
      - name: Run unit & widget tests
        run: flutter test
        working-directory: flutter_app
```
