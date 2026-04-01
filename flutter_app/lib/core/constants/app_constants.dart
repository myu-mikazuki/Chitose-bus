class AppConstants {
  AppConstants._();

  /// GAS WebアプリのデプロイURL
  /// --dart-define=GAS_ENDPOINT_URL=https://... で渡す（.dart_defines ファイル推奨）
  static const String gasEndpointUrl = String.fromEnvironment(
    'GAS_ENDPOINT_URL',
    defaultValue: '',
  );

  /// スケジュール自動更新間隔
  static const Duration scheduleRefreshInterval = Duration(minutes: 30);

  /// カウントダウン更新間隔
  static const Duration countdownRefreshInterval = Duration(seconds: 30);

  /// プライバシーポリシーの公開URL
  static const String privacyPolicyUrl =
      'https://yuzucchi-cist.github.io/Chitose-bus/privacy_policy.html';

  /// AdMob バナー広告ユニット ID (Android)
  /// --dart-define=ADMOB_ANDROID_AD_UNIT_ID=ca-app-pub-xxx/xxx で渡す
  /// デフォルトはテスト用ID
  static const String admobAndroidAdUnitId = String.fromEnvironment(
    'ADMOB_ANDROID_AD_UNIT_ID',
    defaultValue: 'ca-app-pub-3940256099942544/6300978111',
  );

  /// AdMob バナー広告ユニット ID (iOS)
  /// --dart-define=ADMOB_IOS_AD_UNIT_ID=ca-app-pub-xxx/xxx で渡す
  /// デフォルトはテスト用ID
  static const String admobIosAdUnitId = String.fromEnvironment(
    'ADMOB_IOS_AD_UNIT_ID',
    defaultValue: 'ca-app-pub-3940256099942544/2934735716',
  );
}
