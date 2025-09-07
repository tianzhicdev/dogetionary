# Dogetionary Scripts

Simple utility scripts for deployment and testing.

## 🚀 Deployment Scripts

### `server_start.sh`
Start the Dogetionary server with automatic environment detection.
```bash
./scripts/server_start.sh          # Normal start
./scripts/server_start.sh --clean  # Clean restart (remove old containers)
```

### `restart-clean.sh` 
**⚠️ DESTRUCTIVE** - Completely wipes database and restarts fresh.
```bash
./scripts/restart-clean.sh
```

### `update-backend.sh`
Update backend code and restart app container.
```bash
./scripts/update-backend.sh
```

## 👤 Server Setup

### `setup-user.sh`
Create the `tianzhic` user with sudo and docker access.
```bash
sudo ./scripts/setup-user.sh
```

## 🧪 Testing Scripts

### `integration_test.py`
Test all API endpoints and functionality.
```bash
./scripts/integration_test.py
```

### `audio_integration_test.py` 
Test audio generation and caching.
```bash
./scripts/audio_integration_test.py
```

---

## Quick Start

1. **Setup server**: `sudo ./scripts/setup-user.sh`
2. **Start services**: `./scripts/server_start.sh`
3. **Test everything**: `./scripts/integration_test.py`
4. **Clean restart**: `./scripts/restart-clean.sh` (if needed)