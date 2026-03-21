"""
SIBNA Authentication — Configuration
All sensitive values must be set via environment variables.
Never use the defaults in production.
"""

import os
import secrets
from dotenv import load_dotenv

load_dotenv(override=True)


def _require_env(key: str, default: str | None = None) -> str:
    """Return env var or raise if missing and no safe default exists."""
    value = os.environ.get(key, default)
    if value is None:
        raise RuntimeError(
            f"Required environment variable '{key}' is not set. "
            "Set it in your .env file or deployment environment."
        )
    return value


class Config:
    # ── Security ──────────────────────────────────────────────────────────
    # REQUIRED in production — no hardcoded fallback
    SECRET_KEY: str = _require_env(
        "SECRET_KEY",
        # Safe default only for local dev; will be flagged if weak
        default=None if os.environ.get("ENVIRONMENT") == "production" else secrets.token_hex(32),
    )
    JWT_SECRET: str = _require_env(
        "JWT_SECRET",
        default=None if os.environ.get("ENVIRONMENT") == "production" else secrets.token_hex(32),
    )

    OTP_LENGTH: int = 6
    OTP_EXPIRY: int = int(os.getenv("OTP_EXPIRY", "300"))   # 5 minutes (was 2 — too short for email)
    MAX_OTP_ATTEMPTS: int = 5
    JWT_EXPIRY_DAYS: int = int(os.getenv("JWT_EXPIRY_DAYS", "30"))

    RESEND_OTP_LIMIT: int = 5
    RESEND_OTP_WINDOW: int = 1800   # 30 minutes
    RATE_LIMIT_WINDOW: int = 3600   # 1 hour

    CHALLENGE_EXPIRY: int = int(os.getenv("CHALLENGE_EXPIRY", "300"))  # 5 minutes

    # ── Database ──────────────────────────────────────────────────────────
    DATABASE_URL: str = os.environ.get("DATABASE_URL", "sqlite:///./sibna_auth.db")
    REDIS_URL: str = os.environ.get("REDIS_URL", "redis://localhost:6379/0")

    # ── SMTP ──────────────────────────────────────────────────────────────
    SMTP_HOST: str = os.environ.get("SMTP_HOST", "smtp.gmail.com")
    SMTP_PORT: int = int(os.environ.get("SMTP_PORT", "465"))
    SMTP_USERNAME: str = os.environ.get("GMAIL_USER", "")
    SMTP_PASSWORD: str = os.environ.get("GMAIL_APP_PASSWORD", "")
    SMTP_USE_SSL: bool = True
    SMTP_FROM_NAME: str = "SIBNA"

    # ── CORS ──────────────────────────────────────────────────────────────
    # Production: set CORS_ORIGINS to your actual frontend domain(s)
    # e.g. "https://app.sibna.dev,https://sibna.dev"
    CORS_ORIGINS: list[str] = os.environ.get(
        "CORS_ORIGINS",
        "http://localhost:3000,http://localhost:8080" if os.environ.get("ENVIRONMENT") != "production" else ""
    ).split(",")

    # ── Environment ───────────────────────────────────────────────────────
    DEBUG: bool = os.environ.get("DEBUG", "false").lower() == "true"
    ENVIRONMENT: str = os.environ.get("ENVIRONMENT", "development")

    @classmethod
    def validate(cls) -> None:
        """Validate critical config at startup. Call once in main."""
        if cls.ENVIRONMENT == "production":
            if len(cls.SECRET_KEY) < 32:
                raise RuntimeError("SECRET_KEY must be at least 32 characters in production.")
            if len(cls.JWT_SECRET) < 32:
                raise RuntimeError("JWT_SECRET must be at least 32 characters in production.")
            if "*" in cls.CORS_ORIGINS:
                raise RuntimeError("CORS_ORIGINS must not contain '*' in production.")
            if not cls.SMTP_USERNAME or not cls.SMTP_PASSWORD:
                raise RuntimeError("SMTP credentials must be set in production.")
