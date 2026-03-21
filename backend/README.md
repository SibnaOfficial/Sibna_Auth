# SIBNA Authentication System — v3.0.0

Backend authentication service for SIBNA. Built with FastAPI and Python 3.11.

## Features

- SIM card auto-detection and verification
- Email OTP (6 digits, cryptographically secure)
- Challenge-response authentication with device tracking
- Account recovery via registered email
- JWT session tokens (validated on every protected request)
- Full audit logging
- Rate limiting (Redis with in-memory fallback)
- Multi-device management

## Security changes in v3.0

- OTP generated with `secrets.randbelow` (CSPRNG) — replaces insecure `random.randint`
- OTP stored as HMAC-SHA256 hash — never as plaintext
- OTP comparison uses `hmac.compare_digest` — prevents timing attacks
- All protected endpoints require `Authorization: Bearer <token>`
- Account recovery returns identical response regardless of match — prevents user enumeration
- `SECRET_KEY` and `JWT_SECRET` raise errors at startup if unset in production
- CORS limited to explicit origin list — no wildcards in production
- SIM verification does not store raw phone numbers in the database

## Quick start

```bash
cp .env.example .env
# Edit .env — set SECRET_KEY, JWT_SECRET, and SMTP credentials at minimum
bash start.sh
```

## Docker

```bash
cp .env.example .env
# Edit .env
docker compose up --build
```

## Environment variables

See `.env.example` for the full list.

Generate secure values:
```bash
python3 -c "import secrets; print(secrets.token_hex(32))"
```

## API endpoints

| Method | Path | Auth | Description |
|---|---|---|---|
| POST | `/auth/sim/verify` | No | Verify SIM number |
| POST | `/auth/register` | No | Register new account |
| POST | `/auth/challenge` | No | Request login challenge |
| POST | `/auth/verify-challenge` | No | Verify challenge, get token |
| POST | `/auth/link-email` | No | Send email OTP |
| POST | `/auth/verify-otp` | No | Verify OTP, get token |
| POST | `/auth/recovery/initiate` | No | Start account recovery |
| POST | `/auth/update-profile` | Yes | Update name |
| GET | `/auth/me` | Yes | Get own account info |
| GET | `/auth/devices` | Yes | List registered devices |
| DELETE | `/auth/devices` | Yes | Remove a device |
| POST | `/auth/validate-phone` | No | Validate phone number |
| GET | `/health` | No | Health check |
