# Security

This document covers encryption, authentication, and cryptographic utilities in `p2p_dart`.

---

## Table of Contents

1. [Security Overview](#security-overview)
2. [Transport Encryption (DTLS/SRTP)](#transport-encryption-dtlssrtp)
3. [Peer Authentication](#peer-authentication)
4. [CryptoUtils Reference](#cryptoutils-reference)
5. [AuthManager Reference](#authmanager-reference)
6. [Security Configuration](#security-configuration)
7. [Trusted Peer Lists](#trusted-peer-lists)
8. [Best Practices](#best-practices)

---

## Security Overview

`p2p_dart` provides two layers of security:

| Layer | Mechanism | Where |
|-------|-----------|-------|
| **Transport** | DTLS 1.3 (WebRTC mandatory) | `DataChannelWrapper` / browser WebRTC |
| **Authentication** | HMAC-SHA256 challenge-response | `AuthManager` |

Optional application-level encryption is available through `CryptoUtils` (AES-256-GCM).

---

## Transport Encryption (DTLS/SRTP)

All WebRTC data channels are **encrypted by default** via DTLS 1.3. This is enforced by the WebRTC specification and cannot be disabled. The DTLS handshake:

1. Both peers generate ephemeral key pairs.
2. Each SDP includes a **DTLS fingerprint** (`a=fingerprint:sha-256 ...`).
3. On connection, both sides verify each other's certificate fingerprint.
4. A shared session key is derived; all subsequent data is encrypted with AES-GCM.

`SecurityConfig.enforceEncryption = true` (the default) terminates any connection that fails the DTLS handshake. Set to `false` only for testing in isolated environments.

---

## Peer Authentication

Beyond transport encryption, `p2p_dart` supports **application-level peer authentication** using a symmetric challenge-response protocol.

### Protocol

```
Alice                                        Bob
  │                                           │
  │  issueChallenge(bobId)                    │
  │    ─── {nonce: 32 random bytes} ─────────►│
  │                                           │ signChallenge(nonce)
  │                                           │   HMAC-SHA256(sharedKey, nonce)
  │◄─── {nonce, signature, responderId} ──────│
  │                                           │
  │  verifyResponse(response)                 │
  │    HMAC-SHA256(sharedKey, nonce) ==        │
  │      response.signature ?                 │
  │        → peer verified                    │
  └───────────────────────────────────────────┘
```

Both peers must share the same **pre-shared key** (`presharedKey`). In practice this is derived from an out-of-band secret or an ECDH session key.

### Usage

```dart
// Initialise on both sides with the same key.
final key = CryptoUtils.randomBytes(32);  // 256-bit

final authManager = AuthManager(
  localPeerId: node.peerId,
  presharedKey: key,
  maxFailures: 5,
);

// --- INITIATOR SIDE ---
// Step 1: Issue a challenge and send the nonce to the remote peer.
final challenge = authManager.issueChallenge(remotePeerId);
await connection.send({'auth_nonce': challenge.nonceHex});

// --- RESPONDER SIDE ---
// Step 2: Receive nonce, sign it, send back the response.
final nonce = CryptoUtils.hexToBytes(data['auth_nonce'] as String);
final response = authManager.signChallenge(nonce);
await connection.send(response.toJson());

// --- INITIATOR SIDE ---
// Step 3: Verify the response.
final authResponse = AuthResponse.fromJson(responseData);
try {
  final verified = authManager.verifyResponse(authResponse);
  if (verified) print('Peer authenticated!');
} on AuthenticationException catch (e) {
  print('Auth failed: $e');
  await connection.close();
}
```

### Challenge Expiry

Challenges automatically expire after **30 seconds**. If `verifyResponse` is called with an expired challenge, `AuthenticationException` is thrown.

### Failure Counting

Each verification failure increments an internal counter per peer. When `maxFailures` (default 5) is reached, `isBanned(peerId)` returns `true`. Application code should check this before allowing further connection attempts:

```dart
if (authManager.isBanned(incomingPeerId)) {
  await connection.close();
  return;
}
```

---

## CryptoUtils Reference

**File:** `lib/src/security/crypto_utils.dart`

All methods are static.

### Symmetric Encryption

```dart
// Generate a 256-bit AES key.
final key = CryptoUtils.generateAesKey();  // Uint8List(32)

// Encrypt with AES-256-GCM (includes random 12-byte IV).
// Returns: IV(12) || ciphertext || auth_tag(16)
final encrypted = CryptoUtils.encryptAesGcm(key, plaintext);

// Decrypt.
final decrypted = CryptoUtils.decryptAesGcm(key, encrypted);
```

### HMAC

```dart
// Compute HMAC-SHA256(key, data) → 32 bytes.
final mac = CryptoUtils.hmacSha256(key, data);
```

### Hashing

```dart
// SHA-256.
final hash = CryptoUtils.sha256(data);  // Uint8List(32)

// SHA-1 (for Kademlia IDs).
final hash = CryptoUtils.sha1(data);    // Uint8List(20)
```

### Key Derivation

```dart
// HKDF-SHA256: expand/extract a key from input keying material.
final derivedKey = CryptoUtils.hkdf(
  inputKeyMaterial: ikm,
  salt: salt,        // optional, Uint8List
  info: info,        // optional, Uint8List
  length: 32,
);
```

### Random Bytes

```dart
// Cryptographically secure random bytes.
final nonce = CryptoUtils.randomBytes(32);
```

### Hex Utilities

```dart
final hex = CryptoUtils.bytesToHex(bytes);
final bytes = CryptoUtils.hexToBytes(hexString);
```

### Constant-time Comparison

```dart
// Safe from timing attacks.
final equal = CryptoUtils.constantTimeEqual(a, b);
```

---

## AuthManager Reference

**File:** `lib/src/security/auth_manager.dart`

```dart
AuthManager({
  required String localPeerId,
  required Uint8List presharedKey,
  int maxFailures = 5,
  P2PLogger? logger,
})
```

| Method | Returns | Description |
|--------|---------|-------------|
| `issueChallenge(remotePeerId)` | `AuthChallenge` | Create and store a nonce challenge |
| `signChallenge(nonce)` | `AuthResponse` | Sign a received nonce with the shared key |
| `verifyResponse(response)` | `bool` | Verify HMAC; throws `AuthenticationException` on failure |
| `isVerified(remotePeerId)` | `bool` | Whether the peer passed authentication |
| `isBanned(remotePeerId)` | `bool` | Whether the peer exceeded failure limit |
| `revoke(remotePeerId)` | `void` | Remove from verified set (e.g., on disconnect) |

---

## Security Configuration

```dart
P2PConfig(
  security: SecurityConfig(
    // Refuse connections that fail DTLS (default: true).
    enforceEncryption: true,

    // Require HMAC challenge-response from all incoming peers (default: false).
    requireAuthentication: true,

    // How long to wait for the auth handshake (default: 15 s).
    authTimeout: Duration(seconds: 15),

    // If non-empty and requireAuthentication is true,
    // only these peer IDs may connect.
    trustedPeers: ['aabb...', 'ccdd...'],

    // Ban a peer after this many failed auth attempts (default: 5).
    maxAuthFailures: 5,
  ),
)
```

---

## Trusted Peer Lists

When `trustedPeers` is non-empty and `requireAuthentication` is `true`, only the listed peer IDs are admitted:

```dart
SecurityConfig(
  requireAuthentication: true,
  trustedPeers: [
    'aabbccdd...40chars...',  // Alice
    '11223344...40chars...',  // Bob
  ],
)
```

Any peer not on the list will have its connection closed immediately after identification.

---

## Best Practices

1. **Always use `enforceEncryption: true`** (the default). There is no legitimate reason to disable DTLS.

2. **Use a derived pre-shared key** rather than a hardcoded one. Options:
   - Derive from an ECDH exchange at first connection.
   - Use `CryptoUtils.hkdf` to derive from a password + salt.

3. **Enable `requireAuthentication`** for private networks or applications with sensitive data.

4. **Rotate keys periodically** by revoking a peer's authentication (`authManager.revoke`) and re-authenticating.

5. **Monitor auth failures.** `AuthManager` automatically counts failures. Log bans via the `onLog` callback in `LoggingConfig`.

6. **Never log sensitive data** unless debugging. Keep `logSensitiveData: false` in production.

7. **Validate peer IDs** using `Kademlia.isValidId(peerId)` before connecting.
