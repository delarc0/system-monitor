#!/bin/bash
set -e

cd "$(dirname "$0")"

# Create venv if it doesn't exist
if [ ! -d "venv" ]; then
    echo "Creating virtual environment..."
    python3 -m venv venv
fi

source venv/bin/activate

# Install deps if needed
pip install -q -r requirements.txt

echo "Starting System Monitor..."
python3 main.py