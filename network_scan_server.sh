#!/bin/bash
# ============================================================
# network_scan_server.sh — iPerf3 server setup & watchdog
# Compatible with: macOS, Linux, WSL
# Usage: ./iperf3_server.sh [--port 5201] [--whitelist "1.2.3.4,5.6.7.8"]
# ============================================================

# ---------- CONFIG (edit these) ----------
PORT=5201
MAX_CONNECTIONS=3             # Max simultaneous clients (informational — iperf3 handles 1 at a time)
WHITELIST=""                  # Comma-separated allowed IPs (leave empty to allow all)
LOG_DIR="$HOME/iperf3_logs"
WATCHDOG_INTERVAL=30          # Seconds between watchdog checks
ONE_OFF=false                 # true = exit after one test (safer for public exposure)
# -----------------------------------------

# Parse CLI args
while [[ "$#" -gt 0 ]]; do
  case $1 in
    --port)       PORT="$2"; shift ;;
    --whitelist)  WHITELIST="$2"; shift ;;
    --one-off)    ONE_OFF=true ;;
    --log-dir)    LOG_DIR="$2"; shift ;;
    *) echo "Unknown param: $1"; exit 1 ;;
  esac
  shift
done

mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/server.log"
PID_FILE="$LOG_DIR/iperf3.pid"

# ---------- HELPERS ----------
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }

detect_os() {
  case "$(uname -s)" in
    Darwin) echo "macos" ;;
    Linux)  echo "linux" ;;
    *)      echo "unknown" ;;
  esac
}

# ---------- DEPENDENCY CHECK ----------
check_deps() {
  if ! command -v iperf3 &>/dev/null; then
    echo "iperf3 not found. Install it first:"
    echo "  macOS : brew install iperf3"
    echo "  Linux : sudo apt install iperf3"
    exit 1
  fi
  log "iperf3 found: $(iperf3 --version 2>&1 | head -1)"
}

# ---------- FIREWALL REMINDER ----------
firewall_reminder() {
  log "--- Firewall Reminder ---"
  log "Make sure port $PORT is manually allowed in your firewall before clients connect."
  log "  macOS : System Settings > Network > Firewall"
  log "  Linux : sudo ufw allow $PORT/tcp"
  log "  Linux : sudo iptables -A INPUT -p tcp --dport $PORT -j ACCEPT"
  log "-------------------------"
}

# ---------- SHOW LOCAL IPs ----------
show_ips() {
  log "--- Server IP Addresses ---"
  local os=$(detect_os)
  if [ "$os" = "macos" ]; then
    ifconfig | grep "inet " | grep -v 127.0.0.1 | awk '{print "  " $2}' | tee -a "$LOG_FILE"
  else
    hostname -I 2>/dev/null | tr ' ' '\n' | grep -v '^$' | awk '{print "  " $1}' | tee -a "$LOG_FILE"
  fi

  # Show Tailscale IP if available
  if command -v tailscale &>/dev/null; then
    local ts_ip=$(tailscale ip -4 2>/dev/null)
    [ -n "$ts_ip" ] && log "  Tailscale IP: $ts_ip"
  fi
  log "---------------------------"
}

# ---------- START IPERF3 ----------
start_iperf3() {
  local flags="-s -p $PORT"
  $ONE_OFF && flags="$flags --one-off"

  log "Starting iperf3 server on port $PORT..."
  [ "$ONE_OFF" = true ] && log "Mode: one-off (exits after one client)"
  [ -n "$WHITELIST" ] && log "Whitelist: $WHITELIST (enforced via firewall, not iperf3)"

  iperf3 $flags >> "$LOG_FILE" 2>&1 &
  IPERF_PID=$!
  echo "$IPERF_PID" > "$PID_FILE"
  log "iperf3 started with PID $IPERF_PID"
}

# ---------- WATCHDOG ----------
watchdog() {
  log "Watchdog started (checking every ${WATCHDOG_INTERVAL}s)"
  while true; do
    sleep "$WATCHDOG_INTERVAL"
    if ! kill -0 "$IPERF_PID" 2>/dev/null; then
      log "WARNING: iperf3 crashed or exited. Restarting..."
      start_iperf3
    fi
  done
}

# ---------- CLEANUP ON EXIT ----------
cleanup() {
  log "Shutting down..."
  [ -f "$PID_FILE" ] && kill "$(cat $PID_FILE)" 2>/dev/null
  rm -f "$PID_FILE"
  log "Done."
  exit 0
}
trap cleanup SIGINT SIGTERM

# ---------- MAIN ----------
echo "================================================"
echo " iPerf3 Server"
echo " Port      : $PORT"
echo " Whitelist : ${WHITELIST:-"(none — open to all)"}"
echo " One-off   : $ONE_OFF"
echo " Logs      : $LOG_FILE"
echo "================================================"
echo ""

check_deps
firewall_reminder
show_ips
start_iperf3

# Run watchdog in foreground (keeps script alive)
watchdog
