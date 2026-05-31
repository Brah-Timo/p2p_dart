/// Structured logger for p2p_dart.
library;

import 'dart:developer' as developer;

import '../core/enums.dart';

// ─── P2P Logger ───────────────────────────────────────────────────────────────

/// A structured, levelled logger for p2p_dart components.
///
/// By default writes to `dart:developer` (visible in DevTools).
/// Provide [onLog] to redirect output to your own logging framework.
class P2PLogger {
  /// Component name (e.g. `'DHT'`, `'WebRTC'`).
  final String component;

  /// Whether to emit TRACE and DEBUG messages.
  final bool verbose;

  /// Optional custom log sink.
  final void Function(String level, String component, String message)? onLog;

  /// Creates a [P2PLogger].
  P2PLogger(
    this.component, {
    this.verbose = false,
    this.onLog,
  });

  // ─── Log Methods ──────────────────────────────────────────────────────────

  /// Emits a TRACE message (only when [verbose] is `true`).
  void trace(String message) => _emit(LogLevel.trace, message);

  /// Emits a DEBUG message.
  void debug(String message) => _emit(LogLevel.debug, message);

  /// Emits an INFO message.
  void info(String message) => _emit(LogLevel.info, message);

  /// Emits a WARNING message.
  void warning(String message) => _emit(LogLevel.warning, message);

  /// Emits an ERROR message.
  void error(String message) => _emit(LogLevel.error, message);

  /// Emits a CRITICAL message.
  void critical(String message) => _emit(LogLevel.critical, message);

  // ─── Private ────────────────────────────────────────────────────────────

  void _emit(LogLevel level, String message) {
    if (!_shouldEmit(level)) return;

    final levelName = level.name.toUpperCase().padRight(8);
    final formatted = '[$levelName] [$component] $message';

    final sink = onLog;
    if (sink != null) {
      sink(level.name, component, message);
      return;
    }

    developer.log(
      formatted,
      name: 'p2p_dart.$component',
      level: _dartLevel(level),
      time: DateTime.now(),
    );
  }

  bool _shouldEmit(LogLevel level) {
    if (level == LogLevel.trace || level == LogLevel.debug) return verbose;
    return true;
  }

  int _dartLevel(LogLevel level) => switch (level) {
        LogLevel.trace => 300,
        LogLevel.debug => 500,
        LogLevel.info => 800,
        LogLevel.warning => 900,
        LogLevel.error => 1000,
        LogLevel.critical => 1200,
        LogLevel.off => 0,
      };
}
