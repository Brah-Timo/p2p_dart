/// P2P Multiplayer Game Example
///
/// A minimal "position sync" demo showing:
/// - Low-latency unreliable game-state broadcast.
/// - Input prediction and reconciliation concept.
/// - Player join / leave handling.
/// - Server-less authority model.
library;

import 'dart:async';
import 'dart:math';

import 'package:p2p_dart/p2p_dart.dart';

// ─── Game State ───────────────────────────────────────────────────────────────

class Vector2 {
  double x;
  double y;

  Vector2(this.x, this.y);

  Vector2 operator +(Vector2 other) => Vector2(x + other.x, y + other.y);
  Vector2 operator *(double s) => Vector2(x * s, y * s);

  Map<String, dynamic> toJson() => {'x': x, 'y': y};
  factory Vector2.fromJson(Map<String, dynamic> j) =>
      Vector2((j['x'] as num).toDouble(), (j['y'] as num).toDouble());

  @override
  String toString() => '(${x.toStringAsFixed(1)}, ${y.toStringAsFixed(1)})';
}

class PlayerState {
  final String peerId;
  String displayName;
  Vector2 position;
  Vector2 velocity;
  double rotation;
  String animation;
  int health;
  int score;
  DateTime lastUpdate;

  PlayerState({
    required this.peerId,
    this.displayName = 'Player',
    Vector2? position,
    Vector2? velocity,
    this.rotation = 0,
    this.animation = 'idle',
    this.health = 100,
    this.score = 0,
  })  : position = position ?? Vector2(0, 0),
        velocity = velocity ?? Vector2(0, 0),
        lastUpdate = DateTime.now();

  Map<String, dynamic> toJson() => {
        'peerId': peerId,
        'name': displayName,
        'pos': position.toJson(),
        'vel': velocity.toJson(),
        'rot': rotation,
        'anim': animation,
        'hp': health,
        'score': score,
        'ts': lastUpdate.millisecondsSinceEpoch,
      };

  factory PlayerState.fromJson(Map<String, dynamic> j) => PlayerState(
        peerId: j['peerId'] as String,
        displayName: (j['name'] as String?) ?? 'Player',
        position: Vector2.fromJson(j['pos'] as Map<String, dynamic>),
        velocity: Vector2.fromJson(j['vel'] as Map<String, dynamic>),
        rotation: (j['rot'] as num).toDouble(),
        animation: (j['anim'] as String?) ?? 'idle',
        health: (j['hp'] as int?) ?? 100,
        score: (j['score'] as int?) ?? 0,
      );
}

// ─── Game Event ───────────────────────────────────────────────────────────────

class GameEvent {
  final String type;
  final String senderId;
  final Map<String, dynamic> data;
  final DateTime timestamp;

  GameEvent({
    required this.type,
    required this.senderId,
    required this.data,
  }) : timestamp = DateTime.now();
}

// ─── P2P Game ─────────────────────────────────────────────────────────────────

/// A minimal P2P multiplayer game controller.
class P2PGame {
  // ─── Config ────────────────────────────────────────────────────────────────

  static const Duration _tickRate = Duration(milliseconds: 50); // 20 Hz
  static const double _worldWidth = 800;
  static const double _worldHeight = 600;

  // ─── State ─────────────────────────────────────────────────────────────────

  late P2PNode _node;
  late PlayerState _localPlayer;
  final Map<String, PlayerState> _remotePlayers = {};

  Timer? _gameTick;
  final _rng = Random();

  // ─── Streams ───────────────────────────────────────────────────────────────

  final _eventController = StreamController<GameEvent>.broadcast();

  /// Stream of game events (join, leave, state updates, etc.).
  Stream<GameEvent> get onEvent => _eventController.stream;

  // ─── Lifecycle ─────────────────────────────────────────────────────────────

  Future<void> start({
    String? displayName,
    List<String> bootstrapPeers = const [],
  }) async {
    _node = P2PNode(
      config: P2PConfig(
        bootstrapPeers: bootstrapPeers,
        webrtc: WebRTCConfig(
          defaultChannel: DataChannelConfig.unreliable(
            label: 'game-state',
          ),
        ),
        performance: const PerformanceConfig(
          heartbeatInterval: Duration(seconds: 5),
        ),
      ),
    );

    await _node.initialize();

    _localPlayer = PlayerState(
      peerId: _node.peerId,
      displayName: displayName ?? 'Player-${_node.peerId.substring(0, 4)}',
      position: Vector2(
        _rng.nextDouble() * _worldWidth,
        _rng.nextDouble() * _worldHeight,
      ),
    );

    _registerHandlers();
    _startGameLoop();

    print('Game started. Player: ${_localPlayer.displayName} (${_node.peerId.substring(0, 8)})');
    print('Position: ${_localPlayer.position}');
  }

  Future<void> stop() async {
    _gameTick?.cancel();
    await _node.stop();
    _eventController.close();
  }

  // ─── Player Input ─────────────────────────────────────────────────────────

  /// Applies directional input (dx, dy in [-1, 1]).
  void applyInput(double dx, double dy) {
    const speed = 150.0; // pixels per second
    _localPlayer.velocity = Vector2(dx * speed, dy * speed);
    _localPlayer.animation = (dx != 0 || dy != 0) ? 'run' : 'idle';
  }

  /// Makes the local player attack.
  Future<void> attack() async {
    _localPlayer.animation = 'attack';
    await _broadcastAction('attack', {
      'pos': _localPlayer.position.toJson(),
      'rot': _localPlayer.rotation,
    });
  }

