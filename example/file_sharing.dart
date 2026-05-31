/// P2P File Sharing Example
///
/// Demonstrates:
/// - Sending files as chunked binary messages.
/// - Tracking transfer progress.
/// - Reassembling chunks on the receiver side.
/// - Multiple concurrent transfers.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:p2p_dart/p2p_dart.dart';

// ─── Transfer Meta ────────────────────────────────────────────────────────────

class TransferMeta {
  final String id;
  final String fileName;
  final int totalSize;
  final int totalChunks;
  final int chunkSize;

  int receivedChunks = 0;
  final List<Uint8List?> chunks;

  TransferMeta({
    required this.id,
    required this.fileName,
    required this.totalSize,
    required this.totalChunks,
    required this.chunkSize,
  }) : chunks = List.filled(totalChunks, null);

  bool get isComplete => receivedChunks == totalChunks;

  double get progress => totalChunks == 0 ? 0 : receivedChunks / totalChunks;

  Uint8List reassemble() {
    final buffer = GrowingBuffer(initialCapacity: totalSize);
    for (final chunk in chunks) {
      if (chunk != null) buffer.write(chunk);
    }
    return buffer.toBytes();
  }
}

// ─── P2P File Sharing ─────────────────────────────────────────────────────────

class P2PFileSharing {
  static const int chunkSize = 16 * 1024; // 16 KiB
  static const int chunkDelayMs = 5;

  late P2PNode node;

  final Map<String, TransferMeta> _inboundTransfers = {};
  final Map<String, TransferProgress> _outboundProgress = {};

  final StreamController<FileReceivedEvent> _fileReceived =
      StreamController.broadcast();

  final StreamController<TransferProgress> _progressUpdates =
      StreamController.broadcast();

  /// Stream of completed received files.
  Stream<FileReceivedEvent> get onFileReceived => _fileReceived.stream;

  /// Stream of outbound transfer progress updates.
  Stream<TransferProgress> get onProgress => _progressUpdates.stream;

  // ─── Lifecycle ─────────────────────────────────────────────────────────────

  Future<void> start({List<String> bootstrapPeers = const []}) async {
    node = P2PNode(
      config: P2PConfig(
        bootstrapPeers: bootstrapPeers,
        performance: const PerformanceConfig(
          maxMessageSize: 64 * 1024,
        ),
      ),
    );

    await node.initialize();
    _setupHandlers();
    print('File sharing node online: ${node.peerId}');
  }

  Future<void> stop() => node.stop();

  // ─── Send ──────────────────────────────────────────────────────────────────

  /// Sends the file at [filePath] to [targetPeerId].
  Future<void> sendFile(String targetPeerId, String filePath) async {
    final file = File(filePath);
    if (!file.existsSync()) throw FileSystemException('File not found', filePath);

    final bytes = await file.readAsBytes();
    final fileName = file.uri.pathSegments.last;
    final totalChunks = (bytes.length / chunkSize).ceil();
    final transferId = _generateId();

    final progress = TransferProgress(
      id: transferId,
      fileName: fileName,
      totalBytes: bytes.length,
      direction: TransferDirection.outbound,
    );
    _outboundProgress[transferId] = progress;

    print('Sending "$fileName" (${_formatBytes(bytes.length)}) → ${targetPeerId.substring(0, 8)}…');

    // 1. Send header.
    await node.send(targetPeerId, {
      'type': 'file_header',
      'transferId': transferId,
      'fileName': fileName,
      'totalSize': bytes.length,
      'totalChunks': totalChunks,
      'chunkSize': chunkSize,
    });

    // 2. Stream chunks.
    final chunks = Chunker.split(bytes, chunkSize);
    for (var i = 0; i < chunks.length; i++) {
      await node.send(targetPeerId, {
        'type': 'file_chunk',
        'transferId': transferId,
        'chunkIndex': i,
        'data': base64Encode(chunks[i]),
      });

      progress.sentBytes += chunks[i].length;
      _progressUpdates.add(progress);
      _printProgress(fileName, i + 1, totalChunks, bytes.length, progress.sentBytes);

      if (chunkDelayMs > 0) {
        await Future.delayed(Duration(milliseconds: chunkDelayMs));
      }
    }

    // 3. Send completion signal.
    await node.send(targetPeerId, {
      'type': 'file_complete',
      'transferId': transferId,
    });

    print('\n✓ "$fileName" sent successfully!');
    _outboundProgress.remove(transferId);
  }

