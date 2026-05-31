/// Unit tests for [EventBus].
library;

import 'dart:async';

import 'package:test/test.dart';
import 'package:p2p_dart/p2p_dart.dart';

// ─── Test Event ───────────────────────────────────────────────────────────────

class TestEvent extends P2PEvent {
  final String value;
  TestEvent(this.value);
}

class OtherEvent extends P2PEvent {
  OtherEvent();
}

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  late EventBus bus;

  setUp(() => bus = EventBus());

  group('EventBus', () {
    test('on() receives emitted events', () {
      final received = <String>[];
      bus.on<TestEvent>((e) => received.add(e.value));
      bus.emit(TestEvent('hello'));
      bus.emit(TestEvent('world'));
      expect(received, equals(['hello', 'world']));
    });

    test('does not deliver to wrong type handler', () {
      var called = false;
      bus.on<OtherEvent>((_) => called = true);
      bus.emit(TestEvent('ignored'));
      expect(called, isFalse);
    });

    test('cancel() stops delivery', () {
      final received = <String>[];
      final sub = bus.on<TestEvent>((e) => received.add(e.value));
      bus.emit(TestEvent('first'));
      sub.cancel();
      bus.emit(TestEvent('second'));
      expect(received, equals(['first']));
    });

    test('once() fires only once', () {
      var count = 0;
      bus.once<TestEvent>((_) => count++);
      bus.emit(TestEvent('a'));
      bus.emit(TestEvent('b'));
      bus.emit(TestEvent('c'));
      expect(count, equals(1));
    });

    test('next() completes on first event', () async {
      final future = bus.next<TestEvent>();
      bus.emit(TestEvent('expected'));
      final event = await future;
      expect(event.value, equals('expected'));
    });

    test('stream() emits events', () async {
      final values = <String>[];
      final sub = bus.stream<TestEvent>().listen((e) => values.add(e.value));
      bus.emit(TestEvent('x'));
      bus.emit(TestEvent('y'));
      await Future.microtask(() {});
      sub.cancel();
      expect(values, equals(['x', 'y']));
    });

    test('multiple handlers for same type', () {
      final log = <String>[];
      bus.on<TestEvent>((_) => log.add('h1'));
      bus.on<TestEvent>((_) => log.add('h2'));
      bus.emit(TestEvent('trigger'));
      expect(log, containsAll(['h1', 'h2']));
    });

    test('subscriptionCount reflects active subscriptions', () {
      expect(bus.subscriptionCount, isZero);
      final s1 = bus.on<TestEvent>((_) {});
      final s2 = bus.on<TestEvent>((_) {});
      expect(bus.subscriptionCount, equals(2));
      s1.cancel();
      bus.emit(TestEvent('trigger')); // triggers pruning
      expect(bus.subscriptionCount, lessThanOrEqualTo(1));
      s2.cancel();
    });

    test('offAll() removes all handlers for a type', () {
      var count = 0;
      bus.on<TestEvent>((_) => count++);
      bus.on<TestEvent>((_) => count++);
      bus.offAll<TestEvent>();
      bus.emit(TestEvent('ignored'));
      expect(count, isZero);
    });

    test('handler error does not affect other handlers', () {
      var safe = false;
      bus.on<TestEvent>((_) => throw Exception('oops'));
      bus.on<TestEvent>((_) => safe = true);
      expect(() => bus.emit(TestEvent('test')), returnsNormally);
      expect(safe, isTrue);
    });
  });
}
