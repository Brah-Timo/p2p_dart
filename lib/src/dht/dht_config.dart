/// Configuration for the Kademlia Distributed Hash Table.
library;

// ─── DHT Config ───────────────────────────────────────────────────────────────

/// Configuration for the DHT network layer.
class DHTConfig {
  /// Addresses of well-known bootstrap peers to contact at startup.
  ///
  /// Each entry is a Kademlia peer ID (40-char hex).  The node will attempt
  /// to contact all of them and use the first successful responder to seed
  /// its routing table.
  ///
  /// Defaults to an empty list (creates an isolated network — useful for
  /// testing).
  final List<String> bootstrapPeers;

  /// Kademlia bucket size *k* — the maximum number of contacts stored
  /// per k-bucket.
  ///
  /// RFC 5533 recommends k = 20.  Defaults to `20`.
  final int bucketSize;

  /// Degree of parallelism *α* for iterative lookup RPCs.
  ///
  /// Kademlia sends up to α FIND_NODE / FIND_VALUE requests concurrently.
  /// Defaults to `3`.
  final int alpha;

  /// Number of nodes that should replicate each stored value.
  ///
  /// Defaults to `3`.
  final int replicationFactor;

  /// Time-to-live for locally stored DHT records.
  ///
  /// After this duration the node will stop serving the value unless it is
  /// republished.  Defaults to 24 hours.
  final Duration valueTtl;

  /// How often the node republishes its own key/value records.
  ///
  /// Should be less than [valueTtl].  Defaults to 1 hour.
  final Duration republishInterval;

  /// How often to refresh each k-bucket by performing a random lookup
  /// within its ID range.
  ///
  /// Defaults to 1 hour.
  final Duration bucketRefreshInterval;

  /// Timeout for a single FIND_NODE or FIND_VALUE RPC.
  ///
  /// Defaults to 5 seconds.
  final Duration rpcTimeout;

  /// Maximum number of hops in a single iterative lookup.
  ///
  /// Prevents infinite recursion in pathological topologies.
  /// Defaults to `20`.
  final int maxLookupHops;

  /// Whether to cache values found during FIND_VALUE lookups at the node
  /// closest to the target key that did *not* have the value.
  ///
  /// Defaults to `true`.
  final bool enableCaching;

  /// Creates a [DHTConfig].
  const DHTConfig({
    this.bootstrapPeers = const [],
    this.bucketSize = 20,
    this.alpha = 3,
    this.replicationFactor = 3,
    this.valueTtl = const Duration(hours: 24),
    this.republishInterval = const Duration(hours: 1),
    this.bucketRefreshInterval = const Duration(hours: 1),
    this.rpcTimeout = const Duration(seconds: 5),
    this.maxLookupHops = 20,
    this.enableCaching = true,
  });

  /// Validates configuration constraints.
  void validate() {
    assert(bucketSize > 0, 'bucketSize must be > 0');
    assert(alpha > 0, 'alpha must be > 0');
    assert(replicationFactor > 0, 'replicationFactor must be > 0');
    assert(
      republishInterval < valueTtl,
      'republishInterval must be less than valueTtl',
    );
  }

  @override
  String toString() =>
      'DHTConfig(k=$bucketSize, α=$alpha, replication=$replicationFactor, '
      'bootstrap=${bootstrapPeers.length})';
}
