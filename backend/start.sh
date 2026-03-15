#!/bin/bash
# SIBNA Backend Startup Script

echo "🚀 Starting SIBNA Authentication Backend..."
echo "============================================"

# Check Python
if ! command -v python3 &> /dev/null; then
    echo "❌ Python3 is not installed"
    exit 1
fi

# Create virtual environment if not exists
if [ ! -d "venv" ]; then
    echo "📦 Creating virtual environment..."
    python3 -m venv venv
fi

# Activate virtual environment
source venv/bin/activate

# Install dependencies
echo "📥 Installing dependencies..."
pip install -q -r requirements.txt

# Start server
echo "✅ Starting FastAPI server on http://localhost:8000"
echo "📚 API Docs: http://localhost:8000/docs"
echo ""
python3 -m uvicorn main:app --host 0.0.0.0 --port 8000 --reload
