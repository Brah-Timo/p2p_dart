/// Simple P2P Chat Example
///
/// Demonstrates:
/// - Starting a P2P node.
/// - Connecting to remote peers.
/// - Sending and receiving text messages.
/// - Broadcasting to all connected peers.
///
/// Usage:
///   dart run example/simple_chat.dart [remotePeerId]
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:p2p_dart/p2p_dart.dart';

// ─── P2P Chat ─────────────────────────────────────────────────────────────────

class P2PChat {
  late P2PNode node;
  final List<String> _connectedPeers = [];
  final List<ChatMessage> _history = [];

  // ─── Lifecycle ─────────────────────────────────────────────────────────────

  Future<void> start({List<String> bootstrapPeers = const []}) async {
    node = P2PNode(
      config: P2PConfig(
        bootstrapPeers: bootstrapPeers,
        webrtc: const WebRTCConfig(
          stunServers: [
            StunServerConfig('stun.l.google.com'),
            StunServerConfig('stun1.l.google.com'),
          ],
        ),
        logging: const LoggingConfig(verbose: true),
      ),
    );

    await node.initialize();
    _registerHandlers();

    print('╔══════════════════════════════════════════╗');
    print('║          P2P Chat — ONLINE               ║');
    print('╠══════════════════════════════════════════╣');
    print('║  Your Peer ID:                           ║');
    print('║  ${node.peerId.substring(0, 40)}  ║');
    print('╚══════════════════════════════════════════╝');
    print('');
    print('Commands:');
    print('  connect <peerId>       — connect to a peer');
    print('  send <peerId> <msg>    — send message to peer');
    print('  broadcast <msg>        — send to all peers');
    print('  peers                  — list connected peers');
    print('  history                — show chat history');
    print('  quit                   — exit');
    print('');
  }

  Future<void> stop() async {
    await node.stop();
    print('Chat stopped.');
  }

  // ─── Actions ───────────────────────────────────────────────────────────────

  Future<void> connectTo(String peerId) async {
    try {
      print('Connecting to ${peerId.substring(0, 12)}…');
      await node.connect(peerId);
      _connectedPeers.add(peerId);
      print('✓ Connected to ${peerId.substring(0, 12)}');
    } catch (e) {
      print('✗ Failed to connect: $e');
    }
  }

  Future<void> sendMessage(String targetPeerId, String text) async {
    try {
      await node.send(targetPeerId, {
        'type': 'chat_message',
        'text': text,
        'timestamp': DateTime.now().toIso8601String(),
      });

      final msg = ChatMessage(
        from: 'Me',
        to: targetPeerId.substring(0, 8),
        text: text,
        timestamp: DateTime.now(),
      );
      _history.add(msg);
      print('[→ ${targetPeerId.substring(0, 8)}…]: $text');
    } catch (e) {
      print('✗ Send failed: $e');
    }
  }

  Future<void> broadcastMessage(String text) async {
    if (_connectedPeers.isEmpty) {
      print('No peers connected.');
      return;
    }

    await node.broadcast({
      'type': 'chat_broadcast',
      'text': text,
      'from': node.peerId,
      'timestamp': DateTime.now().toIso8601String(),
    });

    print('[→ ALL (${_connectedPeers.length})]: $text');
  }

  void showPeers() {
    if (_connectedPeers.isEmpty) {
      print('No peers connected.');
      return;
    }
    print('Connected peers:');
    for (final peer in _connectedPeers) {
      print('  • ${peer.substring(0, 16)}…');
    }
  }

  void showHistory({int count = 20}) {
    final recent = _history.length <= count
        ? _history
        : _history.sublist(_history.length - count);
    if (recent.isEmpty) {
      print('No messages yet.');
      return;
    }
    print('--- Chat History ---');
    for (final msg in recent) {
      final time = '${msg.timestamp.hour}:${msg.timestamp.minute.toString().padLeft(2, '0')}';
      print('[$time] ${msg.from} → ${msg.to}: ${msg.text}');
    }
    print('--- End ---');
  }

  // ─── Private ────────────────────────────────────────────────────────────

  void _registerHandlers() {
    // Incoming text messages.
    node.eventBus.on<MessageReceivedEvent>((event) {
      final data = event.data;
      if (data['type'] == 'chat_message' || data['type'] == 'chat_broadcast') {
        final sender = event.senderId.substring(0, 8);
        final text = data['text'] as String? ?? '';

        _history.add(ChatMessage(
          from: sender,
          to: 'Me',
          text: text,
          timestamp: DateTime.now(),
        ));

        print('\n[← $sender…]: $text');
        stdout.write('> ');
      }
    });

    // Peer join/leave notifications.
    node.eventBus.on<PeerConnectedEvent>((event) {
      if (!_connectedPeers.contains(event.peerId)) {
        _connectedPeers.add(event.peerId);
      }
      print('\n✓ Peer joined: ${event.peerId.substring(0, 12)}…');
      stdout.write('> ');
    });

    node.eventBus.on<PeerLeftEvent>((event) {
      _connectedPeers.remove(event.peerId);
      print('\n✗ Peer left: ${event.peerId.substring(0, 12)}…');
      stdout.write('> ');
    });
  }
}

// ─── Chat Message ────────────────────────────────────────────────────────────

class ChatMessage {
  final String from;
  final String to;
  final String text;
  final DateTime timestamp;

  const ChatMessage({
    required this.from,
    required this.to,
    required this.text,
    required this.timestamp,
  });
}

// ─── CLI REPL ────────────────────────────────────────────────────────────────

Future<void> main(List<String> args) async {
  final chat = P2PChat();
  await chat.start(
    bootstrapPeers: args.isNotEmpty ? [args.first] : [],
  );

  // If a remote peer was given, connect immediately.
  if (args.length >= 2) {
    await chat.connectTo(args[1]);
  }

  stdout.write('> ');

  await for (final line in stdin.transform(const SystemEncoding().decoder).transform(const LineSplitter())) {
    final parts = line.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) {
      stdout.write('> ');
      continue;
    }

    switch (parts[0]) {
      case 'connect':
        if (parts.length < 2) {
          print('Usage: connect <peerId>');
        } else {
          await chat.connectTo(parts[1]);
        }

      case 'send':
        if (parts.length < 3) {
          print('Usage: send <peerId> <message>');
        } else {
          await chat.sendMessage(parts[1], parts.sublist(2).join(' '));
        }

      case 'broadcast':
        if (parts.length < 2) {
          print('Usage: broadcast <message>');
        } else {
          await chat.broadcastMessage(parts.sublist(1).join(' '));
        }

      case 'peers':
        chat.showPeers();

      case 'history':
        chat.showHistory();

      case 'quit':
      case 'exit':
        await chat.stop();
        exit(0);

      default:
        print('Unknown command: ${parts[0]}');
    }

    stdout.write('> ');
  }
}
