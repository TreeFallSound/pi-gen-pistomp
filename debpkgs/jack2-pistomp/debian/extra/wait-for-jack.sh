#!/bin/bash
# Wait for JACK server to be ready to accept client connections.
# Used as ExecStartPre in services that depend on jack.service,
# because jack.service is Type=simple so systemd considers it
# "started" before the socket is actually ready.
#
# jack_client_open has no internal timeout, hence the per-probe bound.

budget=${WAIT_FOR_JACK_TIMEOUT:-30}
probe_timeout=${WAIT_FOR_JACK_PROBE_TIMEOUT:-2}
deadline=$((SECONDS + budget))

while (( SECONDS < deadline )); do
    if timeout -k 1 "$probe_timeout" jack_lsp &>/dev/null; then
        echo "JACK is ready"
        exit 0
    fi
    sleep 0.25
done

echo "Timeout waiting for JACK server after ${budget}s" >&2
exit 1
