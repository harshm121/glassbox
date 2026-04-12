"""Authentication module for the web application."""

import hashlib
import secrets
from datetime import datetime, timedelta
from dataclasses import dataclass

import jwt
from redis import Redis


@dataclass
class TokenPair:
    access_token: str
    refresh_token: str
    expires_at: datetime


class AuthService:
    """Handles user authentication, token generation, and session management."""

    def __init__(self, secret_key: str, redis: Redis, token_ttl: int = 3600):
        self.secret_key = secret_key
        self.redis = redis
        self.token_ttl = token_ttl

    def authenticate(self, username: str, password: str) -> TokenPair | None:
        """Verify credentials and return tokens if valid."""
        user = self._lookup_user(username)
        if not user:
            return None

        if not self._verify_password(password, user["password_hash"], user["salt"]):
            self._record_failed_attempt(username)
            return None

        if self._is_locked_out(username):
            return None

        return self._issue_tokens(user["id"], user["roles"])

    def refresh(self, refresh_token: str) -> TokenPair | None:
        """Exchange a valid refresh token for a new token pair."""
        payload = self._decode_token(refresh_token)
        if not payload or payload.get("type") != "refresh":
            return None

        if self.redis.get(f"revoked:{refresh_token}"):
            return None

        self.redis.set(f"revoked:{refresh_token}", "1", ex=self.token_ttl)
        return self._issue_tokens(payload["sub"], payload["roles"])

    def revoke(self, token: str) -> bool:
        """Revoke a token so it can no longer be used."""
        self.redis.set(f"revoked:{token}", "1", ex=self.token_ttl)
        return True

    def _issue_tokens(self, user_id: str, roles: list[str]) -> TokenPair:
        now = datetime.utcnow()
        expires = now + timedelta(seconds=self.token_ttl)

        access = jwt.encode(
            {"sub": user_id, "roles": roles, "type": "access", "exp": expires},
            self.secret_key,
            algorithm="HS256",
        )
        refresh = jwt.encode(
            {"sub": user_id, "roles": roles, "type": "refresh",
             "exp": now + timedelta(days=30)},
            self.secret_key,
            algorithm="HS256",
        )
        return TokenPair(access_token=access, refresh_token=refresh, expires_at=expires)

    def _verify_password(self, password: str, stored_hash: str, salt: str) -> bool:
        return hashlib.sha256(f"{salt}{password}".encode()).hexdigest() == stored_hash

    def _lookup_user(self, username: str) -> dict | None:
        data = self.redis.hgetall(f"user:{username}")
        return dict(data) if data else None

    def _record_failed_attempt(self, username: str):
        key = f"failed:{username}"
        self.redis.incr(key)
        self.redis.expire(key, 900)

    def _is_locked_out(self, username: str) -> bool:
        attempts = self.redis.get(f"failed:{username}")
        return attempts is not None and int(attempts) >= 5