  // ─── Receive ──────────────────────────────────────────────────────────────

  void _setupHandlers() {
    node.messageHandler.on(MessageType.data, (msg) async {
      final data = msg.payload;
      if (data == null) return;

      switch (data['type'] as String?) {
        case 'file_header':
          _handleHeader(msg.senderId, data);
        case 'file_chunk':
          _handleChunk(msg.senderId, data);
        case 'file_complete':
          await _handleComplete(msg.senderId, data);
      }
    });
  }

  void _handleHeader(String senderId, Map<String, dynamic> data) {
    final meta = TransferMeta(
      id: data['transferId'] as String,
      fileName: data['fileName'] as String,
      totalSize: data['totalSize'] as int,
      totalChunks: data['totalChunks'] as int,
      chunkSize: data['chunkSize'] as int,
    );
    _inboundTransfers[meta.id] = meta;
    print('Receiving "${meta.fileName}" (${_formatBytes(meta.totalSize)}) from ${senderId.substring(0, 8)}…');
  }

  void _handleChunk(String senderId, Map<String, dynamic> data) {
    final transferId = data['transferId'] as String;
    final meta = _inboundTransfers[transferId];
    if (meta == null) return;

    final index = data['chunkIndex'] as int;
    final bytes = base64Decode(data['data'] as String);
    meta.chunks[index] = bytes;
    meta.receivedChunks++;

    _printProgress(
      meta.fileName,
      meta.receivedChunks,
      meta.totalChunks,
      meta.totalSize,
      meta.receivedChunks * meta.chunkSize,
    );
  }

  Future<void> _handleComplete(
    String senderId,
    Map<String, dynamic> data,
  ) async {
    final transferId = data['transferId'] as String;
    final meta = _inboundTransfers.remove(transferId);
    if (meta == null) return;

    if (!meta.isComplete) {
      print('\n✗ Transfer incomplete: ${meta.receivedChunks}/${meta.totalChunks} chunks');
      return;
    }

    final fileBytes = meta.reassemble();
    final outputPath = './downloads/${meta.fileName}';

    await Directory('./downloads').create(recursive: true);
    await File(outputPath).writeAsBytes(fileBytes);

    print('\n✓ "${meta.fileName}" received (${_formatBytes(fileBytes.length)}) → $outputPath');

    _fileReceived.add(FileReceivedEvent(
      senderId: senderId,
      fileName: meta.fileName,
      filePath: outputPath,
      sizeBytes: fileBytes.length,
    ));
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)}MB';
  }

  static void _printProgress(
    String name,
    int done,
    int total,
    int totalBytes,
    int doneBytes,
  ) {
    final pct = (done / total * 100).toStringAsFixed(1);
    final bar = '█' * (done * 30 ~/ total) + '░' * ((total - done) * 30 ~/ total);
    stdout.write('\r  $bar $pct% (${_formatBytes(doneBytes)} / ${_formatBytes(totalBytes)})');
  }

  static String _generateId() =>
      DateTime.now().millisecondsSinceEpoch.toRadixString(36);
}

// ─── Supporting Types ─────────────────────────────────────────────────────────

enum TransferDirection { inbound, outbound }

class TransferProgress {
  final String id;
  final String fileName;
  final int totalBytes;
  final TransferDirection direction;
  int sentBytes = 0;

  TransferProgress({
    required this.id,
    required this.fileName,
    required this.totalBytes,
    required this.direction,
  });

  double get progress => totalBytes > 0 ? sentBytes / totalBytes : 0;
}

class FileReceivedEvent {
  final String senderId;
  final String fileName;
  final String filePath;
  final int sizeBytes;

  const FileReceivedEvent({
    required this.senderId,
    required this.fileName,
    required this.filePath,
    required this.sizeBytes,
  });
}

// ─── main ─────────────────────────────────────────────────────────────────────

Future<void> main(List<String> args) async {
  final sharing = P2PFileSharing();
  await sharing.start();

  if (args.length >= 2) {
    final targetPeer = args[0];
    final filePath = args[1];
    await sharing.sendFile(targetPeer, filePath);
  }

  sharing.onFileReceived.listen((e) {
    print('File received: ${e.fileName} (${e.sizeBytes} bytes) from ${e.senderId.substring(0, 8)}');
  });

  // Keep running.
  await Future.delayed(const Duration(hours: 24));
  await sharing.stop();
}
