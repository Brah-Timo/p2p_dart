/// In-memory LRU cache for [PeerInfo] objects.
library;

import '../core/peer_info.dart';

// ─── Cache Entry ─────────────────────────────────────────────────────────────

class _CacheEntry {
  PeerInfo peer;
  DateTime accessedAt;

  _CacheEntry(this.peer) : accessedAt = DateTime.now();

  void touch() => accessedAt = DateTime.now();
}

// ─── Peer Cache ───────────────────────────────────────────────────────────────

/// A size-bounded LRU cache for [PeerInfo] entries.
///
/// Evicts the least-recently-used entry when [capacity] is exceeded.
/// Entries also expire after [ttl] regardless of access.
class PeerCache {
  final int _capacity;
  final Duration _ttl;
  final Map<String, _CacheEntry> _entries = {};

  /// Creates a [PeerCache].
  PeerCache({int capacity = 500, Duration ttl = const Duration(hours: 1)})
      : _capacity = capacity,
        _ttl = ttl;

  // ─── Operations ───────────────────────────────────────────────────────────

  /// Stores [peer] in the cache, evicting LRU if at capacity.
  void put(PeerInfo peer) {
    if (_entries.containsKey(peer.peerId)) {
      _entries[peer.peerId]!
        ..peer = peer
        ..touch();
      return;
    }

    if (_entries.length >= _capacity) {
      _evictLru();
    }

    _entries[peer.peerId] = _CacheEntry(peer);
  }

  /// Retrieves the [PeerInfo] for [peerId], or `null` if not found or expired.
  PeerInfo? get(String peerId) {
    final entry = _entries[peerId];
    if (entry == null) return null;

    if (_isExpired(entry)) {
      _entries.remove(peerId);
      return null;
    }

    entry.touch();
    return entry.peer;
  }

  /// Removes the entry for [peerId].
  void remove(String peerId) => _entries.remove(peerId);

  /// Clears all entries.
  void clear() => _entries.clear();

  /// Returns `true` if [peerId] is in the cache and not expired.
  bool contains(String peerId) => get(peerId) != null;

  /// Number of non-expired entries.
  int get size {
    _evictExpired();
    return _entries.length;
  }

  /// All non-expired [PeerInfo] entries.
  List<PeerInfo> get all {
    _evictExpired();
    return _entries.values.map((e) => e.peer).toList();
  }

  // ─── Private ────────────────────────────────────────────────────────────

  bool _isExpired(_CacheEntry entry) =>
      DateTime.now().difference(entry.peer.lastSeen) > _ttl;

  void _evictLru() {
    if (_entries.isEmpty) return;

    var oldest = _entries.entries.first;
    for (final entry in _entries.entries) {
      if (entry.value.accessedAt.isBefore(oldest.value.accessedAt)) {
        oldest = entry;
      }
    }
    _entries.remove(oldest.key);
  }

  void _evictExpired() {
    _entries.removeWhere((_, e) => _isExpired(e));
  }
}
