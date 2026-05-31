/// A type-safe synchronous event bus.
library;

import 'dart:async';

import 'events.dart';

// ─── Event Handler ────────────────────────────────────────────────────────────

/// A handler function for events of type [T].
typedef EventHandler<T extends P2PEvent> = void Function(T event);

// ─── Event Bus ────────────────────────────────────────────────────────────────

/// A lightweight, type-safe publish/subscribe event bus.
///
/// All events extend [P2PEvent].  Handlers are called synchronously in the
/// order they were registered.
///
/// ## Usage
///
/// ```dart
/// final bus = EventBus();
///
/// // Subscribe
/// bus.on<PeerConnectedEvent>((event) {
///   print('Connected: ${event.peerId}');
/// });
///
/// // Unsubscribe by storing the subscription
/// final sub = bus.on<MessageReceivedEvent>((e) => handleMessage(e));
/// sub.cancel();
///
/// // One-shot
/// bus.once<NodeStartedEvent>((e) => print('Node started once'));
///
/// // Emit
/// bus.emit(PeerConnectedEvent(peerId: 'abc', channel: ch));
/// ```
class EventBus {
  final Map<Type, List<_Subscription>> _subscriptions = {};

  // ─── Subscription ─────────────────────────────────────────────────────────

  /// Subscribes [handler] to events of type [T].
  ///
  /// Returns an [EventSubscription] that can be [EventSubscription.cancel]led.
  EventSubscription on<T extends P2PEvent>(EventHandler<T> handler) {
    final bucket = _subscriptions.putIfAbsent(T, () => []);
    final sub = _Subscription<T>(handler, bus: this);
    bucket.add(sub);
    return sub;
  }

  /// Subscribes [handler] and automatically unsubscribes after the first event.
  EventSubscription once<T extends P2PEvent>(EventHandler<T> handler) {
    late EventSubscription sub;
    sub = on<T>((event) {
      handler(event);
      sub.cancel();
    });
    return sub;
  }

  /// Returns a [Future] that completes with the next event of type [T].
  Future<T> next<T extends P2PEvent>() {
    final completer = Completer<T>();
    once<T>(completer.complete);
    return completer.future;
  }

  /// Returns a [Stream] of events of type [T].
  ///
  /// The returned stream is a broadcast stream that delivers every matching
  /// event synchronously.  Cancel the returned [StreamSubscription] when done.
  Stream<T> stream<T extends P2PEvent>() {
    // Use a broadcast controller so add() is never silently dropped due to
    // back-pressure pausing that a single-subscription controller applies.
    // ignore: close_sinks
    final controller = StreamController<T>.broadcast(sync: true);

    final sub = on<T>(controller.add);

    // When the last listener unsubscribes, detach the bus subscription so we
    // stop routing events.  Do NOT close the controller here — closing it
    // would prevent any further add() calls on an already-cancelled sub.
    controller.onCancel = sub.cancel;

    return controller.stream;
  }

  // ─── Emission ─────────────────────────────────────────────────────────────

  /// Emits [event] to all handlers registered for its runtime type.
  void emit<T extends P2PEvent>(T event) {
    final handlers = _subscriptions[event.runtimeType];
    if (handlers == null || handlers.isEmpty) return;

    // Take a snapshot to avoid concurrent modification issues.
    for (final sub in List<_Subscription>.from(handlers)) {
      if (sub.isActive) {
        try {
          (sub as _Subscription<T>).invoke(event);
        } catch (_) {
          // Individual handler errors must not prevent other handlers.
        }
      }
    }

    // Prune cancelled subscriptions.
    handlers.removeWhere((s) => !s.isActive);
  }

  // ─── Unsubscription ───────────────────────────────────────────────────────

  /// Removes [handler] from all event type buckets.
  void removeAll() {
    _subscriptions.clear();
  }

  /// Cancels all subscriptions for event type [T].
  void offAll<T extends P2PEvent>() {
    _subscriptions.remove(T);
  }

  /// Internal: cancels a specific subscription.
  void _cancel(_Subscription sub) {
    sub._active = false;
    final bucket = _subscriptions[sub._type];
    bucket?.removeWhere((s) => s == sub);
  }

  /// Number of active subscriptions across all types.
  int get subscriptionCount =>
      _subscriptions.values.fold(0, (sum, list) => sum + list.length);
}

// ─── Subscription ─────────────────────────────────────────────────────────────

/// A handle to an event subscription.
abstract class EventSubscription {
  /// Cancels this subscription so no further events are delivered.
  void cancel();

  /// Whether this subscription is still active.
  bool get isActive;
}

class _Subscription<T extends P2PEvent> implements EventSubscription {
  final EventHandler<T> _handler;
  final EventBus _bus;
  bool _active = true;

  Type get _type => T;

  _Subscription(this._handler, {required EventBus bus}) : _bus = bus;

  void invoke(T event) {
    if (_active) _handler(event);
  }

  @override
  void cancel() => _bus._cancel(this);

  @override
  bool get isActive => _active;
}
