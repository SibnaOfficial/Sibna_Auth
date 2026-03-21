"""
SIBNA Authentication System — v3.0.0
======================================
Secure authentication system supporting:
- SIM card auto-detection and verification
- Phone number validation (libphonenumber)
- Email OTP (6 digits, cryptographically secure)
- JWT session tokens
- Challenge-response authentication
- Account recovery via email
- Multi-device management
- Full audit logging
"""

import hmac
import hashlib
import time
import secrets
import os
import json
import asyncio
import smtplib
import logging
from contextlib import asynccontextmanager
from datetime import datetime, timedelta, timezone
from typing import Optional, Dict, Any

from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart

import jwt
from fastapi import FastAPI, HTTPException, Request, BackgroundTasks, Depends, Security
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from pydantic import BaseModel, EmailStr, Field, field_validator

import phonenumbers
from phonenumbers import carrier, geocoder, timezone as ph_timezone

from sqlalchemy import create_engine, Column, Integer, String, Float, Text, Boolean, UniqueConstraint
from sqlalchemy.orm import DeclarativeBase, sessionmaker, Session
import redis

from config import Config

# ── Logging ───────────────────────────────────────────────────────────────────
# Use structured logging — never log sensitive values (OTP, keys, tokens)
logging.basicConfig(
    level=logging.DEBUG if Config.DEBUG else logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger("sibna.auth")

# ── Startup / Shutdown ────────────────────────────────────────────────────────

@asynccontextmanager
async def lifespan(app: FastAPI):
    Config.validate()
    init_db()
    logger.info("SIBNA Auth started — environment: %s", Config.ENVIRONMENT)
    yield
    logger.info("SIBNA Auth shutting down")


# ── Application ───────────────────────────────────────────────────────────────

app = FastAPI(
    title="SIBNA Authentication API",
    description="Secure authentication — SIM verification, Email OTP, Challenge-Response",
    version="3.0.0",
    lifespan=lifespan,
    # Disable docs in production
    docs_url="/docs" if not (os.environ.get("ENVIRONMENT") == "production") else None,
    redoc_url=None,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=Config.CORS_ORIGINS,
    allow_credentials=True,
    allow_methods=["GET", "POST", "DELETE"],
    allow_headers=["Authorization", "Content-Type"],
)

# ── Database ──────────────────────────────────────────────────────────────────

class Base(DeclarativeBase):
    pass

engine_args: Dict[str, Any] = {}
if Config.DATABASE_URL.startswith("sqlite"):
    engine_args["connect_args"] = {"check_same_thread": False}

engine = create_engine(Config.DATABASE_URL, **engine_args)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

# ── Redis ─────────────────────────────────────────────────────────────────────

_redis_client: Optional[redis.Redis] = None
REDIS_AVAILABLE = False

try:
    _redis_client = redis.from_url(Config.REDIS_URL, decode_responses=True)
    _redis_client.ping()
    REDIS_AVAILABLE = True
    logger.info("Redis connected at %s", Config.REDIS_URL)
except Exception:
    logger.warning("Redis unavailable — falling back to in-memory rate limiting (not suitable for multi-instance deployments)")

_MEM_RATE_LIMITS: Dict[str, Dict] = {}

# ── Models ────────────────────────────────────────────────────────────────────

class User(Base):
    __tablename__ = "users"
    id          = Column(Integer, primary_key=True, index=True)
    p_hash      = Column(String, unique=True, index=True, nullable=False)
    phone_number = Column(String)
    salt        = Column(String, nullable=False)
    pub_key     = Column(String)
    email_hash  = Column(String)
    device_id   = Column(String)
    country_code = Column(String)
    sim_verified = Column(Boolean, default=False)
    is_verified  = Column(Boolean, default=False)
    email_verified = Column(Boolean, default=False)
    first_name  = Column(String)
    last_name   = Column(String)
    created_at  = Column(Float)
    last_login  = Column(Float)
    login_count = Column(Integer, default=0)


class OTP(Base):
    __tablename__ = "otps"
    id         = Column(Integer, primary_key=True)
    p_hash     = Column(String, index=True, nullable=False)
    otp_hash   = Column(String, nullable=False)   # Store hash, never plaintext
    otp_type   = Column(String, default="email")
    target     = Column(String)
    expires    = Column(Float, nullable=False)
    used       = Column(Boolean, default=False)
    attempts   = Column(Integer, default=0)
    created_at = Column(Float)


class Challenge(Base):
    __tablename__ = "challenges"
    id             = Column(String, primary_key=True)
    p_hash         = Column(String, index=True, nullable=False)
    challenge_data = Column(Text, nullable=False)
    expires        = Column(Float, nullable=False)
    used           = Column(Boolean, default=False)
    created_at     = Column(Float)


class Device(Base):
    __tablename__ = "devices"
    id          = Column(Integer, primary_key=True)
    p_hash      = Column(String, index=True, nullable=False)
    device_id   = Column(String, nullable=False)
    device_name = Column(String)
    device_type = Column(String)
    last_used   = Column(Float)
    is_primary  = Column(Boolean, default=False)
    is_verified = Column(Boolean, default=False)
    created_at  = Column(Float)
    __table_args__ = (UniqueConstraint("p_hash", "device_id", name="_p_hash_device_id_uc"),)


class SIMVerification(Base):
    __tablename__ = "sim_verifications"
    id           = Column(Integer, primary_key=True)
    p_hash       = Column(String, nullable=False)
    match_result = Column(Boolean)
    verified_at  = Column(Float)
    ip_address   = Column(String)


class AuditLog(Base):
    __tablename__ = "audit_log"
    id         = Column(Integer, primary_key=True)
    p_hash     = Column(String)
    action     = Column(String, nullable=False)
    details    = Column(Text)
    ip_address = Column(String)
    user_agent = Column(Text)
    timestamp  = Column(Float, nullable=False)


def init_db() -> None:
    Base.metadata.create_all(bind=engine)


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

# ── Pydantic Schemas ──────────────────────────────────────────────────────────

class PhoneRequest(BaseModel):
    phone: str = Field(..., description="Phone number in E.164 or local format")
    country_code: Optional[str] = Field(None, description="ISO country code, e.g. 'DZ'")
    device_id: Optional[str] = None
    device_name: Optional[str] = None
    device_type: Optional[str] = None


class SIMVerifyRequest(BaseModel):
    sim_phone: Optional[str] = None
    entered_phone: str
    country_code: Optional[str] = None
    device_id: str
    device_name: Optional[str] = None
    device_type: Optional[str] = None


class RegisterRequest(PhoneRequest):
    pub_key: str = Field(..., min_length=10, description="Ed25519 public key (base64)")
    sim_verified: bool = False


class ChallengeRequest(PhoneRequest):
    pass


class VerifyChallengeRequest(BaseModel):
    challenge_id: str
    signed_challenge: str  # Base64-encoded Ed25519 signature
    device_id: str
    device_name: Optional[str] = None
    device_type: Optional[str] = None


class EmailLinkRequest(BaseModel):
    phone: str
    email: EmailStr
    country_code: Optional[str] = None


class VerifyOTPRequest(BaseModel):
    phone: str
    otp: str = Field(..., min_length=6, max_length=6)
    country_code: Optional[str] = None
    new_pub_key: Optional[str] = None
    new_device_id: Optional[str] = None

    @field_validator("otp")
    @classmethod
    def otp_must_be_digits(cls, v: str) -> str:
        if not v.isdigit():
            raise ValueError("OTP must contain only digits")
        return v


class RecoveryRequest(PhoneRequest):
    email: EmailStr


class ProfileUpdateRequest(BaseModel):
    phone: str
    country_code: Optional[str] = None
    first_name: str = Field(..., min_length=1, max_length=64)
    last_name: str = Field(..., min_length=1, max_length=64)


class RemoveDeviceRequest(BaseModel):
    phone: str
    device_id: str
    country_code: Optional[str] = None

# ── Auth middleware ───────────────────────────────────────────────────────────

bearer_scheme = HTTPBearer(auto_error=False)


def require_auth(
    credentials: Optional[HTTPAuthorizationCredentials] = Security(bearer_scheme),
) -> str:
    """Dependency — validates JWT and returns p_hash."""
    if credentials is None:
        raise HTTPException(401, "Authentication required")
    try:
        payload = jwt.decode(
            credentials.credentials,
            Config.JWT_SECRET,
            algorithms=["HS256"],
        )
        p_hash: str = payload.get("sub", "")
        if not p_hash:
            raise HTTPException(401, "Invalid token")
        return p_hash
    except jwt.ExpiredSignatureError:
        raise HTTPException(401, "Token expired")
    except jwt.InvalidTokenError:
        raise HTTPException(401, "Invalid token")


def _issue_jwt(p_hash: str) -> str:
    payload = {
        "sub": p_hash,
        "iat": datetime.now(timezone.utc),
        "exp": datetime.now(timezone.utc) + timedelta(days=Config.JWT_EXPIRY_DAYS),
    }
    return jwt.encode(payload, Config.JWT_SECRET, algorithm="HS256")

# ── Cryptographic helpers ─────────────────────────────────────────────────────

def _hmac_sha256(key: str, message: str) -> str:
    return hmac.new(
        key.encode(),
        message.encode(),
        hashlib.sha256,
    ).hexdigest()


def generate_p_hash(phone: str, country_code: Optional[str] = None) -> str:
    """Derive a pseudonymous identifier from a phone number."""
    normalized = normalize_phone(phone, country_code)
    return _hmac_sha256(Config.SECRET_KEY, normalized)


def generate_email_hash(email: str) -> str:
    return _hmac_sha256(Config.SECRET_KEY, email.lower().strip())


def generate_otp() -> str:
    """Generate a cryptographically secure 6-digit OTP."""
    # secrets.randbelow is CSPRNG-backed; random.randint is NOT safe here
    return "".join(str(secrets.randbelow(10)) for _ in range(Config.OTP_LENGTH))


def hash_otp(otp: str) -> str:
    """Hash an OTP before storing it. Never store plaintext OTPs."""
    return _hmac_sha256(Config.SECRET_KEY, otp)


def verify_otp_hash(otp_candidate: str, stored_hash: str) -> bool:
    """Constant-time comparison to prevent timing attacks."""
    candidate_hash = hash_otp(otp_candidate)
    return hmac.compare_digest(candidate_hash, stored_hash)

# ── Phone helpers ─────────────────────────────────────────────────────────────

def normalize_phone(phone: str, country_code: Optional[str] = None) -> str:
    try:
        region = country_code.upper() if country_code else None
        parsed = phonenumbers.parse(phone, region)
        if not phonenumbers.is_valid_number(parsed):
            raise ValueError("Invalid phone number")
        return phonenumbers.format_number(parsed, phonenumbers.PhoneNumberFormat.E164)
    except phonenumbers.NumberParseException as exc:
        raise ValueError(f"Cannot parse phone number: {exc}") from exc


def get_phone_info(phone: str, country_code: Optional[str] = None) -> Dict[str, Any]:
    normalized = normalize_phone(phone, country_code)
    parsed = phonenumbers.parse(normalized, None)
    return {
        "normalized": normalized,
        "country_code": phonenumbers.region_code_for_number(parsed),
        "country_name": geocoder.description_for_number(parsed, "en"),
        "carrier": carrier.name_for_number(parsed, "en"),
        "is_valid": phonenumbers.is_valid_number(parsed),
        "number_type": str(phonenumbers.number_type(parsed)),
    }


def compare_phone_numbers(
    phone1: str, phone2: str, country_code: Optional[str] = None
) -> Dict[str, Any]:
    """
    Compare two phone numbers for SIM verification.
    Uses only E.164 normalized exact match and suffix match (≥10 digits).
    The original substring match has been removed — it allowed any subset
    to match any superset, which is a security flaw.
    """
    try:
        norm1 = normalize_phone(phone1, country_code)
        norm2 = normalize_phone(phone2, country_code)

        clean1 = norm1.lstrip("+")
        clean2 = norm2.lstrip("+")

        exact_match = hmac.compare_digest(clean1, clean2)

        # Suffix match: last 10 digits must be identical
        suffix_match = False
        min_len = min(len(clean1), len(clean2))
        if min_len >= 10 and not exact_match:
            suffix_match = hmac.compare_digest(clean1[-10:], clean2[-10:])

        is_match = exact_match or suffix_match
        return {
            "is_match": is_match,
            "confidence": "high" if exact_match else ("medium" if suffix_match else "low"),
            "phone1_normalized": norm1,
            "phone2_normalized": norm2,
        }
    except ValueError as exc:
        return {"is_match": False, "confidence": "error", "error": str(exc)}

# ── Rate limiting ─────────────────────────────────────────────────────────────

def check_rate_limit(identifier: str, action: str, max_attempts: int = 5) -> bool:
    key = f"rl:{action}:{identifier}"
    if REDIS_AVAILABLE and _redis_client:
        try:
            count = _redis_client.get(key)
            return int(count or 0) < max_attempts
        except Exception:
            pass
    entry = _MEM_RATE_LIMITS.get(key)
    if not entry or time.time() > entry["expires"]:
        return True
    return entry["count"] < max_attempts


def record_rate_limit(identifier: str, action: str, window: Optional[int] = None) -> None:
    key = f"rl:{action}:{identifier}"
    win = window or Config.RATE_LIMIT_WINDOW
    if REDIS_AVAILABLE and _redis_client:
        try:
            pipe = _redis_client.pipeline()
            pipe.incr(key)
            pipe.expire(key, win)
            pipe.execute()
            return
        except Exception:
            pass
    now = time.time()
    entry = _MEM_RATE_LIMITS.get(key)
    if not entry or now > entry["expires"]:
        _MEM_RATE_LIMITS[key] = {"count": 1, "expires": now + win}
    else:
        entry["count"] += 1

# ── Audit logging ─────────────────────────────────────────────────────────────

def log_action(
    db: Session,
    p_hash: str,
    action: str,
    details: Optional[str] = None,
    request: Optional[Request] = None,
) -> None:
    db.add(AuditLog(
        p_hash=p_hash,
        action=action,
        details=details,
        ip_address=request.client.host if request else None,
        user_agent=request.headers.get("user-agent") if request else None,
        timestamp=time.time(),
    ))
    db.commit()

# ── Email ─────────────────────────────────────────────────────────────────────

def _mask_phone(phone: str) -> str:
    if not phone or len(phone) <= 6:
        return "your account"
    return f"{phone[:4]} {'•' * (len(phone) - 6)} {phone[-2:]}"


async def send_otp_email(target_email: str, otp_code: str, phone_hint: Optional[str] = None) -> bool:
    """
    Send OTP email.
    Security: otp_code is NOT logged at any level.
    """
    masked_phone = _mask_phone(phone_hint or "")

    def _blocking() -> bool:
        subject = f"{otp_code} is your SIBNA verification code"
        html = f"""<!DOCTYPE html>
<html><head><meta charset="utf-8">
<style>
body{{background:#080808;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;color:#fff;margin:0;padding:0}}
.w{{padding:40px 20px;text-align:center}}
.c{{max-width:480px;margin:0 auto;background:#121212;padding:48px;border-radius:32px;border:1px solid rgba(255,255,255,.08)}}
.logo{{font-size:32px;font-weight:900;letter-spacing:-1.5px;margin-bottom:40px;text-transform:uppercase}}
.title{{font-size:20px;font-weight:500;color:rgba(255,255,255,.6);margin-bottom:12px}}
.phone{{font-size:14px;color:#555;margin-bottom:32px;font-family:monospace;letter-spacing:1px}}
.otp-wrap{{padding:24px;background:rgba(255,255,255,.03);border-radius:20px;border:1px solid rgba(255,255,255,.05);margin:24px 0}}
.otp{{color:#fff;font-size:48px;font-weight:800;letter-spacing:10px}}
.expiry{{font-size:14px;color:#888;margin-top:16px}}
.hl{{color:#fff;font-weight:700}}
.note{{color:#555;font-size:12px;margin-top:30px;line-height:1.6;max-width:80%;margin-left:auto;margin-right:auto}}
.footer{{margin-top:50px;font-size:11px;color:#333;letter-spacing:.5px;text-transform:uppercase;border-top:1px solid rgba(255,255,255,.05);padding-top:30px}}
</style></head>
<body><div class="w"><div class="c">
<div class="logo">SIBNA</div>
<div class="title">Security Verification</div>
<div class="phone">For account {masked_phone}</div>
<div class="otp-wrap"><div class="otp">{otp_code}</div></div>
<p class="expiry">Expires in <span class="hl">{Config.OTP_EXPIRY // 60} minutes</span></p>
<div class="note">SIBNA will never call or message you asking for this code. If you did not request this, please secure your account immediately.</div>
<div class="footer">&copy; {datetime.now().year} SIBNA &bull; Secure Communication</div>
</div></div></body></html>"""

        text = (
            f"SIBNA Verification\n\n"
            f"Code: {otp_code}\n"
            f"Valid for {Config.OTP_EXPIRY // 60} minutes.\n"
            f"Account: {masked_phone}\n\n"
            f"If you did not request this, ignore this email."
        )

        msg = MIMEMultipart("alternative")
        msg["From"] = f"{Config.SMTP_FROM_NAME} <{Config.SMTP_USERNAME}>"
        msg["To"] = target_email
        msg["Subject"] = subject
        msg.attach(MIMEText(text, "plain"))
        msg.attach(MIMEText(html, "html"))

        with smtplib.SMTP_SSL(Config.SMTP_HOST, Config.SMTP_PORT, timeout=20) as server:
            server.login(Config.SMTP_USERNAME, Config.SMTP_PASSWORD)
            server.send_message(msg)
        return True

    try:
        loop = asyncio.get_event_loop()
        await loop.run_in_executor(None, _blocking)
        logger.info("OTP email delivered to %s", target_email)
        return True
    except Exception as exc:
        logger.error("SMTP failure for %s: %s", target_email, exc)
        return False

# ── Routes: Health ─────────────────────────────────────────────────────────────

@app.get("/")
async def root():
    return {
        "name": "SIBNA Authentication API",
        "version": "3.0.0",
        "status": "running",
        "docs": "/docs" if Config.DEBUG else "disabled in production",
    }


@app.get("/health")
async def health():
    return {"status": "healthy", "timestamp": time.time(), "redis": REDIS_AVAILABLE}

# ── Routes: SIM Verification ──────────────────────────────────────────────────

@app.post("/auth/sim/verify")
async def verify_sim(
    request: Request,
    req: SIMVerifyRequest,
    db: Session = Depends(get_db),
):
    client_ip = request.client.host
    if not check_rate_limit(client_ip, "sim_verify", 10):
        raise HTTPException(429, "Too many SIM verification attempts.")
    record_rate_limit(client_ip, "sim_verify")

    if not req.sim_phone:
        return {
            "status": "no_sim",
            "match": False,
            "message": "No SIM detected. Use email verification.",
            "fallback_options": [{"type": "email_otp", "endpoint": "/auth/link-email"}],
        }

    try:
        comparison = compare_phone_numbers(req.sim_phone, req.entered_phone, req.country_code)
    except Exception as exc:
        logger.warning("SIM compare error: %s", exc)
        raise HTTPException(400, "Could not compare phone numbers.")

    p_hash = generate_p_hash(req.entered_phone, req.country_code)

    # Audit — do NOT store raw SIM numbers in the DB
    db.add(SIMVerification(
        p_hash=p_hash,
        match_result=comparison["is_match"],
        verified_at=time.time(),
        ip_address=client_ip,
    ))
    db.commit()

    if comparison["is_match"]:
        return {
            "status": "match",
            "match": True,
            "confidence": comparison["confidence"],
            "phone": comparison["phone2_normalized"],
            "next_step": "register",  # Client must call /auth/register with pub_key
            "message": "SIM verified. Please complete registration with your public key.",
        }

    return {
        "status": "sim_mismatch",
        "match": False,
        "confidence": comparison["confidence"],
        "message": "SIM number does not match. Use email verification.",
        "fallback_options": [{"type": "email_otp", "endpoint": "/auth/link-email"}],
    }

# ── Routes: Registration ──────────────────────────────────────────────────────

@app.post("/auth/register")
async def register(
    request: Request,
    req: RegisterRequest,
    db: Session = Depends(get_db),
):
    client_ip = request.client.host
    if not check_rate_limit(client_ip, "register", 5):
        raise HTTPException(429, "Too many registration attempts.")
    record_rate_limit(client_ip, "register")

    try:
        phone_info = get_phone_info(req.phone, req.country_code)
    except ValueError as exc:
        raise HTTPException(400, str(exc))

    normalized = phone_info["normalized"]
    p_hash = generate_p_hash(normalized)

    if db.query(User).filter(User.p_hash == p_hash).first():
        raise HTTPException(409, "An account already exists with this number.")

    now = time.time()
    device_id = req.device_id or secrets.token_urlsafe(32)

    user = User(
        p_hash=p_hash,
        phone_number=normalized,
        salt=secrets.token_hex(32),
        pub_key=req.pub_key,
        country_code=phone_info.get("country_code"),
        sim_verified=req.sim_verified,
        is_verified=True,
        created_at=now,
        last_login=now,
        login_count=1,
    )
    db.add(user)

    db.add(Device(
        p_hash=p_hash,
        device_id=device_id,
        device_name=req.device_name,
        device_type=req.device_type,
        is_primary=True,
        is_verified=True,
        last_used=now,
        created_at=now,
    ))
    db.commit()

    log_action(db, p_hash, "register", f"country={phone_info.get('country_code')} sim={req.sim_verified}", request)
    logger.info("New account registered: %s", p_hash[:8])

    return {
        "status": "success",
        "message": "Account registered successfully.",
        "data": {"phone": normalized, "device_id": device_id},
    }

# ── Routes: Challenge-Response ────────────────────────────────────────────────

@app.post("/auth/challenge")
async def get_challenge(
    request: Request,
    req: ChallengeRequest,
    db: Session = Depends(get_db),
):
    client_ip = request.client.host
    if not check_rate_limit(client_ip, "challenge", 10):
        raise HTTPException(429, "Too many challenge requests.")
    record_rate_limit(client_ip, "challenge")

    try:
        normalized = normalize_phone(req.phone, req.country_code)
    except ValueError as exc:
        raise HTTPException(400, str(exc))

    p_hash = generate_p_hash(normalized)
    user = db.query(User).filter(User.p_hash == p_hash).first()
    if not user:
        raise HTTPException(404, "Account not found. Please register first.")

    challenge_id = secrets.token_urlsafe(32)
    challenge_data = secrets.token_urlsafe(64)

    db.add(Challenge(
        id=challenge_id,
        p_hash=p_hash,
        challenge_data=challenge_data,
        expires=time.time() + Config.CHALLENGE_EXPIRY,
        created_at=time.time(),
    ))
    db.commit()

    return {
        "status": "challenge_ready",
        "challenge_id": challenge_id,
        "challenge": challenge_data,
        "expires_in": Config.CHALLENGE_EXPIRY,
    }


@app.post("/auth/verify-challenge")
async def verify_challenge(
    request: Request,
    req: VerifyChallengeRequest,
    db: Session = Depends(get_db),
):
    client_ip = request.client.host
    if not check_rate_limit(client_ip, "verify_challenge", 5):
        raise HTTPException(429, "Too many verification attempts.")
    record_rate_limit(client_ip, "verify_challenge")

    challenge = db.query(Challenge).filter(
        Challenge.id == req.challenge_id,
        Challenge.used.is_(False),
        Challenge.expires > time.time(),
    ).first()

    if not challenge:
        raise HTTPException(403, "Invalid or expired challenge.")

    user = db.query(User).filter(User.p_hash == challenge.p_hash).first()
    if not user:
        raise HTTPException(404, "Account not found.")

    # Mark challenge used immediately to prevent replay
    challenge.used = True
    db.commit()

    # TODO: verify req.signed_challenge against user.pub_key using Ed25519
    # Until implemented, challenge-response is authenticated by device possession only
    # Production deployments must implement signature verification here.

    device = db.query(Device).filter(
        Device.p_hash == challenge.p_hash,
        Device.device_id == req.device_id,
        Device.is_verified.is_(True),
    ).first()

    if not device:
        # Unknown device — require email verification before issuing token
        return {
            "status": "need_recovery",
            "message": "New device detected. Email verification required.",
            "action": "email_verification_required",
            "endpoint": "/auth/link-email",
        }

    now = time.time()
    user.last_login = now
    user.login_count = (user.login_count or 0) + 1
    device.last_used = now
    db.commit()

    token = _issue_jwt(challenge.p_hash)
    log_action(db, challenge.p_hash, "login", f"device={req.device_id}", request)

    return {"status": "success", "message": "Logged in successfully.", "token": token}

# ── Routes: Profile (authenticated) ──────────────────────────────────────────

@app.post("/auth/update-profile")
async def update_profile(
    request: Request,
    req: ProfileUpdateRequest,
    db: Session = Depends(get_db),
    p_hash_auth: str = Depends(require_auth),
):
    """Update profile. Requires a valid JWT."""
    try:
        normalized = normalize_phone(req.phone, req.country_code)
    except ValueError as exc:
        raise HTTPException(400, str(exc))

    p_hash = generate_p_hash(normalized)

    # Ensure the token belongs to the same account
    if p_hash != p_hash_auth:
        raise HTTPException(403, "Not authorized to update this account.")

    user = db.query(User).filter(User.p_hash == p_hash).first()
    if not user:
        raise HTTPException(404, "User not found.")

    user.first_name = req.first_name.strip()
    user.last_name = req.last_name.strip()
    db.commit()

    log_action(db, p_hash, "profile_update", None, request)
    return {"status": "success", "message": "Profile updated.", "next_step": "vault"}

# ── Routes: Email OTP ─────────────────────────────────────────────────────────

@app.post("/auth/link-email")
async def link_email(
    request: Request,
    background_tasks: BackgroundTasks,
    req: EmailLinkRequest,
    db: Session = Depends(get_db),
):
    client_ip = request.client.host
    if not check_rate_limit(client_ip, "link_email", Config.RESEND_OTP_LIMIT, Config.RESEND_OTP_WINDOW):
        raise HTTPException(429, "Too many attempts. Please try again in 30 minutes.")
    record_rate_limit(client_ip, "link_email", Config.RESEND_OTP_WINDOW)

    try:
        normalized = normalize_phone(req.phone, req.country_code)
    except ValueError as exc:
        raise HTTPException(400, str(exc))

    p_hash = generate_p_hash(normalized)

    otp_plain = generate_otp()
    otp_hash = hash_otp(otp_plain)   # Store hash only — never store plaintext

    db.add(OTP(
        p_hash=p_hash,
        otp_hash=otp_hash,
        otp_type="email",
        target=req.email,
        expires=time.time() + Config.OTP_EXPIRY,
        created_at=time.time(),
    ))

    user = db.query(User).filter(User.p_hash == p_hash).first()
    if user:
        user.email_hash = generate_email_hash(req.email)

    db.commit()

    # Send in background — otp_plain is passed to send function and NOT logged
    background_tasks.add_task(send_otp_email, req.email, otp_plain, normalized)
    log_action(db, p_hash, "link_email", f"email_hint={req.email[:3]}***", request)

    return {
        "status": "otp_sent",
        "message": "Verification code sent to your email.",
        "email_hint": req.email[:3] + "***@" + req.email.split("@")[-1],
        "expires_in": Config.OTP_EXPIRY,
    }


@app.post("/auth/verify-otp")
async def verify_otp(
    request: Request,
    req: VerifyOTPRequest,
    db: Session = Depends(get_db),
):
    client_ip = request.client.host
    if not check_rate_limit(client_ip, "verify_otp", 5):
        raise HTTPException(429, "Too many attempts.")
    record_rate_limit(client_ip, "verify_otp")

    try:
        normalized = normalize_phone(req.phone, req.country_code)
    except ValueError as exc:
        raise HTTPException(400, str(exc))

    p_hash = generate_p_hash(normalized)

    otp_record = (
        db.query(OTP)
        .filter(
            OTP.p_hash == p_hash,
            OTP.used.is_(False),
            OTP.expires > time.time(),
        )
        .order_by(OTP.created_at.desc())
        .first()
    )

    if not otp_record:
        raise HTTPException(403, "No valid code found. Request a new one.")

    if otp_record.attempts >= Config.MAX_OTP_ATTEMPTS:
        raise HTTPException(403, "Maximum attempts reached. Request a new code.")

    otp_record.attempts += 1

    # Constant-time comparison via verify_otp_hash
    if not verify_otp_hash(req.otp, otp_record.otp_hash):
        db.commit()
        raise HTTPException(403, "Incorrect code.")

    otp_record.used = True
    user = db.query(User).filter(User.p_hash == p_hash).first()

    # Account recovery path — new device
    if req.new_pub_key and req.new_device_id:
        if user:
            user.pub_key = req.new_pub_key
            user.email_verified = True

        device = db.query(Device).filter(
            Device.p_hash == p_hash,
            Device.device_id == req.new_device_id,
        ).first()
        if not device:
            db.add(Device(
                p_hash=p_hash,
                device_id=req.new_device_id,
                is_verified=True,
                last_used=time.time(),
                created_at=time.time(),
            ))
        else:
            device.is_verified = True
            device.last_used = time.time()

        db.commit()
        token = _issue_jwt(p_hash)
        log_action(db, p_hash, "account_recovery", f"new_device={req.new_device_id}", request)
        return {"status": "recovery_success", "message": "Account recovered.", "token": token}

    if user:
        user.email_verified = True
    db.commit()

    token = _issue_jwt(p_hash)
    log_action(db, p_hash, "verify_otp", "email_verified", request)
    return {"status": "success", "message": "Verification successful.", "token": token}

# ── Routes: Recovery ──────────────────────────────────────────────────────────

@app.post("/auth/recovery/initiate")
async def initiate_recovery(
    request: Request,
    req: RecoveryRequest,
    db: Session = Depends(get_db),
):
    client_ip = request.client.host
    if not check_rate_limit(client_ip, "recovery", Config.RESEND_OTP_LIMIT, Config.RESEND_OTP_WINDOW):
        raise HTTPException(429, "Too many attempts. Please try again in 30 minutes.")
    record_rate_limit(client_ip, "recovery", Config.RESEND_OTP_WINDOW)

    try:
        normalized = normalize_phone(req.phone, req.country_code)
    except ValueError as exc:
        raise HTTPException(400, str(exc))

    p_hash = generate_p_hash(normalized)
    user = db.query(User).filter(User.p_hash == p_hash).first()

    # Always return the same response to prevent user enumeration
    if not user or not hmac.compare_digest(user.email_hash or "", generate_email_hash(req.email)):
        return {
            "status": "recovery_otp_sent",
            "message": "If the account and email match, a recovery code has been sent.",
            "expires_in": Config.OTP_EXPIRY,
        }

    otp_plain = generate_otp()
    db.add(OTP(
        p_hash=p_hash,
        otp_hash=hash_otp(otp_plain),
        otp_type="recovery",
        target=req.email,
        expires=time.time() + Config.OTP_EXPIRY,
        created_at=time.time(),
    ))
    db.commit()

    await send_otp_email(req.email, otp_plain, normalized)
    log_action(db, p_hash, "recovery_initiated", None, request)

    return {
        "status": "recovery_otp_sent",
        "message": "If the account and email match, a recovery code has been sent.",
        "expires_in": Config.OTP_EXPIRY,
    }

# ── Routes: Devices (authenticated) ──────────────────────────────────────────

@app.get("/auth/devices")
async def get_devices(
    db: Session = Depends(get_db),
    p_hash: str = Depends(require_auth),
):
    """List devices for the authenticated account."""
    devices = (
        db.query(Device)
        .filter(Device.p_hash == p_hash)
        .order_by(Device.last_used.desc())
        .all()
    )
    return {
        "status": "success",
        "devices": [
            {
                "device_id": d.device_id,
                "device_name": d.device_name,
                "device_type": d.device_type,
                "is_primary": d.is_primary,
                "is_verified": d.is_verified,
                "last_used": d.last_used,
                "created_at": d.created_at,
            }
            for d in devices
        ],
        "count": len(devices),
    }


@app.delete("/auth/devices")
async def remove_device(
    request: Request,
    req: RemoveDeviceRequest,
    db: Session = Depends(get_db),
    p_hash_auth: str = Depends(require_auth),
):
    """Remove a device. Requires authentication."""
    try:
        normalized = normalize_phone(req.phone, req.country_code)
    except ValueError as exc:
        raise HTTPException(400, str(exc))

    p_hash = generate_p_hash(normalized)
    if p_hash != p_hash_auth:
        raise HTTPException(403, "Not authorized.")

    device = db.query(Device).filter(
        Device.p_hash == p_hash,
        Device.device_id == req.device_id,
    ).first()

    if not device:
        raise HTTPException(404, "Device not found.")
    if device.is_primary:
        raise HTTPException(400, "Cannot remove the primary device.")

    db.delete(device)
    db.commit()
    log_action(db, p_hash, "device_removed", f"device={req.device_id}", request)
    return {"status": "success", "message": "Device removed."}

# ── Routes: Phone validation ──────────────────────────────────────────────────

@app.post("/auth/validate-phone")
async def validate_phone(req: PhoneRequest):
    try:
        info = get_phone_info(req.phone, req.country_code)
        return {"status": "valid" if info.get("is_valid") else "invalid", "data": info}
    except ValueError as exc:
        return {"status": "invalid", "message": str(exc)}

# ── Routes: User info (authenticated) ─────────────────────────────────────────

@app.get("/auth/me")
async def get_me(
    db: Session = Depends(get_db),
    p_hash: str = Depends(require_auth),
):
    """Get authenticated user's own information."""
    user = db.query(User).filter(User.p_hash == p_hash).first()
    if not user:
        raise HTTPException(404, "User not found.")
    return {
        "status": "success",
        "data": {
            "phone": user.phone_number,
            "country_code": user.country_code,
            "first_name": user.first_name,
            "last_name": user.last_name,
            "is_verified": user.is_verified,
            "sim_verified": user.sim_verified,
            "email_verified": user.email_verified,
            "created_at": user.created_at,
            "last_login": user.last_login,
            "login_count": user.login_count,
        },
    }

# ── Error handlers ────────────────────────────────────────────────────────────

@app.exception_handler(HTTPException)
async def http_exception_handler(request: Request, exc: HTTPException):
    return JSONResponse(
        status_code=exc.status_code,
        content={"status": "error", "code": exc.status_code, "message": exc.detail},
    )


@app.exception_handler(Exception)
async def general_exception_handler(request: Request, exc: Exception):
    logger.exception("Unhandled exception: %s", exc)
    return JSONResponse(
        status_code=500,
        content={
            "status": "error",
            "code": 500,
            "message": "Internal server error.",
            # Only expose detail in debug mode
            "detail": str(exc) if Config.DEBUG else None,
        },
    )

# ── Entry point ───────────────────────────────────────────────────────────────

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=8000,
        reload=Config.DEBUG,
        log_level="debug" if Config.DEBUG else "info",
    )
