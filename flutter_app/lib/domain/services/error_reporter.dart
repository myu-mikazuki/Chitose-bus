abstract class ErrorReporter {
  Future<void> recordError(Object error, StackTrace stack);
}
