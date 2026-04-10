import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import '../../domain/services/error_reporter.dart';

class CrashlyticsErrorReporter implements ErrorReporter {
  const CrashlyticsErrorReporter(this._crashlytics);

  final FirebaseCrashlytics _crashlytics;

  @override
  Future<void> recordError(Object error, StackTrace stack) {
    return _crashlytics.recordError(error, stack);
  }
}
