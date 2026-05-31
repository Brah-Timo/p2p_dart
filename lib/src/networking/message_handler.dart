/// Inbound message dispatch and middleware chain.
library;

import 'dart:async';

import '../core/enums.dart';
import '../utils/logger.dart';
import 'message.dart';

// ─── Message Middleware ───────────────────────────────────────────────────────

/// A function that processes an inbound [P2PMessage] and optionally passes it
/// to the next handler.
typedef MessageMiddleware = Future<void> Function(
  P2PMessage message,
  Future<void> Function() next,
);

// ─── Type Handler ─────────────────────────────────────────────────────────────

/// A strongly-typed handler for a specific [MessageType].
typedef TypedMessageHandler = Future<void> Function(P2PMessage message);

// ─── Message Handler ─────────────────────────────────────────────────────────

/// Routes inbound [P2PMessage]s through a middleware chain and then to
/// per-type handlers.
///
/// Usage:
/// ```dart
/// final handler = MessageHandler();
///
/// // Add global middleware (e.g., logging, authentication).
/// handler.use((msg, next) async {
///   print('Received: ${msg.type}');
///   await next();
/// });
///
/// // Register a typed handler.
/// handler.on(MessageType.data, (msg) async {
///   print('Data from ${msg.senderId}: ${msg.payload}');
/// });
///
/// // Dispatch an incoming message.
/// await handler.dispatch(incomingMessage);
/// ```
class MessageHandler {
  final List<MessageMiddleware> _middlewares = [];
  final Map<MessageType, List<TypedMessageHandler>> _handlers = {};
  final P2PLogger _log;

  /// Creates a [MessageHandler].
  MessageHandler({P2PLogger? logger})
      : _log = logger ?? P2PLogger('MessageHandler');

  // ─── Middleware ──────────────────────────────────────────────────────────

  /// Appends [middleware] to the chain.
  void use(MessageMiddleware middleware) {
    _middlewares.add(middleware);
  }

  // ─── Typed Handlers ───────────────────────────────────────────────────────

  /// Registers [handler] for messages of [type].
  void on(MessageType type, TypedMessageHandler handler) {
    _handlers.putIfAbsent(type, () => []).add(handler);
  }

  /// Removes all handlers for [type].
  void off(MessageType type) => _handlers.remove(type);

  // ─── Dispatch ────────────────────────────────────────────────────────────

  /// Dispatches [message] through the middleware chain and then to type-handlers.
  Future<void> dispatch(P2PMessage message) async {
    try {
      await _runMiddleware(message, 0, () => _callHandlers(message));
    } catch (e, st) {
      _log.error('Unhandled error dispatching ${message.type}: $e\n$st');
    }
  }

  // ─── Private ─────────────────────────────────────────────────────────────

  Future<void> _runMiddleware(
    P2PMessage message,
    int index,
    Future<void> Function() finalHandler,
  ) async {
    if (index >= _middlewares.length) {
      await finalHandler();
      return;
    }

    await _middlewares[index](
      message,
      () => _runMiddleware(message, index + 1, finalHandler),
    );
  }

  Future<void> _callHandlers(P2PMessage message) async {
    final handlers = _handlers[message.type];
    if (handlers == null || handlers.isEmpty) {
      _log.debug('No handler registered for ${message.type}');
      return;
    }

    await Future.wait(
      handlers.map((h) => h(message)),
      eagerError: false,
    );
  }
}
