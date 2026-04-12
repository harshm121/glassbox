<!-- source-hash: a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6 -->
# src/auth.py

> JWT-based authentication service with Redis-backed sessions and brute-force protection

## Recent Changes

```mermaid
timeline
    title Recent Changes
    Latest : ~modified authenticate -- added lockout check after failed attempts
           : +added _is_locked_out -- brute-force protection (5 attempts / 15 min)
           : +added _record_failed_attempt -- tracks failures in Redis with TTL
    Previous : +added refresh -- token rotation with single-use refresh tokens
             : +added revoke -- token revocation via Redis blacklist
```

## Structure

```mermaid
classDiagram
    class TokenPair {
        +str access_token
        +str refresh_token
        +datetime expires_at
    }

    class AuthService {
        -str secret_key
        -Redis redis
        -int token_ttl
        +TokenPair authenticate(str username, str password)
        +TokenPair refresh(str refresh_token)
        +bool revoke(str token)
    }

    class authenticate {
        «method · modified»
    }
    note for authenticate "now checks lockout before issuing tokens"

    class _is_locked_out {
        «method · added»
    }
    note for _is_locked_out "blocks login after 5 failed attempts in 15 min"

    class _record_failed_attempt {
        «method · added»
    }

    AuthService --> TokenPair : returns
    AuthService *-- authenticate
    AuthService *-- _is_locked_out
    AuthService *-- _record_failed_attempt
```

## Flow

```mermaid
flowchart TD
    A["authenticate(username, password)"] --> B["lookup user in Redis"]
    B --> C{"user found?"}
    C -- no --> D["return None"]
    C -- yes --> E{"password valid?"}
    E -- no --> F["record failed attempt"] --> D
    E -- yes --> G{"locked out?"}
    G -- yes --> D
    G -- no --> H["issue token pair"]
    H --> I["return TokenPair"]
```

```mermaid
flowchart TD
    R["refresh(token)"] --> S["decode JWT"]
    S --> T{"valid refresh token?"}
    T -- no --> U["return None"]
    T -- yes --> V{"revoked?"}
    V -- yes --> U
    V -- no --> W["revoke old token"]
    W --> X["issue new pair"]
```

## Dependencies

```mermaid
graph LR
    Auth["auth.py"]
    Auth -->|"sign/verify tokens"| JWT["jwt"]
    Auth -->|"session store + lockout tracking"| Redis["redis"]
    Auth -->|"password hashing"| Hashlib["hashlib"]
    Auth -->|"token expiry math"| Datetime["datetime"]
```
