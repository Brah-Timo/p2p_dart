/// Decentralised Key-Value Storage Example
///
/// Demonstrates:
/// - Storing and retrieving arbitrary values in the DHT.
/// - Replication across multiple nodes.
/// - TTL-based expiry.
/// - Content-addressable storage (CAS) via SHA-1 keys.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:p2p_dart/p2p_dart.dart';

// ─── Storage Entry ────────────────────────────────────────────────────────────

class StorageEntry {
  final String key;
  final dynamic value;
  final DateTime storedAt;
  final DateTime expiresAt;

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  StorageEntry({
    required this.key,
    required this.value,
    Duration ttl = const Duration(hours: 24),
  })  : storedAt = DateTime.now(),
        expiresAt = DateTime.now().add(ttl);

  @override
  String toString() =>
      'StorageEntry(key: ${key.substring(0, 8)}…, expired: $isExpired)';
}

// ─── Decentralised Storage ────────────────────────────────────────────────────

/// A fully decentralised key-value store built on top of [P2PNode] and DHT.
class DecentralisedStorage {
  late P2PNode _node;

  /// Local cache of entries to avoid redundant network requests.
  final Map<String, StorageEntry> _localCache = {};

  // ─── Lifecycle ─────────────────────────────────────────────────────────────

  Future<void> start({List<String> bootstrapPeers = const []}) async {
    _node = P2PNode(
      config: P2PConfig(
        bootstrapPeers: bootstrapPeers,
        dht: DHTConfig(
          bootstrapPeers: bootstrapPeers,
          replicationFactor: 3,
          valueTtl: const Duration(hours: 24),
        ),
      ),
    );

    await _node.initialize();
    print('Storage node online: ${_node.peerId}');
  }

  Future<void> stop() => _node.stop();

  // ─── Core Operations ──────────────────────────────────────────────────────

  /// Stores [value] under [key] in the distributed network.
  ///
  /// [key] can be any string; it will be hashed internally.
  /// Returns the hashed DHT key.
  Future<String> put(
    String key,
    dynamic value, {
    Duration ttl = const Duration(hours: 24),
  }) async {
    final serialised = _serialise(value);

    // Store in DHT.
    await _node.dhtPut(key, serialised);

    // Cache locally.
    _localCache[key] = StorageEntry(key: key, value: value, ttl: ttl);

    print('Stored: "$key" (${serialised.length} bytes)');
    return Kademlia.keyFromString(key);
  }

  /// Retrieves the value for [key], searching locally then across the network.
  ///
  /// Returns `null` if not found or if the entry has expired.
  Future<dynamic> get(String key) async {
    // Check local cache.
    final cached = _localCache[key];
    if (cached != null && !cached.isExpired) {
      print('Cache hit: "$key"');
      return cached.value;
    }

    // Search DHT.
    final raw = await _node.dhtGet(key);
    if (raw == null) {
      print('Not found: "$key"');
      return null;
    }

    final value = _deserialise(raw);
    _localCache[key] = StorageEntry(key: key, value: value);
    print('DHT hit: "$key"');
    return value;
  }

  /// Deletes [key] from the local cache.
  ///
  /// Note: DHT records expire naturally; there is no distributed delete.
  void delete(String key) {
    _localCache.remove(key);
    _node.dhtNetwork.delete(key);
    print('Deleted locally: "$key"');
  }

  // ─── Convenience Typed Wrappers ───────────────────────────────────────────

  /// Stores a JSON-serialisable [map].
  Future<String> putJson(String key, Map<String, dynamic> map, {Duration? ttl}) =>
      put(key, map, ttl: ttl ?? const Duration(hours: 24));

  /// Retrieves a JSON map.
  Future<Map<String, dynamic>?> getJson(String key) async {
    final v = await get(key);
    if (v is Map<String, dynamic>) return v;
    if (v is String) {
      try {
        return jsonDecode(v) as Map<String, dynamic>?;
      } catch (_) {}
    }
    return null;
  }

  /// Stores raw [bytes] under [key].
  Future<String> putBytes(String key, Uint8List bytes, {Duration? ttl}) =>
      put(key, bytes.toBase64(), ttl: ttl ?? const Duration(hours: 24));

  /// Retrieves raw bytes.
  Future<Uint8List?> getBytes(String key) async {
    final v = await get(key);
    if (v is String) {
      try {
        return v.fromBase64();
      } catch (_) {}
    }
    return null;
  }

  // ─── Content-Addressable Storage ─────────────────────────────────────────

  /// Stores [value] and returns its content-derived CAS key.
  ///
  /// The key is the SHA-1 hash of the serialised value.
  Future<String> putCas(dynamic value) async {
    final serialised = _serialise(value);
    final key = Kademlia.contentKey(
      Uint8List.fromList(serialised.codeUnits),
    );
    await put(key, value);
    return key;
  }

  /// Retrieves by CAS key.
  Future<dynamic> getCas(String casKey) async => get(casKey);

  // ─── Stats ────────────────────────────────────────────────────────────────

  /// Returns statistics about the local node.
  Map<String, dynamic> stats() {
    _localCache.removeWhere((_, e) => e.isExpired);
    return {
      'peerId': _node.peerId,
      'localCacheSize': _localCache.length,
      'dhtPeers': _node.dhtNetwork.peerCount,
      'connections': _node.connectionCount,
    };
  }

  // ─── Private ─────────────────────────────────────────────────────────────

  String _serialise(dynamic value) {
    if (value is String) return value;
    return jsonEncode(value);
  }

  dynamic _deserialise(String raw) {
    try {
      return jsonDecode(raw);
    } catch (_) {
      return raw;
    }
  }
}

// ─── Demo ─────────────────────────────────────────────────────────────────────

Future<void> main(List<String> args) async {
  final storage = DecentralisedStorage();
  await storage.start(
    bootstrapPeers: args.isNotEmpty ? [args.first] : [],
  );

  // ── Basic CRUD ────────────────────────────────────────────────────────────

  // Store a string.
  await storage.put('greeting', 'Hello, P2P World!');
  final greeting = await storage.get('greeting');
  print('Retrieved: $greeting');

  // Store a JSON document.
  await storage.putJson('user:alice', {
    'name': 'Alice Johnson',
    'email': 'alice@example.com',
    'joinedAt': DateTime.now().toIso8601String(),
  });

  final alice = await storage.getJson('user:alice');
  print('User: ${alice?['name']} <${alice?['email']}>');

  // ── Content-Addressable Storage ───────────────────────────────────────────

  final casKey = await storage.putCas({'document': 'Important data', 'version': 1});
  print('CAS key: $casKey');

  final doc = await storage.getCas(casKey);
  print('CAS retrieved: $doc');

  // ── Stats ─────────────────────────────────────────────────────────────────

  final stat = storage.stats();
  print('Stats: $stat');

  // ── Cleanup ───────────────────────────────────────────────────────────────

  storage.delete('greeting');
  final deleted = await storage.get('greeting');
  print('After delete: $deleted'); // Should be null (or fetched from DHT if replicated)

  await storage.stop();
}
