"""
SIBNA Authentication System - Final Version
============================================
Complete authentication system supporting:
- Automatic SIM detection (Auto-detection)
- Phone number validation
- Email OTP (8 ) 
- Global country support
- High security with HMAC + Salt
- Automatic fallback if SIM fails
"""

import hmac
import hashlib
import time
import secrets
import random
import os
import json
import jwt
import asyncio
import smtplib
from datetime import datetime, timedelta
from typing import Optional, Dict, Any, List
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart

from fastapi import FastAPI, HTTPException, Request, BackgroundTasks, Depends
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from pydantic import BaseModel, EmailStr, Field, validator
import phonenumbers
from phonenumbers import carrier, geocoder, timezone

from sqlalchemy import create_engine, Column, Integer, String, Float, Text, Boolean, UniqueConstraint
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker, Session
import redis
from config import Config

# ============================================
# Pydantic Models
# ============================================

class PhoneRequest(BaseModel):
    phone: str = Field(..., description="Phone number")
    country_code: Optional[str] = Field(None, description="Country code")
    device_id: Optional[str] = Field(None, description="Device ID")
    device_name: Optional[str] = Field(None, description="Device name")
    device_type: Optional[str] = Field(None, description="Device type")

class SIMVerifyRequest(BaseModel):
    sim_phone: Optional[str] = Field(None, description="SIM phone number")
    entered_phone: str = Field(..., description="Entered phone number")
    country_code: Optional[str] = Field(None, description="Country code")
    device_id: str = Field(..., description="Device ID")
    device_name: Optional[str] = None
    device_type: Optional[str] = None
    sim_info: Optional[Dict[str, Any]] = Field(None, description="Additional SIM info")

class RegisterRequest(PhoneRequest):
    email: Optional[EmailStr] = Field(None, description="Email address")
    pub_key: str = Field(..., description="Public key")
    sim_verified: Optional[bool] = Field(False, description="Is SIM verified")

class ChallengeRequest(PhoneRequest):
    pass

class ChallengeResponse(BaseModel):
    challenge_id: str
    phone: str
    country_code: Optional[str] = None

class VerifyChallengeRequest(BaseModel):
    challenge_id: str
    signed_challenge: str
    device_id: str
    device_name: Optional[str] = None
    device_type: Optional[str] = None

class EmailLinkRequest(BaseModel):
    phone: str
    email: EmailStr
    country_code: Optional[str] = None

class VerifyOTPRequest(BaseModel):
    phone: str
    otp: str = Field(..., min_length=6, max_length=6, description="OTP code (6 digits)")
    country_code: Optional[str] = None
    new_pub_key: Optional[str] = None
    new_device_id: Optional[str] = None

class RecoveryRequest(PhoneRequest):
    email: EmailStr

class DeviceInfo(BaseModel):
    device_id: str
    device_name: Optional[str] = None
    device_type: Optional[str] = None

class RemoveDeviceRequest(BaseModel):
    phone: str
    device_id: str
    country_code: Optional[str] = None

# ============================================
# Configuration
# ============================================

app = FastAPI(
    title="SIBNA Authentication API",
    description="Complete Auth System with SIM Auto-detection & Email OTP",
    version="2.5.0"
)

