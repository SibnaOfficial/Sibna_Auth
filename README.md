je# SIBNA Authentication System

![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Flutter](https://img.shields.io/badge/Flutter-%2302569B.svg?logo=Flutter&logoColor=white)
![Python](https://img.shields.io/badge/Python-3776AB?logo=python&logoColor=white)
![FastAPI](https://img.shields.io/badge/FastAPI-005571?style=flat&logo=fastapi)

An Enterprise-grade Authentication and Session Management System featuring auto-OTP generation, hardware-level JWT encryption, and a premium Glassmorphism UI/UX.

---

## 🚀 Features

### Frontend (Flutter)
*   **Ultra-Premium UI/UX:** Dark-themed aesthetic inspired by top-tier FinTech and Enterprise applications.
*   **Hardware Encryption:** JSON Web Tokens (JWT) are securely stored in the iOS Keychain and Android Keystore (`flutter_secure_storage`).
*   **Smart Auto-Login:** A beautiful Splash Screen intercepts the app launch, authenticates the hardware token in the background, and seamlessly routes to the dashboard bypassing the login screen.
*   **Dynamic SIM Detection:** Intelligently reads the physical SIM card to auto-fill phone numbers for frictionless onboarding.
*   **True Hardware UUIDs:** Extracts actual device identity (`device_info_plus`) rather than relying on mock identifiers.

### Backend (Python/FastAPI)
*   **Enterprise JWT Sessions:** Issues signed, short-lived or long-lived JSON Web Tokens upon successful OTP verification using `PyJWT`.
*   **High-End HTML Emails:** Dispatches ultra-premium, dark-themed HTML verification emails complete with elegant phone-number masking (e.g. `+213 •••••• 04`).
*   **Bulletproof Rate Limiting:** Advanced in-memory rate-limiting prevents OTP spam attacks (Max 5 attempts / 30 mins).
*   **100% Global Standards:** Fully localized in professional English (Responses, Country codes, Console Logs).

---

## 📁 Project Structure

```bash
Auth0/
├── backend/                # Python FastAPI Server
│   ├── main.py             # Core API routing, JWT generation, & SMTP Logic
│   ├── config.py           # Environment Variables (Secrets, SMTP, Expirations)
│   ├── models/             # Database Schemas (Users, OTPs, Devices)
│   └── requirements.txt    # Python dependencies
│
└── frontend/               # Flutter Application
    ├── lib/
    │   ├── core/           # Constants, Theme Config, & API Services
    │   └── features/       # 
    │       ├── auth/       # Splash Screen, OTP verification, UI logic
    │       └── vault/      # The protected dashboard feature
    └── pubspec.yaml        # Flutter dependencies
```

---

## 🛠️ Quick Start

### 1. Backend Setup
```bash
cd backend
python -m venv venv
# Windows
venv\Scripts\activate
# Mac/Linux
source venv/bin/activate

pip install -r requirements.txt
# Set your environment variables in a .env file (SMTP credentials, JWT secret)
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

### 2. Frontend Setup
```bash
cd frontend
flutter pub get
# Update the API baseUrl in lib/core/constants/constants.dart to point to your backend IP
flutter run
```

---

## 🛡️ Security Architecture
1. **Initial Flow:** User enters Phone/Email -> Backend limits rate -> Backend dispatches beautiful 6-digit OTP Email.
2. **Verification:** User enters OTP -> Backend verifies hash -> Backend signs a 30-day JWT -> Frontend receives and encrypts JWT to hardware.
3. **Session Re-entry:** User opens app -> Splash Screen reads Keystore -> Validates JWT -> Auto-routes to internal app views.

## 📝 License
This project is licensed under the MIT License - see the LICENSE file for details.
