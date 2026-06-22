#!/bin/bash
# Wait for JACK server to be ready to accept client connections.
# Used as ExecStartPre in services that depend on jack.service,
# because jack.service is Type=simple so systemd considers it
# "started" before the socket is actually ready.

timeout=30
attempts=$((timeout * 4))  # Check every 0.25 seconds

for ((i=0; i<attempts; i++)); do
    if jack_lsp &>/dev/null; then
        echo "JACK is ready"
        exit 0
    fi
    sleep 0.25
done

echo "Timeout waiting for JACK server" >&2
exit 1