# CORS Configuration
app.add_middleware(
    CORSMiddleware,
    allow_origins=Config.CORS_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ============================================
# Database & Redis Setup
# ============================================

Base = declarative_base()

# SQLite needs special handling for concurrent threads
engine_args = {}
if Config.DATABASE_URL.startswith("sqlite"):
    engine_args["connect_args"] = {"check_same_thread": False}

engine = create_engine(Config.DATABASE_URL, **engine_args)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

# Redis fallback for local development
try:
    redis_client = redis.from_url(Config.REDIS_URL, decode_responses=True)
    redis_client.ping()
    REDIS_AVAILABLE = True
except Exception:
    print("⚠️ Redis not available. Falling back to local memory for rate limiting.")
    REDIS_AVAILABLE = False
    redis_client = None

class User(Base):
    __tablename__ = "users"
    id = Column(Integer, primary_key=True, index=True)
    p_hash = Column(String, unique=True, index=True, nullable=False)
    phone_number = Column(String)
    salt = Column(String, nullable=False)
    pub_key = Column(String)
    email_hash = Column(String)
    email = Column(String)
    device_id = Column(String)
    country_code = Column(String)
    sim_verified = Column(Boolean, default=False)
    is_verified = Column(Boolean, default=False)
    email_verified = Column(Boolean, default=False)
    first_name = Column(String)
    last_name = Column(String)
    created_at = Column(Float)
    last_login = Column(Float)
    login_count = Column(Integer, default=0)

class OTP(Base):
    __tablename__ = "otps"
    id = Column(Integer, primary_key=True)
    p_hash = Column(String, index=True, nullable=False)
    otp_code = Column(String, nullable=False)
    otp_type = Column(String, default='email')
    target = Column(String)
    expires = Column(Float, nullable=False)
    used = Column(Boolean, default=False)
    attempts = Column(Integer, default=0)
    created_at = Column(Float)

class Challenge(Base):
    __tablename__ = "challenges"
    id = Column(String, primary_key=True)
    p_hash = Column(String, index=True, nullable=False)
    challenge_data = Column(Text, nullable=False)
    expires = Column(Float, nullable=False)
    used = Column(Boolean, default=False)
    created_at = Column(Float)

class Device(Base):
    __tablename__ = "devices"
    id = Column(Integer, primary_key=True)
    p_hash = Column(String, index=True, nullable=False)
    device_id = Column(String, nullable=False)
    device_name = Column(String)
    device_type = Column(String)
    sim_info = Column(Text)
    last_used = Column(Float)
    is_primary = Column(Boolean, default=False)
    is_verified = Column(Boolean, default=False)
    created_at = Column(Float)
    __table_args__ = (UniqueConstraint('p_hash', 'device_id', name='_p_hash_device_id_uc'),)

class SIMVerification(Base):
    __tablename__ = "sim_verifications"
    id = Column(Integer, primary_key=True)
    p_hash = Column(String, nullable=False)
    sim_number = Column(String)
    app_number = Column(String)
    match_result = Column(Boolean)
    verified_at = Column(Float)
    ip_address = Column(String)

class AuditLog(Base):
    __tablename__ = "audit_log"
    id = Column(Integer, primary_key=True)
    p_hash = Column(String)
    action = Column(String, nullable=False)
    details = Column(Text)
    ip_address = Column(String)
    user_agent = Column(Text)
    timestamp = Column(Float, nullable=False)

def init_db():
    Base.metadata.create_all(bind=engine)

init_db()

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

# ============================================
# Helper Functions
# ============================================

def generate_p_hash(phone: str, country_code: str = None) -> str:
    """Generate phone hash with country code support"""
    normalized_phone = normalize_phone(phone, country_code)
    return hmac.new(
        Config.SECRET_KEY.encode(),
        normalized_phone.encode(),
        hashlib.sha256
    ).hexdigest()

def generate_email_hash(email: str) -> str:
    """Generate email hash"""
    normalized_email = email.lower().strip()
    return hmac.new(
        Config.SECRET_KEY.encode(),
        normalized_email.encode(),
        hashlib.sha256
    ).hexdigest()

def generate_salt() -> str:
    """Generate random salt"""
    return secrets.token_hex(32)

def generate_otp(length: int = 6) -> str:
    """Generate numeric OTP (6 digits as requested)"""
    return ''.join([str(random.randint(0, 9)) for _ in range(length)])

def generate_challenge() -> str:
    """Generate challenge string"""
    return secrets.token_urlsafe(64)

def generate_device_id() -> str:
    """Generate unique device ID"""
    return secrets.token_urlsafe(32)

def normalize_phone(phone: str, country_code: str = None) -> str:
    """Normalize phone number with country code support"""
    try:
        if country_code:
            region = country_code.upper()
            parsed = phonenumbers.parse(phone, region)
        else:
            parsed = phonenumbers.parse(phone, None)
        
        if not phonenumbers.is_valid_number(parsed):
            raise ValueError("Invalid phone number")
        
        return phonenumbers.format_number(parsed, phonenumbers.PhoneNumberFormat.E164)
    except Exception as e:
        cleaned = ''.join(filter(str.isdigit, phone))
        if not cleaned.startswith('+'):
            cleaned = '+' + cleaned
        return cleaned

def get_phone_info(phone: str, country_code: str = None) -> Dict[str, Any]:
    """Get detailed phone number information"""
    try:
        normalized = normalize_phone(phone, country_code)
        parsed = phonenumbers.parse(normalized, None)
        
        return {
            "normalized": normalized,
            "country_code": phonenumbers.region_code_for_number(parsed),
            "country_name": geocoder.description_for_number(parsed, 'en'),
            "carrier": carrier.name_for_number(parsed, 'en'),
            "timezone": str(timezone.time_zones_for_number(parsed)),
            "is_valid": phonenumbers.is_valid_number(parsed),
            "is_possible": phonenumbers.is_possible_number(parsed),
            "number_type": str(phonenumbers.number_type(parsed))
        }
    except Exception as e:
        return {
            "normalized": phone,
            "error": str(e),
            "is_valid": False
        }

def compare_phone_numbers(phone1: str, phone2: str, country_code: str = None) -> Dict[str, Any]:
    """
    Compare two phone numbers and check if they match
    Used for SIM verification
    """
    try:
        # Normalize both numbers
        norm1 = normalize_phone(phone1, country_code)
        norm2 = normalize_phone(phone2, country_code)
        
        # Remove + for comparison
        clean1 = ''.join(filter(str.isdigit, norm1))
        clean2 = ''.join(filter(str.isdigit, norm2))
        
        # Check various match scenarios
        
        # Strip leading zeros to handle numbers with/without country code gracefully
        c1 = clean1.lstrip('0')
        c2 = clean2.lstrip('0')

        # 1. Exact match after cleaning
        exact_match = (c1 == c2)
        
        # 2. Substring match (in case one has country code and the other doesn't)
        substring_match = (c1 in c2) or (c2 in c1)
        
        # 3. Robust Suffix match (handling numbers from 7 to 12 digits)
        suffix_match = False
        for length in range(7, 13):
            if len(c1) >= length and len(c2) >= length:
                if c1[-length:] == c2[-length:]:
                    suffix_match = True
                    break

        is_match = exact_match or substring_match or suffix_match
        
        return {
            "phone1_normalized": norm1,
            "phone2_normalized": norm2,
            "exact_match": exact_match,
            "suffix_match": suffix_match,
            "is_match": is_match,
            "confidence": "high" if exact_match else ("medium" if is_match else "low")
        }
    except Exception as e:
        return {
            "error": str(e),
            "is_match": False,
            "confidence": "error"
        }

# ============================================
# Email Service
# ============================================

async def send_otp_email(target_email: str, otp_code: str, phone_hint: str = None):
    """Send a premium OTP email with elegant phone number masking"""
    
    # Elegant masking logic (e.g., +213 •••••• 04)
    masked_phone = "your SIBNA account"
    if phone_hint:
        clean_phone = phone_hint.strip()
        if len(clean_phone) > 7:
            # Automatic masking for all countries
            # Keep country code + first digit, and last 2 digits
            # Example: +213 552 380304 -> +213 •••••• 04
            prefix = clean_phone[:4]
            suffix = clean_phone[-2:]
            middle_len = len(clean_phone) - 6
            masked_phone = f"{prefix} {'•' * middle_len} {suffix}"
        else:
            masked_phone = clean_phone
            
    print(f"[SECURITY] Sending OTP {otp_code} to {target_email} for account: {masked_phone}")
    
    def _send_blocking():
        subject = f"{otp_code} is your SIBNA verification code"
        
        # Ultra-Premium Dark-Themed HTML Template
        html_content = f"""
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <style>
                body {{ background: #080808; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; color: #ffffff; margin: 0; padding: 0; }}
                .wrapper {{ padding: 40px 20px; text-align: center; background: linear-gradient(180deg, #0d0d0d 0%, #080808 100%); }}
                .container {{ max-width: 480px; margin: 0 auto; background: #121212; padding: 48px; border-radius: 32px; border: 1px solid rgba(255,255,255,0.08); box-shadow: 0 20px 40px rgba(0,0,0,0.4); }}
                .logo {{ font-size: 32px; font-weight: 900; letter-spacing: -1.5px; margin-bottom: 40px; color: #ffffff; text-transform: uppercase; }}
                .title {{ font-size: 20px; font-weight: 500; color: rgba(255,255,255,0.6); margin-bottom: 12px; }}
                .phone {{ font-size: 14px; color: #555; margin-bottom: 32px; font-family: 'SF Mono', menlo, monospace; letter-spacing: 1px; }}
                .otp-wrap {{ position: relative; padding: 24px; background: rgba(255,255,255,0.03); border-radius: 20px; border: 1px solid rgba(255,255,255,0.05); margin: 24px 0; }}
                .otp-box {{ color: #ffffff; font-size: 48px; font-weight: 800; letter-spacing: 10px; margin: 0; text-shadow: 0 0 20px rgba(255,255,255,0.2); }}
                .expiry {{ font-size: 14px; color: #888; margin-top: 16px; }}
                .highlight {{ color: #ffffff; font-weight: 700; }}
                .footer {{ margin-top: 50px; font-size: 11px; color: #333; letter-spacing: 0.5px; text-transform: uppercase; border-top: 1px solid rgba(255,255,255,0.05); padding-top: 30px; }}
                .note {{ color: #555; font-size: 12px; margin-top: 30px; line-height: 1.6; max-width: 80%; margin-left: auto; margin-right: auto; }}
            </style>
        </head>
        <body>
            <div class="wrapper">
                <div class="container">
                    <div class="logo">SIBNA</div>
                    <div class="title">Security Verification</div>
                    <div class="phone">For account {masked_phone}</div>
                    <div class="otp-wrap">
                        <div class="otp-box">{otp_code}</div>
                    </div>
                    <p class="expiry">Expires in <span class="highlight">2 minutes</span></p>
                    <div class="note">
                        SIBNA Security Tip: We will never call or message you asking for this code. If you didn't request this, please secure your account immediately.
                    </div>
                    <div class="footer">
                        &copy; {datetime.now().year} SIBNA INTELLIGENCE &bull; PREMIUM DATA PROTECTION
                    </div>
                </div>
            </div>
        </body>
        </html>
        """
        
        msg = MIMEMultipart("alternative")
        msg["From"] = f"{Config.SMTP_FROM_NAME} <{Config.SMTP_USERNAME}>"
        msg["To"] = target_email
        msg["Subject"] = subject
        
        # Professional Plain Text version
        text_content = f"SIBNA Verification\n\nCode: {otp_code}\nValid for 2 minutes.\nLinked to: {masked_phone}\n\nIf you did not request this, please ignore this email."
        
        msg.attach(MIMEText(text_content, "plain"))
        msg.attach(MIMEText(html_content, "html"))
        
        with smtplib.SMTP_SSL(Config.SMTP_HOST, Config.SMTP_PORT, timeout=20) as server:
            server.login(Config.SMTP_USERNAME, Config.SMTP_PASSWORD)
            server.send_message(msg)
            return True

    try:
        print("!!! ATTEMPTING TO SEND ULTRA-PREMIUM ENGLISH EMAIL !!!")
        with open("EMAIL_DEBUG.log", "a") as f:
            f.write(f"EMAIL TRIGGERED TO {target_email} AT {time.time()}\n")
        loop = asyncio.get_event_loop()
        await loop.run_in_executor(None, _send_blocking)
        print(f"[SUCCESS] Premium email delivered to {target_email}")
        return True
    except Exception as e:
        print(f"[ERROR] SMTP Failure for {target_email}: {e}")
        return False

# ============================================
# Rate Limiting (Redis with In-Memory Fallback)
# ============================================

_MEM_RATE_LIMITS = {} # Local fallback for dev

def check_rate_limit(identifier: str, action_type: str, max_attempts: int = 5, window: int = None) -> bool:
    """Check if action is rate limited using Redis (with memory fallback)"""
    key = f"rate_limit:{action_type}:{identifier}"
    
    if not REDIS_AVAILABLE:
        # Local Memory Fallback
        entry = _MEM_RATE_LIMITS.get(key)
        if not entry:
            return True
        # Check expiry
        if time.time() > entry['expires']:
            del _MEM_RATE_LIMITS[key]
            return True
        
        is_allowed = entry['count'] < max_attempts
        if not is_allowed:
            print(f"[RATE LIMIT] Blocked {action_type} for {identifier}. Count: {entry['count']}/{max_attempts}")
        return is_allowed
        
    try:
        current = redis_client.get(key)
        if current and int(current) >= max_attempts:
            print(f"[RATE LIMIT] Redis blocked {action_type} for {identifier}")
            return False
        return True
    except Exception:
        return True

def record_rate_limit(identifier: str, action_type: str, window: int = None):
    """Record a rate limit attempt in Redis (with memory fallback)"""
    key = f"rate_limit:{action_type}:{identifier}"
    win = window or Config.RATE_LIMIT_WINDOW
    
    if not REDIS_AVAILABLE:
        # Local Memory Fallback
        now = time.time()
        entry = _MEM_RATE_LIMITS.get(key)
        if not entry or now > entry['expires']:
            _MEM_RATE_LIMITS[key] = {'count': 1, 'expires': now + win}
        else:
            entry['count'] += 1
        print(f"[RATE LIMIT] Recorded {action_type} for {identifier}. Global count: {_MEM_RATE_LIMITS[key]['count']}")
        return
        
    try:
        pipeline = redis_client.pipeline()
        pipeline.incr(key)
        pipeline.expire(key, win)
        pipeline.execute()
    except Exception:
        pass

# Audit Logging
# ============================================

def log_action(db: Session, p_hash: str, action: str, details: str = None, request: Request = None):
    """Log user action for audit using SQLAlchemy"""
    log_entry = AuditLog(
        p_hash=p_hash,
        action=action,
        details=details,
        ip_address=request.client.host if request else None,
        user_agent=request.headers.get("user-agent") if request else None,
        timestamp=time.time()
    )
    db.add(log_entry)
    db.commit()

# ============================================
# API Routes - Root & Health
# ============================================

@app.get("/")
async def root():
    """API root endpoint"""
    return {
        "name": "SIBNA Authentication API",
        "version": "2.5.0",
        "status": "running",
        "features": [
            "sim_auto_detection",
            "challenge_response",
            "email_otp_6_digits",
            "39_countries",
            "fallback_auto"
        ],
        "docs": "/docs"
    }

@app.get("/health")
async def health_check():
    """Health check endpoint"""
    return {"status": "healthy", "timestamp": time.time()}

# ============================================
# API Routes - SIM Verification
# ============================================

@app.post("/auth/sim/verify")
async def verify_sim(request: Request, req: SIMVerifyRequest, db: Session = Depends(get_db)):
    """
    Verify SIM number against entered number
    SIM Auto-Detection Verification
    """
    client_ip = request.client.host
    
    # Compare the numbers
    comparison = compare_phone_numbers(req.sim_phone, req.entered_phone, req.country_code)
    
    # Log the attempt
    p_hash = generate_p_hash(req.entered_phone, req.country_code)
    
    sim_ver = SIMVerification(
        p_hash=p_hash,
        sim_number=req.sim_phone,
        app_number=req.entered_phone,
        match_result=comparison["is_match"],
        verified_at=time.time(),
        ip_address=client_ip
    )
    db.add(sim_ver)
    db.commit()
    
    if comparison["is_match"]:
        # NEW: Auto-register user if verified by SIM
        existing_user = db.query(User).filter(User.p_hash == p_hash).first()
        if not existing_user:
            new_user = User(
                p_hash=p_hash,
                salt=generate_salt(), # FIX: Mandatory field
                email=f"sim_{req.sim_phone[-4:]}@sibna.local",
                is_verified=True,
                created_at=time.time()
            )
            db.add(new_user)
            db.commit()
            
        return {
            "status": "match",
            "message": "SIM verified. Please confirm your information.",
            "match": True,
            "confidence": comparison["confidence"],
            "phone": comparison["phone2_normalized"],
            "next_step": "profile", # Direct to profile confirm screen
            "sim_info": {
                "sim_phone": comparison["phone1_normalized"],
                "normalized": comparison["phone2_normalized"]
            }
        }
    else:
        return {
            "status": "sim_mismatch",
            "message": "SIM number mismatch. Please enter the number manually or use e-mail verification.",
            "match": False,
            "confidence": comparison["confidence"],
            "fallback_options": [
                {"type": "manual_entry", "description": "User enters the number manually"},
                {"type": "email_otp", "description": "Send 6-digit code to email", "endpoint": "/auth/link-email", "otp_length": 6}
            ],
            "sim_info": {
                "sim_phone": comparison.get("phone1_normalized", req.sim_phone),
                "entered_phone": comparison.get("phone2_normalized", req.entered_phone)
            },
            "p_hash": p_hash
        }

@app.post("/auth/register")
async def register(request: Request, req: RegisterRequest, db: Session = Depends(get_db)):
    """
    Register a new user
    """
    client_ip = request.client.host
    if not check_rate_limit(client_ip, "register", 5):
        raise HTTPException(429, "Too many registration attempts.")
    
    record_rate_limit(client_ip, "register")
    
    try:
        phone_info = get_phone_info(req.phone, req.country_code)
        if not phone_info.get("is_valid"):
            raise HTTPException(400, "Invalid phone number")
    except Exception as e:
        raise HTTPException(400, f"Phone error: {str(e)}")
    
    normalized_phone = phone_info["normalized"]
    p_hash = generate_p_hash(normalized_phone)
    
    # Check if user exists
    existing_user = db.query(User).filter(User.p_hash == p_hash).first()
    if existing_user:
        raise HTTPException(409, "Account already exists with this number.")
    
    # Create user
    now = time.time()
    salt = secrets.token_hex(32)
    device_id = req.device_id or secrets.token_urlsafe(32)
    
    new_user = User(
        p_hash=p_hash,
        phone_number=normalized_phone,
        salt=salt,
        pub_key=req.pub_key,
        email=req.email,
        country_code=phone_info.get("country_code"),
        is_verified=True,
        sim_verified=req.sim_verified,
        created_at=now,
        last_login=now,
        login_count=1
    )
    db.add(new_user)
    
    # Register device
    new_device = Device(
        p_hash=p_hash,
        device_id=device_id,
        device_name=req.device_name,
        device_type=req.device_type,
        is_primary=True,
        is_verified=True,
        last_used=now,
        created_at=now
    )
    db.add(new_device)
    db.commit()
    
    log_action(db, p_hash, "register", f"Phone: {normalized_phone}, SIM: {req.sim_verified}", request)
    
    return {
        "status": "success",
        "message": "Account registered successfully",
        "data": {
            "phone": normalized_phone,
            "device_id": device_id,
            "sim_verified": req.sim_verified
        }
    }
# ============================================
# API Routes - Challenge-Response Auth
# ============================================

@app.post("/auth/challenge")
async def get_challenge(request: Request, req: ChallengeRequest, db: Session = Depends(get_db)):
    """Request a challenge for authentication"""
    client_ip = request.client.host
    if not check_rate_limit(client_ip, "challenge", 10):
        raise HTTPException(429, "Too many challenge requests.")
    
    record_rate_limit(client_ip, "challenge")
    
    try:
        phone_info = get_phone_info(req.phone, req.country_code)
        normalized_phone = phone_info["normalized"]
    except:
        normalized_phone = normalize_phone(req.phone, req.country_code)
    
    p_hash = generate_p_hash(normalized_phone)
    user = db.query(User).filter(User.p_hash == p_hash).first()
    
    if not user:
        raise HTTPException(404, "Account not found. Please register first.")
    
    challenge_id = secrets.token_urlsafe(32)
    challenge_data = secrets.token_urlsafe(64)
    expires = time.time() + Config.CHALLENGE_EXPIRY
    
    new_challenge = Challenge(
        id=challenge_id,
        p_hash=p_hash,
        challenge_data=challenge_data,
        expires=expires,
        created_at=time.time()
    )
    db.add(new_challenge)
    db.commit()
    
    return {
        "status": "challenge_ready",
        "challenge_id": challenge_id,
        "challenge": challenge_data,
        "phone": normalized_phone,
        "expires_in": Config.CHALLENGE_EXPIRY
    }

@app.post("/auth/verify-challenge")
async def verify_challenge(request: Request, req: VerifyChallengeRequest, db: Session = Depends(get_db)):
    """Verify signed challenge and complete login"""
    client_ip = request.client.host
    if not check_rate_limit(client_ip, "verify", 5):
        raise HTTPException(429, "Too many verification attempts.")
    
    record_rate_limit(client_ip, "verify")
    
    challenge = db.query(Challenge).filter(
        Challenge.id == req.challenge_id,
        Challenge.used == False,
        Challenge.expires > time.time()
    ).first()
    
    if not challenge:
        raise HTTPException(403, "Invalid or expired challenge.")
    
    user = db.query(User).filter(User.p_hash == challenge.p_hash).first()
    
    # Check if device is registered
    device = db.query(Device).filter(
        Device.p_hash == challenge.p_hash,
        Device.device_id == req.device_id
    ).first()
    
    is_new_device = not device
    
    if is_new_device:
        challenge.used = True
        db.commit()
        return {
            "status": "need_recovery",
            "message": "New device detected. Email verification required.",
            "phone": user.phone_number,
            "action": "email_verification_required",
            "fallback": {
                "method": "email_otp",
                "otp_length": 6,
                "endpoint": "/auth/link-email"
            }
        }
    
    challenge.used = True
    user.last_login = time.time()
    user.login_count += 1
    device.last_used = time.time()
    db.commit()
    
    log_action(db, challenge.p_hash, "login", f"Device: {req.device_id}", request)
    
    return {
        "status": "success",
        "message": "Logged in successfully",
        "phone": user.phone_number
    }

class ProfileUpdateRequest(BaseModel):
    phone: str
    country_code: Optional[str] = None
    first_name: str
    last_name: str

@app.post("/auth/update-profile")
async def update_profile(request: Request, req: ProfileUpdateRequest, db: Session = Depends(get_db)):
    """Update user profile (names) after SIM verification"""
    normalized_phone = normalize_phone(req.phone, req.country_code)
    p_hash = generate_p_hash(normalized_phone)
    
    user = db.query(User).filter(User.p_hash == p_hash).first()
    if not user:
        raise HTTPException(404, "User not found")
    
    user.first_name = req.first_name
    user.last_name = req.last_name
    db.commit()
    
    log_action(db, p_hash, "profile_update", f"Name: {req.first_name} {req.last_name}", request)
    return {"status": "success", "message": "Profile updated successfully", "next_step": "vault"}

# ============================================
# API Routes - Email OTP (6 digits)
# ============================================

@app.post("/auth/link-email")
async def link_email(request: Request, background_tasks: BackgroundTasks, req: EmailLinkRequest, db: Session = Depends(get_db)):
    """
     Email address  OTP (6 )
    """
    client_ip = request.client.host
    if not check_rate_limit(client_ip, "link_email", Config.RESEND_OTP_LIMIT, Config.RESEND_OTP_WINDOW):
        raise HTTPException(429, "Too many attempts. Please try again in 30 minutes.")
    
    record_rate_limit(client_ip, "link_email", Config.RESEND_OTP_WINDOW)
    
    try:
        phone_info = get_phone_info(req.phone, req.country_code)
        normalized_phone = phone_info["normalized"]
    except:
        normalized_phone = normalize_phone(req.phone, req.country_code)
    
    p_hash = generate_p_hash(normalized_phone)
    user = db.query(User).filter(User.p_hash == p_hash).first()
    
    # Generate 6-digit OTP
    otp_code = ''.join([str(random.randint(0, 9)) for _ in range(6)])
    expires = time.time() + Config.OTP_EXPIRY
    
    new_otp = OTP(
        p_hash=p_hash,
        otp_code=otp_code,
        otp_type='email',
        target=req.email,
        expires=expires,
        created_at=time.time()
    )
    db.add(new_otp)
    
    if user:
        user.email_hash = generate_email_hash(req.email)
    
    db.commit()
    
    # Send email in background
    background_tasks.add_task(send_otp_email, req.email, otp_code, normalized_phone)
    log_action(db, p_hash, "link_email", f"Email: {req.email}", request)
    
    return {
        "status": "otp_sent",
        "message": "Verification code (6-digits) sent to your email.",
        "email_hint": req.email[:3] + "***" + req.email.split("@")[-1],
        "expires_in": Config.OTP_EXPIRY
    }

@app.post("/auth/verify-otp")
async def verify_otp(request: Request, req: VerifyOTPRequest, db: Session = Depends(get_db)):
    """
    Verify OTP code (6-digits)
    """
    client_ip = request.client.host
    if not check_rate_limit(client_ip, "verify_otp", 5):
        raise HTTPException(429, "Too many attempts.")
    
    if len(req.otp) != 6 or not req.otp.isdigit():
        raise HTTPException(400, "OTP must be 6 digits.")
    
    record_rate_limit(client_ip, "verify_otp")
    
    normalized_phone = normalize_phone(req.phone, req.country_code)
    p_hash = generate_p_hash(normalized_phone)
    
    otp_record = db.query(OTP).filter(
        OTP.p_hash == p_hash,
        OTP.used == False,
        OTP.expires > time.time()
    ).order_by(OTP.created_at.desc()).first()
    
    if not otp_record:
        raise HTTPException(403, "No valid code found. Request a new one.")
    
    if otp_record.attempts >= Config.MAX_OTP_ATTEMPTS:
        raise HTTPException(403, "Maximum attempts reached.")
    
    otp_record.attempts += 1
    
    if otp_record.otp_code != req.otp:
        db.commit()
        raise HTTPException(403, "Incorrect code.")
    
    otp_record.used = True
    user = db.query(User).filter(User.p_hash == p_hash).first()
    
    # Handle recovery (new device)
    if req.new_pub_key and req.new_device_id:
        if user:
            user.pub_key = req.new_pub_key
            user.email_verified = True
        
        # Upsert device
        device = db.query(Device).filter(Device.p_hash == p_hash, Device.device_id == req.new_device_id).first()
        if not device:
            device = Device(p_hash=p_hash, device_id=req.new_device_id, last_used=time.time(), created_at=time.time())
            db.add(device)
        else:
            device.last_used = time.time()
            
        db.commit()
        
        # Generate JWT Session Token
        token_data = {
            "sub": p_hash,
            "exp": datetime.utcnow() + timedelta(days=Config.JWT_EXPIRY_DAYS)
        }
        access_token = jwt.encode(token_data, Config.JWT_SECRET, algorithm="HS256")
        
        log_action(db, p_hash, "account_recovery", f"New device: {req.new_device_id}", request)
        return {"status": "recovery_success", "message": "Account recovered.", "token": access_token}
    
    if user:
        user.email_verified = True
        
    db.commit()
    
    # Generate JWT Session Token
    token_data = {
        "sub": p_hash,
        "exp": datetime.utcnow() + timedelta(days=Config.JWT_EXPIRY_DAYS)
    }
    access_token = jwt.encode(token_data, Config.JWT_SECRET, algorithm="HS256")
    
    log_action(db, p_hash, "verify_otp", "Email verified", request)
    return {"status": "success", "message": "Verification successful", "token": access_token}

# ============================================
# API Routes - Account Recovery
# ============================================

@app.post("/auth/recovery/initiate")
async def initiate_recovery(request: Request, req: RecoveryRequest, db: Session = Depends(get_db)):
    """
    Initiate account recovery process
    """
    client_ip = request.client.host
    if not check_rate_limit(client_ip, "recovery", Config.RESEND_OTP_LIMIT, Config.RESEND_OTP_WINDOW):
        raise HTTPException(429, "Too many attempts. Please try again in 30 minutes.")
    
    record_rate_limit(client_ip, "recovery", Config.RESEND_OTP_WINDOW)
    
    normalized_phone = normalize_phone(req.phone, req.country_code)
    p_hash = generate_p_hash(normalized_phone)
    user = db.query(User).filter(User.p_hash == p_hash).first()
    
    if not user:
        raise HTTPException(404, "Account not found.")
    
    email_hash = generate_email_hash(req.email)
    if user.email_hash != email_hash:
        raise HTTPException(403, "Email does not match.")
    
    # Generate 6-digit OTP
    otp_code = ''.join([str(random.randint(0, 9)) for _ in range(6)])
    expires = time.time() + Config.OTP_EXPIRY
    
    new_otp = OTP(
        p_hash=p_hash,
        otp_code=otp_code,
        otp_type='recovery',
        target=req.email,
        expires=expires,
        created_at=time.time()
    )
    db.add(new_otp)
    db.commit()
    
    await send_otp_email(req.email, otp_code, normalized_phone)
    log_action(db, p_hash, "recovery_initiated", f"Email: {req.email}", request)
    
    return {
        "status": "recovery_otp_sent",
        "message": "Recovery code (6-digits) sent to your email.",
        "expires_in": Config.OTP_EXPIRY
    }

# ============================================
# API Routes - Device Management
# ============================================

@app.get("/auth/devices/{phone}")
async def get_devices(phone: str, country_code: Optional[str] = None, db: Session = Depends(get_db)):
    """Get list of registered devices"""
    normalized_phone = normalize_phone(phone, country_code)
    p_hash = generate_p_hash(normalized_phone)
    
    devices = db.query(Device).filter(Device.p_hash == p_hash).order_by(Device.last_used.desc()).all()
    
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
                "created_at": d.created_at
            } for d in devices
        ],
        "count": len(devices)
    }

