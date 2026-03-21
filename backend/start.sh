#!/usr/bin/env bash
set -euo pipefail

echo "SIBNA Authentication Backend — starting"
echo "======================================="

if ! command -v python3 &>/dev/null; then
    echo "ERROR: python3 is not installed." >&2
    exit 1
fi

PYTHON_VERSION=$(python3 -c 'import sys; print(sys.version_info.major * 10 + sys.version_info.minor)')
if [ "$PYTHON_VERSION" -lt 310 ]; then
    echo "ERROR: Python 3.10+ required (found $(python3 --version))." >&2
    exit 1
fi

if [ ! -d "venv" ]; then
    echo "Creating virtual environment..."
    python3 -m venv venv
fi

source venv/bin/activate

echo "Installing dependencies..."
pip install -q --upgrade pip
pip install -q -r requirements.txt

if [ -z "${SECRET_KEY:-}" ] || [ -z "${JWT_SECRET:-}" ]; then
    echo ""
    echo "WARNING: SECRET_KEY or JWT_SECRET is not set."
    echo "Copy .env.example to .env and configure all required values."
    echo ""
fi

echo "Server starting on http://0.0.0.0:${PORT:-8000}"

python3 -m uvicorn main:app \
    --host 0.0.0.0 \
    --port "${PORT:-8000}" \
    --reload
