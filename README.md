# TwoOfUs — Private, Zero-Knowledge 1-to-1 Communication Ecosystem 🔒✨

<div align="center">

[![Security: End-to-End Encrypted](https://img.shields.io/badge/Security-End--to--End%20Encrypted%20(X25519%20%2B%20AES--256--GCM)-00C853?style=for-the-badge&logo=shield)](https://github.com/aradhyags7/TwoOfUs)
[![Flutter](https://img.shields.io/badge/Flutter-3.x%20Mobile%20(Android%20%7C%20iOS)-02569B?style=for-the-badge&logo=flutter)](https://flutter.dev)
[![FastAPI](https://img.shields.io/badge/FastAPI-Python%203.11%2B-009688?style=for-the-badge&logo=fastapi)](https://fastapi.tiangolo.com)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-Render%20Cloud-336791?style=for-the-badge&logo=postgresql)](https://www.postgresql.org)
[![Automated Tests](https://img.shields.io/badge/Test%20Suite-All%20Tests%20Passing%20(100%25)-brightgreen?style=for-the-badge&logo=checkmarx)](https://github.com/aradhyags7/TwoOfUs)

**A private, hardened, zero-knowledge 1-to-1 communication space designed exclusively for two connected people.**  
Built for best friends, trusted companions, confidants, and partners who demand absolute privacy, cryptographic sovereignty, and seamless real-time collaboration.

[Live Production Server](https://twoofus.onrender.com) • [Key Features](#-key-features) • [Security & Cryptography](#-security--cryptographic-architecture) • [WebRTC Calling](#-webrtc-hd-voice--video-calling) • [System Architecture](#-system-architecture) • [Getting Started](#-getting-started) • [Automated Tests](#-quality-assurance--automated-tests)

</div>

---

## 📖 Overview

In an era of invasive data harvesting and shared group chats, **TwoOfUs** offers a sanctuary: a dedicated, cryptographically isolated space tailored for exactly **two people**. Whether you are collaborating with your closest friend, staying connected with a trusted confidant, or keeping your personal conversations completely confidential, TwoOfUs provides:

- 🛡️ **Zero-Knowledge Privacy**: Server-side zero knowledge where private keys, plaintext messages, and unencrypted files never touch the server disk.
- 💬 **Private 1-to-1 Messaging**: Instant encrypted text, rich replies, reactions, full text search, and genuine presence indicators.
- 📞 **Peer-to-Peer HD Calling**: Crystal-clear voice and video calls with hardware acoustic echo cancellation (AEC), automatic gain control (AGC), and direct DTLS-SRTP media streaming.
- 👁️ **Ephemeral "View-Once" Media**: Disappearing photos and videos with atomic server-side shredding upon consumption.
- 📓 **Shared Timeline & Notes**: A collaborative private diary, notes vault, and memory timeline for two.
- 🔐 **Multi-Method 2FA & App Security**: TOTP authenticator app support, email OTP delivery, single-use recovery codes, and biometric app lock.

---

## 🌟 Key Features

### 🔐 1. Zero-Knowledge End-to-End Cryptography
* **On-Device Key Generation**: Curve25519 (X25519 ECDH) key pairs are generated on client hardware and never leave the device unencrypted.
* **Authenticated Encryption**: All messages and media payloads are encrypted using AES-256-GCM / XSalsa20-Poly1305 with fresh cryptographic nonces on every transmission.
* **Out-of-Band Safety Numbers**: Interactive 60-digit safety codes and camera-based QR scanner (Signal/WhatsApp standard) to mathematically verify encryption integrity and prevent Man-in-the-Middle (MITM) attacks.
* **Server-Side Blind Routing**: The FastAPI server acts purely as an encrypted blind router and public key directory. It cannot decrypt conversations or view user files.

### 📞 2. WebRTC HD Voice & Video Calling
* **Direct Peer-to-Peer Media**: Voice and video streams route directly peer-to-peer using WebRTC Unified Plan semantics.
* **Hardware Audio Optimization**: Automatic Acoustic Echo Cancellation (AEC), Noise Suppression, and Auto Gain Control (AGC) configured through native platform audio sessions (`MODE_IN_COMMUNICATION`).
* **Adaptive Opus Codec**: Low-latency, adaptive audio streaming with Forward Error Correction (FEC) and Discontinuous Transmission (DTX) for resilient calls even over cellular networks.
* **Global NAT Traversal**: Multi-tier ICE discovery utilizing Google STUN clusters, Cloudflare STUN, and OpenRelay TURN fallback for guaranteed connectivity across strict firewalls and mobile carrier NATs.
* **Dynamic Peripheral Audio Routing**: Seamless real-time switching between device loudspeaker, earpiece receiver, and connected Bluetooth audio devices with visual audio waveform meters.

### 💬 3. Private Messaging & Dynamic Presence
* **Real-Time Delivery**: WebSocket-backed instant messaging with sent, delivered, and read status indicators.
* **Interactive Chat Controls**: Quote replies, message editing, custom emoji reactions, and message copy.
* **Full-Conversation Search**: Offline search across conversation history with match highlighting and forward/backward navigation.
* **Accurate Online Presence**: Real-time heartbeat synchronization (`last_seen`) with live presence indicators that reflect active connectivity.
* **Dynamic User Profile**: Partner profile photo rendering with elegant monogram fallbacks and neutral, universal design.

### 👁️ 4. Ephemeral "View-Once" Media Vault
* **Self-Destructing Media**: Share photos and videos configured to open once and immediately vanish from both devices.
* **Atomic Server-Side Shredding**: The backend physically shreds and permanently deletes expired media files from the filesystem immediately upon viewing.
* **Shared Media Gallery**: Categorized media hub with filter tabs for **Photos**, **Videos**, **Voice Notes**, and **Documents**.

### 📓 5. Shared Timeline & Private Notes
* **Collaborative Daily Log**: A shared space to record joint thoughts, projects, daily notes, and important milestones.
* **Memory Timeline**: Attach photos, status badges, and formatted notes to specific calendar dates with instant synchronization.
* **Privacy & Isolation**: Strictly restricted to the paired users; inaccessible to any external user or third party.

### 🛡️ 6. Enterprise-Grade Authentication & App Lock
* **Multi-Method 2FA**:
  * **TOTP Authenticator Apps**: Google Authenticator, Microsoft Authenticator, 1Password, Authy, Apple Passwords.
  * **Live QR Enrollment**: Standard `otpauth://` QR code scanning via `qr_flutter`.
  * **Email OTP Fallback**: 6-digit one-time passcodes sent via high-reliability Google SMTP (`smtp.gmail.com:587`).
  * **Hashed Backup Codes**: 8 single-use cryptographically random recovery codes hashed with SHA-256 for disaster recovery.
* **Biometric & Passcode Lock**: 4-digit PIN lock with native Fingerprint / Face ID unlock (`local_auth`) and automatic timeout locking.

### 🎨 7. Curated Design & Custom Themes
* **Modern Luxury Aesthetic**: Sleek glassmorphic surfaces, dark-mode first design, and refined micro-interactions.
* **6 Curated Color Palettes**: *Midnight Obsidian*, *Nordic Teal*, *Emerald Luxury*, *Neon Violet*, *Deep Indigo*, and *Velvet Slate*.
* **Universal 1-to-1 Design**: Free of relationship stereotypes or couple-exclusive language — tailored cleanly for any two people.

---

## 🏛️ System Architecture

```mermaid
graph TD
    subgraph "Flutter Mobile Client (Android & iOS)"
        A[App Entry / Splash Screen] --> B{Session Verification}
        B -->|Active Session| C[Passcode / Biometric Unlock]
        B -->|No Session| D[Login / Registration / 2FA]
        C --> E[1-to-1 Private Home Hub]
        
        E --> F[Shared Timeline & Notes]
        E --> G[Categorized Settings & Security Hub]
        E --> H[E2EE Messaging Engine]
        E --> I[WebRTC Calling Engine]
        E --> J[Shared Media Vault]
    end

    subgraph "FastAPI Server (Render Cloud — https://twoofus.onrender.com)"
        K[REST API Router & Auth Controller]
        L[E2EE Public Key Registry]
        M[Presence & Heartbeat Engine]
        N[SMTP Email Dispatcher]
        O[Zero-Knowledge Storage & File Shredder]
        P[WebSocket Call Signaling]
    end

    subgraph "Database Layer"
        Q[(Render PostgreSQL Managed Database)]
    end

    subgraph "WebRTC Peer-to-Peer Media Plane"
        R[Direct DTLS-SRTP Audio/Video Stream]
    end

    D <--> K
    H <--> L
    E <--> M
    D <--> N
    H <--> O
    I <--> P
    K <--> Q
    I <-->|P2P Media Exchange| R
```

---

## 🔐 Security & Cryptographic Architecture

| Layer | Protocol / Primitive | Implementation Details |
| :--- | :--- | :--- |
| **Key Agreement** | **Curve25519 (X25519 ECDH)** | Ephemeral & identity key pairs generated on-device via libsodium; private keys never leave local hardware. |
| **Payload Encryption** | **AES-256-GCM / XSalsa20** | Authenticated encryption with unique 96-bit / 192-bit cryptographic nonces per message. |
| **Calling Media** | **DTLS 1.2 / SRTP** | End-to-end encrypted voice and video media packets directly between clients. |
| **MITM Verification** | **60-digit Safety Code & QR** | SHA-256 digest comparison of paired public keys with live camera scanner verification. |
| **Two-Factor Auth** | **RFC 6238 TOTP & HMAC-SHA1** | Time-based 30-second rolling codes + 6-digit email OTPs + SHA-256 hashed single-use backup codes. |
| **Password Storage** | **Argon2id / PBKDF2-HMAC** | High-work-factor cryptographic password hashing with unique per-user salts. |
| **Zero-Knowledge Media** | **Atomic Disk Shredding** | Ephemeral view-once files are overwritten with random bytes and unlinked upon first read. |

---

## 🛡️ Security Model

TwoOfUs is architected from the ground up under a **Zero-Knowledge, Fail-Closed Security Model**. The application strictly isolates cryptographic trust to user device hardware, enforcing non-repudiable boundaries between end-to-end encrypted user content and operational server metadata.

### 1. Exact End-to-End Encryption (E2EE) Scope

| Domain | Cryptographic Primitive / Info Tag | Ciphertext Storage | Decryption Key Ownership |
| :--- | :--- | :--- | :--- |
| **Chat Messages** | X25519 ECDH + HKDF-SHA256 (`TwoOfUs-KeyExchange-v1`) + AES-256-GCM | Encrypted ciphertext + 96-bit unique nonce in `messages` table | Communicating devices only (derived from local private key + peer public key) |
| **Media Attachments (Images, Videos, Audio, Docs)** | Client-side AES-256-GCM (`TwoOfUs-Media-v1`) before upload | Ciphertext binary payload stored on disk; nonce and metadata in `media` table | Communicating devices only. Server receives encrypted bytes and cannot read media contents |
| **Shared Timeline & Diary Content** | Client-side AES-256-GCM (`TwoOfUs-Timeline-v1`) before upload | Ciphertext body + nonce stored in `diary_memories` table | Paired partners only. Legacy unencrypted memories are flagged `is_encrypted=false` for backward migration |
| **Timeline Photos** | Client-side AES-256-GCM (`TwoOfUs-Timeline-v1`) before upload | Ciphertext binary file on disk; photo nonce in `diary_memories` table | Paired partners only. Server cannot render or parse uploaded timeline photos |
| **Calling Audio & Video Streams** | WebRTC Unified Plan, DTLS 1.2 handshake, SRTP AES-128-CM/AEAD media plane | Ephemeral; media never touches server disk | Peer devices only via direct peer-to-peer WebRTC connection |

### 2. Non-E2EE Operational Metadata (Server-Visible)

To enable 1-to-1 routing, notification dispatch, and connection establishment, the server processes minimal, strictly segregated metadata:
* **User Identity & Pairing Directory**: User IDs (`int`), usernames, emails, bcrypt-hashed passwords, TOTP secrets, public keys (Curve25519 identity keys published for peer key agreement), and pairing mappings (`pairs` table).
* **Routing & Envelope Headers**: Sender ID, receiver ID, UTC created timestamps, message IDs, and payload byte sizes.
* **Call Session Records**: Caller ID, receiver ID, call type (`voice` / `video`), session status (`initiated`, `ongoing`, `ended`, `rejected`, `missed`), started/ended timestamps, and call duration in seconds. All call history resides strictly in the `call_sessions` table. **Plaintext `CALL_LOG` messages are completely prohibited and never written to the `messages` table.**
* **Connection & Presence**: Device push tokens, client platform (`android` / `ios`), heartbeat `last_seen` timestamps, and ephemeral typing indicators.

### 3. Fail-Closed Guarantees

* **Client-Side Fail Closed**: Plaintext fallbacks are strictly eliminated in `chat_screen.dart` and `media_composer_modal.dart`. If peer public keys are missing, corrupted, or cryptographic encapsulation fails, sending is blocked immediately with an inline error and manual retry action. Unencrypted user content is never transmitted across the wire.
* **Server-Side Fail Closed**: The FastAPI endpoints `/send-message` and `/media/upload` reject (`HTTP 400`) any user message or media upload where `is_encrypted=false`. Unencrypted transport is allowlisted exclusively for typed system event rows (`system`, `system_call_log`, `system_pairing_event`, `system_notification`).

### 4. Key-Change UX & Storage Migration

* **Hardware Pinned Storage**: Peer public keys are migrated from insecure SharedPreferences to hardware-backed secure storage (`FlutterSecureStorage` with Android Keystore / iOS Keychain).
* **Key-Change Detection**: If a partner's public key changes (e.g. after a device reinstall), the client detects the mismatch and renders an explicit, non-dismissible warning banner at the top of the chat:  
  `"Safety number changed. Tap to verify."`
* **Out-of-Band Safety Numbers**: Users can verify 60-digit numeric fingerprints or scan camera QR codes to cryptographically confirm their partner's identity and defeat Active Man-in-the-Middle (MITM) attacks.

### 5. Known Limitations & Threat Model (Based on Tests)

* **Traffic & Timing Analysis**: A state-level network adversary or compromised server operator can observe packet frequency, message timing, and ciphertext file sizes between the two communicating endpoints. TwoOfUs does not currently inject chaff or fixed-rate dummy packet padding.
* **Single-Device Cryptographic Identity**: Each account's private key is bound to local device storage. There is no cloud key escrow or multi-device message replication; re-logging into a new device without key export creates a fresh keypair and triggers safety number alerts for the partner.
* **Endpoint Compromise**: If an attacker achieves root access, physical passcode compromise, or memory inspection on an unlocked user device, plaintext can be extracted from memory. TwoOfUs mitigates this locally through biometric app locks (`local_auth`), background screen blurring, and automatic inactivity timeouts.
* **WebRTC NAT Relay Visibility**: When peer-to-peer connection cannot be established directly due to symmetric NATs, traffic relays through TURN servers. While DTLS-SRTP ensures TURN relays cannot decrypt audio/video packets, the relay operator can observe IP addresses, call timestamps, and data volume.

---

## 📁 Repository Structure

```
TwoOfUs/
├── backend/                       # FastAPI Python Backend
│   ├── app/
│   │   ├── core/                  # Database session, JWT security, configuration
│   │   ├── models/                # SQLAlchemy models (User, Pair, Message, Media, DiaryMemory, CallSession)
│   │   ├── routes/                # Endpoints (auth, users, messages, media, diary, call_signaling)
│   │   ├── schemas/               # Pydantic data validation schemas
│   │   └── services/              # SMTP email service, TOTP 2FA, zero-knowledge storage
│   ├── tests/                     # Penetration, security audit, and WebRTC integration test suites
│   ├── requirements.txt           # Python dependencies
│   ├── .env.example               # Backend environment variable template
│   └── pyproject.toml             # Python project configuration
│
├── frontend/
│   └── twoofus_flutter/           # Flutter Mobile Application
│       ├── lib/
│       │   ├── models/            # Data, message, and call session models
│       │   ├── screens/           # Chat, Home, Timeline, Profile, 2FA Setup, Security, Call screens
│       │   ├── services/          # E2EE cryptography, API client, WebRTC manager, signaling client
│       │   ├── theme/             # Dark glassmorphic design system and curated color palettes
│       │   ├── utils/             # Session persistence, encryption helpers, feedback banners
│       │   └── widgets/           # Image cropper, QR safety modal, media composer, biometric locks
│       ├── test/                  # Automated unit, E2EE crypto, and call security test suites
│       └── pubspec.yaml           # Flutter dependencies & platform assets
│
├── render.yaml                    # Production Render Cloud Blueprint
└── README.md                      # Project documentation
```

---

## 🚀 Getting Started

### 1. Prerequisites
- **Flutter SDK**: v3.12 or higher (`flutter --version`)
- **Python**: v3.11+ (`python --version`)
- **PostgreSQL** (production) or **SQLite** (local development)

---

### 2. Backend Setup (FastAPI)

```bash
# Navigate to backend directory
cd backend

# Create and activate Python virtual environment
python -m venv venv

# Windows PowerShell:
.\venv\Scripts\Activate.ps1
# macOS / Linux:
source venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Copy environment configuration
cp .env.example .env

# Run FastAPI backend locally:
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```
Interactive API documentation will be available at: **`http://localhost:8000/docs`**

---

### 3. Frontend Setup (Flutter Mobile)

```bash
# Navigate to Flutter frontend directory
cd frontend/twoofus_flutter

# Install Flutter packages
flutter pub get

# Run on a connected mobile device or emulator:
flutter run
```

---

### 4. Build Production Release APK

```bash
cd frontend/twoofus_flutter
flutter build apk --release
```
The compiled, optimized release APK will be generated at:  
`frontend/twoofus_flutter/build/app/outputs/flutter-apk/app-release.apk`

---

## 🧪 Quality Assurance & Automated Tests

TwoOfUs includes a test suite covering zero-knowledge encryption, IDOR vulnerability protection, view-once atomic shredding, multi-factor authentication, and WebRTC peer connection signaling.

### Backend Test Suite (FastAPI / pytest)

```bash
cd backend
py -3.11 -m pytest tests -v
```

| Test Suite | Test Cases | Status | Scope |
| :--- | :---: | :---: | :--- |
| `test_encryption_rejection.py` | 14 | ✅ **Passed** | Server-side fail-closed rejection of unencrypted messages and media |
| `test_security_audit.py` | 10 | ✅ **Passed** | IDOR protection, View-Once shredding, E2EE key registry, password lifecycle |
| `test_two_factor_auth.py` | 10 | ✅ **Passed** | TOTP enrollment, email OTPs, backup recovery codes, 2FA login intercepts |
| `test_diary_memories.py` | 8 | ✅ **Passed** | E2EE diary content and photo encryption, pair isolation, migration |
| `test_call_signaling_ws.py` | 7 | ✅ **Passed** | WebSocket auth, ICE candidate routing, SDP exchange, TURN credentials |
| `test_media_roundtrip.py` | 5 | ✅ **Passed** | Two-account media upload, decryption, tamper MAC validation |
| `test_call_signaling.py` | 3 | ✅ **Passed** | Call lifecycle, zero CALL_LOG in messages, history in call_sessions |
| **Total Backend Coverage** | **57** | ✅ **57 Passed (100%)** | Full automated backend test suite under Python 3.11 |

---

### Frontend Test Suite (Flutter)

```bash
cd frontend/twoofus_flutter
flutter test
```

| Test Suite | Tests | Status | Scope |
| :--- | :---: | :---: | :--- |
| `layout_responsiveness_test.dart` | 55 | ✅ **Passed** | Multi-screen responsive layout & zero text/overflow across phone & tablet |
| `visual_golden_test.dart` | 6 | ✅ **Passed** | Visual pixel-level golden tests for dark/light themes and components |
| `e2ee_security_test.dart` | 6 | ✅ **Passed** | X25519 HKDF derivation, AES-256-GCM fresh nonces, timeline encryption |
| `media_roundtrip_test.dart` | 6 | ✅ **Passed** | Two-account media roundtrip, partner key resolution, third-party tamper rejection |
| `call_signaling_test.dart` | 5 | ✅ **Passed** | Signaling deserialization, audio/speaker state toggles, Opus SDP sanitization |
| `call_security_test.dart` | 4 | ✅ **Passed** | Safety code determinism, avalanche effect, signaling integrity, zeroization |
| `key_change_banner_test.dart` | 2 | ✅ **Passed** | FlutterSecureStorage peer key pinning, warning banner on key change |
| `widget_test.dart` | 1 | ✅ **Passed** | Application smoke test and dependency tree validation |
| **Total Frontend Coverage** | **85** | ✅ **85/85 Passed (100%)** | Full client test suite covering cryptography, UI, and call states |

---

## 🌐 Cloud Deployment (Render.com + Neon + Cloudflare R2)

The backend runs on **Render.com** with **Neon Serverless PostgreSQL** and persistent **Cloudflare R2** object storage.

### 1. Database Configuration (Neon PostgreSQL)
Neon provides serverless PostgreSQL that scales to zero and drops idle connections. The backend is hardened with `pool_pre_ping=True`, `pool_recycle=300`, connect timeout, and initial cold-start retries.

* **Pooled Connection (`-pooler`)**:
  - In your [Neon Console](https://console.neon.tech), copy the **Pooled connection string** (`-pooler.us-east-2.aws.neon.tech`).
  - Neon's PgBouncer pooler efficiently handles concurrent web requests and cold starts.
  - In Render Dashboard (**twoofus-backend** -> **Environment**), set:
    ```env
    DATABASE_URL=postgresql://<user>:<password>@<endpoint>-pooler.us-east-2.aws.neon.tech/neondb?sslmode=require
    ```
* **Direct Connection (Optional for Migrations)**:
  - If desired for heavy administrative DDL operations, set `DATABASE_URL_DIRECT` to your direct (unpooled) Neon URL. If omitted, startup auto-migrations safely run over `DATABASE_URL`.
* **SSL and Channel Binding**:
  - Keep `sslmode=require` in the query string.
  - If `channel_binding=require` is present and unsupported by the client libpq or pooler, the backend automatically strips the parameter and falls back to standard SCRAM-SHA-256 over TLS without crashing.

---

### 2. Persistent Storage (Cloudflare R2 S3-Compatible Bucket)
Render containers use ephemeral disks that wipe `./uploads` on every deploy. Cloudflare R2 provides zero-egress-fee, persistent object storage.

1. **Create Bucket**:
   - In your [Cloudflare Dashboard](https://dash.cloudflare.com), navigate to **R2** -> **Create bucket** (e.g. `twoofus-media`).
2. **Create API Token**:
   - Go to **R2** -> **Manage R2 API Tokens** -> **Create API Token**.
   - Permissions: **Object Read & Write**.
   - Specify bucket: Apply to `twoofus-media`.
   - Copy the **Access Key ID**, **Secret Access Key**, and the account's **S3 Endpoint URL** (`https://<account_id>.r2.cloudflarestorage.com`).
3. **Configure Render Environment Variables**:
   ```env
   STORAGE_BACKEND=s3
   S3_ENDPOINT_URL=https://<account_id>.r2.cloudflarestorage.com
   S3_BUCKET=twoofus-media
   S3_REGION=auto
   S3_ACCESS_KEY_ID=<your_r2_access_key_id>
   S3_SECRET_ACCESS_KEY=<your_r2_secret_access_key>
   ```
   *Note: If `STORAGE_BACKEND=s3` is set but credentials are missing, the server logs a loud warning and falls back to ephemeral `LocalStorage` instead of crashing.*

---

### 3. Health Check & Monitoring
The `/health` endpoint checks all critical dependencies and always returns HTTP 200 so Render does not terminate the container during third-party blips:
```bash
curl https://twoofus.onrender.com/health
```
**Healthy Response:**
```json
{
  "status": "ok",
  "app": "TwoOfUs",
  "version": "1.0.0",
  "db": "ok",
  "storage": "ok",
  "time": "2026-10-10T19:15:24.796074Z"
}
```
* Status values:
  - `db`: `"ok"` (successful `SELECT 1`) | `"error"` (connection probe failed)
  - `storage`: `"ok"` (S3 bucket accessible) | `"local"` (LocalStorage active) | `"error"` (S3 check failed)

---

### 4. Rollback Path
* **Instant Dashboard Rollback**:
  - In [Render Dashboard](https://dashboard.render.com), go to **twoofus-backend** -> **Deploys**.
  - Locate the previous successful deploy, click **...**, and choose **Rollback to this deploy**.
* **Git Rollback**:
  - `git revert <commit-hash>` followed by `git push origin main`.

---

### 5. Legacy Client Rejection Notice (Fail-Closed E2EE)
Clients running older application builds that attempt to transmit unencrypted user content receive an **HTTP 400 Bad Request** error:
* **Messages** (`POST /send-message`):
  `{"detail": "Unencrypted user content is rejected. End-to-end encryption is required."}`
* **Media** (`POST /media/upload`):
  `{"detail": "Unencrypted media uploads are rejected. End-to-end encryption is required."}`
* **Missing Keys/Nonces**:
  `{"detail": "Encrypted messages must include a nonce"}`
  `{"detail": "Encrypted media uploads cannot have empty encrypted_media_key"}`

The Flutter application automatically catches these 400 responses and displays an "Update Required" dialog directing users to download the latest client release.

---

## 🔒 Privacy Commitment

TwoOfUs is built upon mathematical privacy. It is not an ad network, does not collect analytics, and cannot view your communications. Your conversations, calls, and shared moments belong exclusively to the **Two of You**.

---

## 📄 License

Private & Open-Source — Crafted with pride for secure, private communication.
