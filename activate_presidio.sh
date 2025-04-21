#!/bin/bash
# Helper script to activate the Presidio environment
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/presidio_env/bin/activate"
if [ -f "$SCRIPT_DIR/presidio_env/env_vars.sh" ]; then
    source "$SCRIPT_DIR/presidio_env/env_vars.sh"
    echo "✅ Presidio environment variables loaded"
fi
echo "✅ Presidio environment activated"
