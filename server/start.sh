#!/bin/sh
# Starts Vela on the base station: LiveKit for audio, and the control service.
#
#   server/start.sh
#
# Ctrl-C stops both. If one stops by itself, the other is stopped too.
# LiveKit reads the Mac's address when it starts, so run this again after changing networks.
# Ports and keys come from settings.toml.

cd "$(dirname "$0")" || exit 1

# Shell variables from settings.toml: CONTROL_PORT, LIVEKIT_PORT, LIVEKIT_CONFIG.
eval "$(.venv/bin/python - <<'PY'
import shlex
import control

s = control.SETTINGS
config = (
    f"port: {s['livekit_port']}\n"
    f"rtc:\n  tcp_port: {s['livekit_tcp_port']}\n  udp_port: {s['livekit_udp_port']}\n"
    f"keys:\n  {s['api_key']}: {s['api_secret']}\n"
)
print(f"CONTROL_PORT={s['control_port']}")
print(f"LIVEKIT_PORT={s['livekit_port']}")
print(f"LIVEKIT_CONFIG={shlex.quote(config)}")
print(f"BOAT_NAME={shlex.quote(s['boat_name'])}")
PY
)" || exit 1
[ -n "$CONTROL_PORT" ] || { echo "Could not read settings.toml."; exit 1; }

for port in "$LIVEKIT_PORT" "$CONTROL_PORT"; do
    if lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
        echo "Port $port is already in use. Vela is probably running in another window."
        echo "Stop it there with Ctrl-C, then run this again."
        exit 1
    fi
done

mkdir -p logs
# A second copy on other ports, for testing, keeps its own log.
LIVEKIT_LOG=logs/livekit.log
[ "$LIVEKIT_PORT" = 7880 ] || LIVEKIT_LOG="logs/livekit-$LIVEKIT_PORT.log"
livekit-server --dev --bind 0.0.0.0 --config-body "$LIVEKIT_CONFIG" > "$LIVEKIT_LOG" 2>&1 &
LIVEKIT_PID=$!
CONTROL_PID=

stop_all() {
    trap - INT TERM EXIT
    kill "$LIVEKIT_PID" $CONTROL_PID 2>/dev/null
    wait 2>/dev/null
}
trap 'stop_all; echo; echo "Vela stopped."; exit 0' INT TERM
trap stop_all EXIT

# Wait for LiveKit to answer before anything is told it is there.
tries=0
until curl -s -o /dev/null "http://127.0.0.1:$LIVEKIT_PORT/"; do
    tries=$((tries + 1))
    if [ "$tries" -gt 50 ] || ! kill -0 "$LIVEKIT_PID" 2>/dev/null; then
        echo "The audio server did not start. The end of $LIVEKIT_LOG:"
        tail -5 "$LIVEKIT_LOG"
        exit 1
    fi
    sleep 0.2
done

echo "Vela is starting for \"$BOAT_NAME\"."
echo "  Audio server is up. Its log is server/$LIVEKIT_LOG"
echo "  Roster: http://$(scutil --get LocalHostName).local:$CONTROL_PORT"
echo "  Test bench: http://$(scutil --get LocalHostName).local:$CONTROL_PORT/test"
echo "  Ctrl-C stops both."
echo

# No line per request: the pages ask several times a second, and phones in test mode report every two.
.venv/bin/uvicorn control:app --host 0.0.0.0 --port "$CONTROL_PORT" --no-access-log &
CONTROL_PID=$!

while kill -0 "$LIVEKIT_PID" 2>/dev/null && kill -0 "$CONTROL_PID" 2>/dev/null; do
    sleep 1
done

if kill -0 "$CONTROL_PID" 2>/dev/null; then
    echo "The audio server stopped. The end of $LIVEKIT_LOG:"
    tail -5 "$LIVEKIT_LOG"
else
    echo "The control service stopped."
fi
echo "Stopping Vela."
exit 1
