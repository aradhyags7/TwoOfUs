# TwoOfUs — Private & Secure Couple Space 💑🔒

**TwoOfUs** is an end-to-end encrypted (E2EE) private couple app built with **Flutter** and **FastAPI**. It provides a dedicated, intimate digital space for two partners featuring real-time encrypted messaging, ephemeral view-once media, interactive shared calendar diary & scrapbook photo album, cryptographic safety number QR code verification, and romantic custom themes.

---

## 🌟 Key Features

- **🔐 True End-to-End Encryption (E2EE)**:
  - **Key Exchange**: X25519 (Curve25519 ECDH) key agreement.
  - **Key Derivation**: HKDF-SHA256 with distinct domain separation tags for messages, media keys, and safety numbers.
  - **Symmetric Cipher**: AES-256-GCM authenticated encryption with unique 96-bit nonces.
  - **Zero-Knowledge Backend**: Plaintext, private keys, and unencrypted media NEVER touch the server or disk.
- **🛡️ Cryptographic Safety Verification & QR Code**:
  - ISO/IEC 18004 standard QR Code generation and 60-digit safety numbers (Signal/WhatsApp standard).
  - Scan partner's QR code or compare numbers to verify authenticity and prevent Man-in-the-Middle (MITM) attacks.
- **👁️ Server-Enforced View-Once Media**:
  - One-time decryption and atomic file shredding upon consumption with HTTP 410 Gone enforcement.
- **📔 Couple's Shared Diary & Memory Scrapbook**:
  - Interactive calendar matrix with glowing activity heat-dots.
  - Attach love notes, mood emojis, and photos to ANY date.
  - Real-time synchronization between paired partners.
- **🎨 Dynamic Romantic Themes**:
  - Multiple curated romantic palettes (Crimson Romance, Velvet Night, Amethyst Glow, Rose Gold, etc.).
- **🔒 App Security & Biometric Lock**:
  - App-level 4-digit passcode protection, biometric authentication, and inactivity auto-lock.

---

## 🏗️ Architecture & Project Structure

```
TwoOfUs/
├── backend/                  # FastAPI Python Backend
│   ├── app/
│   │   ├── core/             # Database & JWT Security configurations
│   │   ├── models/           # SQLAlchemy database models (User, Pair, Message, Media, DiaryMemory)
│   │   ├── routes/           # REST & WebSocket API endpoints
│   │   ├── schemas/          # Pydantic request/response schemas
│   │   └── services/         # Storage & crypto services
│   ├── tests/                # Automated security & penetration test suites
│   ├── requirements.txt      # Python dependencies
│   └── .env.example          # Environment variable template
│
├── frontend/
│   └── twoofus_flutter/      # Flutter Cross-Platform Client (Android, iOS, Web, Desktop)
│       ├── lib/
│       │   ├── models/       # Data models
│       │   ├── screens/      # Chat, Home, Diary, Profile, Security screens
│       │   ├── services/     # E2EE, API, WebSocket, and Security services
│       │   ├── theme/        # Theme controllers & palettes
│       │   └── widgets/      # QR verification modal, media bubbles, custom UI
│       └── test/             # Flutter unit & cryptographic security tests
│
└── docs/                     # Documentation & specifications
```

---

## 🚀 Getting Started

### 1. Prerequisites
- **Flutter SDK** (v3.12+ recommended)
- **Python 3.10+**

### 2. Backend Setup (FastAPI)
```bash
cd backend
python -m venv venv
# Windows:
.\venv\Scripts\activate
# Linux/macOS:
source venv/bin/activate

pip install -r requirements.txt
cp .env.example .env

# Run FastAPI dev server:
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

### 3. Frontend Setup (Flutter)
```bash
cd frontend/twoofus_flutter
flutter pub get

# Run on connected device or emulator:
flutter run
```

---

## 🧪 Running Automated Tests

### Backend Tests
```bash
cd backend
python tests/test_security_audit.py
python tests/test_diary_memories.py
```

### Frontend Cryptographic & Widget Tests
```bash
cd frontend/twoofus_flutter
flutter test
```

---

## 📄 License
Private & Proprietary — Built with ❤️ for Two.