  // ─── Queries ──────────────────────────────────────────────────────────────

  /// All players (local + remote).
  List<PlayerState> get allPlayers => [
        _localPlayer,
        ..._remotePlayers.values,
      ];

  /// Number of players currently in the game.
  int get playerCount => 1 + _remotePlayers.length;

  /// The local player's state.
  PlayerState get localPlayer => _localPlayer;

  // ─── Private: Game Loop ───────────────────────────────────────────────────

  void _startGameLoop() {
    _gameTick = Timer.periodic(_tickRate, (_) => _tick());
  }

  void _tick() {
    final dt = _tickRate.inMilliseconds / 1000.0; // seconds

    // Update local position.
    _localPlayer.position = _localPlayer.position + (_localPlayer.velocity * dt);

    // Clamp to world bounds.
    _localPlayer.position.x =
        _localPlayer.position.x.clamp(0, _worldWidth);
    _localPlayer.position.y =
        _localPlayer.position.y.clamp(0, _worldHeight);

    _localPlayer.lastUpdate = DateTime.now();

    // Broadcast state every tick.
    _broadcastState();
  }

  void _broadcastState() {
    _node.broadcast({
      'type': 'player_state',
      'state': _localPlayer.toJson(),
    }).catchError((_) {});
  }

  Future<void> _broadcastAction(
    String action,
    Map<String, dynamic> data,
  ) async {
    await _node.broadcast({
      'type': 'player_action',
      'action': action,
      'peerId': _node.peerId,
      ...data,
    });
  }

  // ─── Private: Message Handling ────────────────────────────────────────────

  void _registerHandlers() {
    _node.eventBus.on<MessageReceivedEvent>((event) {
      final data = event.data;
      switch (data['type'] as String?) {
        case 'player_state':
          _onRemoteState(event.senderId, data);
        case 'player_action':
          _onRemoteAction(event.senderId, data);
        case 'player_join':
          _onPlayerJoin(event.senderId, data);
      }
    });

    _node.eventBus.on<PeerConnectedEvent>((event) {
      // Announce ourselves to the new peer.
      _node.send(event.peerId, {
        'type': 'player_join',
        'state': _localPlayer.toJson(),
      }).catchError((_) {});
    });

    _node.eventBus.on<PeerLeftEvent>((event) {
      final player = _remotePlayers.remove(event.peerId);
      if (player != null) {
        print('Player left: ${player.displayName}');
        _eventController.add(GameEvent(
          type: 'player_left',
          senderId: event.peerId,
          data: {'displayName': player.displayName},
        ));
      }
    });
  }

  void _onRemoteState(String senderId, Map<String, dynamic> data) {
    final stateJson = data['state'] as Map<String, dynamic>?;
    if (stateJson == null) return;

    final state = PlayerState.fromJson(stateJson);

    // Simple lag compensation: only accept if newer than last known.
    final existing = _remotePlayers[senderId];
    if (existing != null &&
        state.lastUpdate.isBefore(existing.lastUpdate)) {
      return; // Discard old state.
    }

    _remotePlayers[senderId] = state;
    _eventController.add(GameEvent(
      type: 'state_update',
      senderId: senderId,
      data: data,
    ));
  }

  void _onRemoteAction(String senderId, Map<String, dynamic> data) {
    final action = data['action'] as String?;
    if (action == null) return;

    _eventController.add(GameEvent(
      type: 'player_action',
      senderId: senderId,
      data: {'action': action},
    ));

    print('${senderId.substring(0, 8)}: $action');
  }

  void _onPlayerJoin(String senderId, Map<String, dynamic> data) {
    final stateJson = data['state'] as Map<String, dynamic>?;
    if (stateJson == null) return;

    final player = PlayerState.fromJson(stateJson);
    _remotePlayers[senderId] = player;

    print('Player joined: ${player.displayName} @ ${player.position}');
    _eventController.add(GameEvent(
      type: 'player_joined',
      senderId: senderId,
      data: {'displayName': player.displayName},
    ));

    // Send our state back.
    _node.send(senderId, {
      'type': 'player_join',
      'state': _localPlayer.toJson(),
    }).catchError((_) {});
  }
}

// ─── Demo ─────────────────────────────────────────────────────────────────────

Future<void> main(List<String> args) async {
  final game = P2PGame();
  await game.start(
    displayName: 'Hero',
    bootstrapPeers: args.isNotEmpty ? [args.first] : [],
  );

  game.onEvent.listen((event) {
    if (event.type == 'player_joined' || event.type == 'player_left') {
      print('[Game Event] ${event.type}: ${event.data['displayName']}');
    }
  });

  // Simulate movement.
  final rng = Random();
  Timer.periodic(const Duration(milliseconds: 500), (_) {
    game.applyInput(
      (rng.nextDouble() * 2 - 1),
      (rng.nextDouble() * 2 - 1),
    );
  });

  // Print game state every second.
  Timer.periodic(const Duration(seconds: 1), (_) {
    print('--- Game State (${game.playerCount} players) ---');
    for (final player in game.allPlayers) {
      final tag = player.peerId == game.localPlayer.peerId ? '[ME]' : '    ';
      print('  $tag ${player.displayName}: ${player.position}  HP: ${player.health}');
    }
  });

  // Run for 60 seconds.
  await Future.delayed(const Duration(seconds: 60));
  await game.stop();
}
