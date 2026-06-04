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
      'https://myu-mikazuki.github.io/Chitose-bus/privacy_policy.html';

  /// false を渡すと本番の広告ユニット ID を使用する（CI リリースビルド用）
  /// デフォルトは true（テスト用 ID）
  static const bool _useTestAds = bool.fromEnvironment(
    'USE_TEST_ADS',
    defaultValue: true,
  );

  /// AdMob バナー広告ユニット ID (Android)
  /// 本番: --dart-define=USE_TEST_ADS=false --dart-define=ADMOB_ANDROID_AD_UNIT_ID=ca-app-pub-xxx/xxx
  static const String admobAndroidAdUnitId = _useTestAds
      ? 'ca-app-pub-3940256099942544/6300978111'
      : String.fromEnvironment('ADMOB_ANDROID_AD_UNIT_ID');

  /// AdMob バナー広告ユニット ID (iOS)
  /// 本番: --dart-define=USE_TEST_ADS=false --dart-define=ADMOB_IOS_AD_UNIT_ID=ca-app-pub-xxx/xxx
  static const String admobIosAdUnitId = _useTestAds
      ? 'ca-app-pub-3940256099942544/2934735716'
      : String.fromEnvironment('ADMOB_IOS_AD_UNIT_ID');
}
