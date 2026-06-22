#!/bin/bash
# Wait for mod-host to be accepting connections on its control port.
# Exits 1 after 15 s so mod-ui.service fails fast rather than hanging forever.
deadline=$(( $(date +%s) + 15 ))
while ! nc -z localhost 5555 2>/dev/null; do
    if [ "$(date +%s)" -ge "$deadline" ]; then
        echo "wait-for-mod-host: timed out after 15 s" >&2
        exit 1
    fi
    sleep 0.5
done
