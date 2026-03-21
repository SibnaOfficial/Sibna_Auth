# SIBNA Auth

Secure authentication system for SIBNA applications.

## Architecture

```
sibna-auth/
├── backend/          FastAPI — Python 3.11
│   ├── main.py       All routes and business logic
│   ├── config.py     Configuration — reads from environment
│   ├── requirements.txt
│   ├── Dockerfile
│   ├── docker-compose.yml
│   ├── .env.example  Copy to .env and fill in values
│   └── start.sh      Local development launcher
└── frontend/         Flutter mobile application
    ├── lib/
    │   ├── main.dart
    │   ├── core/
    │   │   ├── constants/   Base URL, colors
    │   │   ├── services/    ApiService — all HTTP calls
    │   │   └── theme/       AppTheme
    │   └── features/
    │       ├── auth/        SplashScreen, AuthScreen
    │       └── vault/       VaultScreen
    └── pubspec.yaml
```

## Authentication flow

```
1. App launch
   SplashScreen checks JWT validity
   Valid → VaultScreen
   Invalid / missing → AuthScreen

2. Registration (new user)
   SIM detected → SIM verify → confirm profile → VaultScreen
   No SIM → enter phone → enter email → OTP → VaultScreen

3. Recovery (existing user, new device)
   Enter phone → enter email → OTP → VaultScreen

4. Login (existing user, known device)
   Challenge request → sign challenge → token → VaultScreen
```

## Getting started

### Backend

```bash
cd backend
cp .env.example .env      # Fill in all values
bash start.sh             # Local development
# or
docker compose up --build # With Docker
```

### Flutter

```bash
# Development (Android emulator)
flutter run --dart-define=BASE_URL=http://10.0.2.2:8000

# Development (physical device on same network)
flutter run --dart-define=BASE_URL=http://192.168.x.x:8000

# Production build
flutter build apk --dart-define=BASE_URL=https://api.sibna.dev
```

## Security notes

- OTPs expire in 5 minutes and are stored as HMAC-SHA256 hashes
- All protected API endpoints require `Authorization: Bearer <token>`
- JWT tokens are stored in `flutter_secure_storage` (encrypted on-device)
- Token expiry is validated on every app launch in `SplashScreen`
- Set `CORS_ORIGINS` to your actual domain in production — never use `*`
- Run `pip install cargo-audit` periodically to check for dependency vulnerabilities
