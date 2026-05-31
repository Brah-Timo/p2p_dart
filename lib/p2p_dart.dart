/// p2p_dart — Serverless Peer-to-Peer Networking for Dart
///
/// A comprehensive library for building decentralised P2P applications.
/// Uses WebRTC DataChannels for encrypted direct connections and a
/// Kademlia DHT for peer discovery and distributed storage.
///
/// ## Quick Start
///
/// ```dart
/// import 'package:p2p_dart/p2p_dart.dart';
///
/// void main() async {
///   final node = P2PNode(
///     config: P2PConfig(
///       bootstrapPeers: ['12D3KooWExample...'],
///     ),
///   );
///
///   await node.initialize();
///   print('Node online: ${node.peerId}');
///
///   await node.connect('12D3KooWRemote...');
///   await node.send('12D3KooWRemote...', {'hello': 'world'});
/// }
/// ```
library p2p_dart;

// ─── Core ────────────────────────────────────────────────────────────────────
export 'src/core/p2p_node.dart';
export 'src/core/connection.dart';
export 'src/core/channel_manager.dart';
export 'src/core/peer_info.dart';
export 'src/core/enums.dart';
export 'src/core/p2p_config.dart';
export 'src/core/exceptions.dart';

// ─── DHT ─────────────────────────────────────────────────────────────────────
export 'src/dht/dht_network.dart';
export 'src/dht/dht_config.dart';
export 'src/dht/routing_table.dart';
export 'src/dht/kademlia.dart';
export 'src/dht/bucket.dart';

// ─── WebRTC ──────────────────────────────────────────────────────────────────
export 'src/webrtc/webrtc_manager.dart';
export 'src/webrtc/webrtc_config.dart';
export 'src/webrtc/ice_configuration.dart';
export 'src/webrtc/stun_client.dart';
export 'src/webrtc/data_channel_wrapper.dart';

// ─── Networking ───────────────────────────────────────────────────────────────
export 'src/networking/message.dart';
export 'src/networking/message_handler.dart';
export 'src/networking/packet.dart';
export 'src/networking/transport.dart';

// ─── Security ────────────────────────────────────────────────────────────────
export 'src/security/encryption.dart';
export 'src/security/crypto_utils.dart';
export 'src/security/key_exchange.dart';
export 'src/security/dtls_handler.dart';
export 'src/security/auth_manager.dart';

// ─── Discovery ───────────────────────────────────────────────────────────────
export 'src/discovery/peer_discovery.dart';
export 'src/discovery/local_network.dart';
export 'src/discovery/peer_cache.dart';

// ─── Events ──────────────────────────────────────────────────────────────────
export 'src/events/event_bus.dart';
export 'src/events/events.dart';

// ─── Utils ───────────────────────────────────────────────────────────────────
export 'src/utils/logger.dart';
export 'src/utils/async_utils.dart';
export 'src/utils/buffer_manager.dart';
export 'src/utils/validators.dart';

// ─── Extensions ──────────────────────────────────────────────────────────────
export 'src/extensions/stream_extensions.dart';
export 'src/extensions/future_extensions.dart';
export 'src/extensions/string_extensions.dart';