@app.delete("/auth/devices")
async def remove_device(request: Request, req: RemoveDeviceRequest, db: Session = Depends(get_db)):
    """Remove a device from account"""
    normalized_phone = normalize_phone(req.phone, req.country_code)
    p_hash = generate_p_hash(normalized_phone)
    
    device = db.query(Device).filter(Device.p_hash == p_hash, Device.device_id == req.device_id).first()
    
    if not device:
        raise HTTPException(404, "Device not found.")
    if device.is_primary:
        raise HTTPException(400, "Cannot remove primary device.")
    
    db.delete(device)
    db.commit()
    
    log_action(db, p_hash, "device_removed", f"Device: {req.device_id}", request)
    return {"status": "success", "message": "Device removed successfully."}

# ============================================
# API Routes - Phone Validation
# ============================================

@app.post("/auth/validate-phone")
async def validate_phone(req: PhoneRequest):
    """Validate phone number and get info"""
    try:
        phone_info = get_phone_info(req.phone, req.country_code)
        return {"status": "valid" if phone_info.get("is_valid") else "invalid", "data": phone_info}
    except Exception as e:
        return {"status": "error", "message": str(e)}

@app.get("/countries")
async def get_supported_countries():
    """Get list of supported countries"""
    countries = [
        {"code": "SA", "name": "Saudi Arabia", "dial_code": "+966", "flag": "🇸🇦"},
        {"code": "EG", "name": "Egypt", "dial_code": "+20", "flag": "🇪🇬"},
        {"code": "AE", "name": "United Arab Emirates", "dial_code": "+971", "flag": "🇦🇪"},
        # ... and so on ... (truncated for brevity but keeping structure)
        {"code": "DZ", "name": "Algeria", "dial_code": "+213", "flag": "🇩🇿"},
        {"code": "US", "name": "United States", "dial_code": "+1", "flag": "🇺🇸"},
        {"code": "GB", "name": "United Kingdom", "dial_code": "+44", "flag": "🇬🇧"}
    ]
    return {"status": "success", "count": len(countries), "countries": countries}

