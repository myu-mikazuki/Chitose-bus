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
}