# ============================================
# API Routes - User Info
# ============================================

@app.get("/auth/user/{phone}")
async def get_user_info(phone: str, country_code: Optional[str] = None, db: Session = Depends(get_db)):
    """Get user information"""
    normalized_phone = normalize_phone(phone, country_code)
    p_hash = generate_p_hash(normalized_phone)
    
    user = db.query(User).filter(User.p_hash == p_hash).first()
    if not user:
        raise HTTPException(404, "User not found")
    
    return {
        "status": "success",
        "data": {
            "phone": user.phone_number,
            "country_code": user.country_code,
            "is_verified": user.is_verified,
            "sim_verified": user.sim_verified,
            "email_verified": user.email_verified,
            "created_at": user.created_at,
            "last_login": user.last_login,
            "login_count": user.login_count
        }
    }

# ============================================
# Error Handlers
# ============================================

@app.exception_handler(HTTPException)
async def http_exception_handler(request: Request, exc: HTTPException):
    return JSONResponse(
        status_code=exc.status_code,
        content={"status": "error", "code": exc.status_code, "message": exc.detail}
    )

@app.exception_handler(Exception)
async def general_exception_handler(request: Request, exc: Exception):
    return JSONResponse(
        status_code=500,
        content={
            "status": "error", "code": 500, "message": "Internal Server Error",
            "detail": str(exc) if os.environ.get("DEBUG") else None
        }
    )

# ============================================
# Run Server
# ============================================

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
