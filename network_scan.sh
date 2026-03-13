#!/bin/bash
# ============================================================
# network_scan.sh — Periodic network diagnostic script
# Compatible with: macOS, Linux, WSL
# Usage: ./network_scan.sh --iperf-server <IP> [--interval 300] [--port 5201] [--once] [--iperf-retries 3] [--iperf-retry-delay 5]
# ============================================================

# ---------- CONFIG ----------
IPERF_SERVER=""
IPERF_PORT=5201
PING_TARGETS=("8.8.8.8" "1.1.1.1" "google.com")
PING_COUNT=20                   # Pings per target per scan
DNS_TARGET="google.com"
INTERVAL=300                    # Seconds between scans (default: 5 min)
LOG_DIR="./network_logs"
ONCE=false
IPERF_RETRIES=3              # Retry attempts for iperf3
IPERF_RETRY_DELAY=5          # Seconds between retries
# ----------------------------

# Parse CLI args
while [[ "$#" -gt 0 ]]; do
  case $1 in
    --interval) INTERVAL="$2"; shift ;;
    --iperf-server) IPERF_SERVER="$2"; shift ;;
    --port) IPERF_PORT="$2"; shift ;;
    --once) ONCE=true ;;
    --iperf-retries) IPERF_RETRIES="$2"; shift ;;
    --iperf-retry-delay) IPERF_RETRY_DELAY="$2"; shift ;;
    *) echo "Unknown param: $1"; exit 1 ;;
  esac
  shift
done

# Require --iperf-server
if [ -z "$IPERF_SERVER" ]; then
  echo "Error: --iperf-server <IP> is required"
  echo "Usage: $0 --iperf-server <IP> [--interval 300] [--port 5201] [--once] [--iperf-retries 3] [--iperf-retry-delay 5]"
  exit 1
fi

# Setup
mkdir -p "$LOG_DIR"
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
LOG_FILE="$LOG_DIR/scan_$TIMESTAMP.log"
SUMMARY_FILE="$LOG_DIR/summary.csv"

# Create CSV header if it doesn't exist
if [ ! -f "$SUMMARY_FILE" ]; then
  header="timestamp"
  for target in "${PING_TARGETS[@]}"; do
    safe=$(echo "$target" | tr '.' '_')
    header="${header},${safe}_latency_ms,${safe}_loss_pct"
  done
  header="${header},dns_ms,iperf_mbps"
  echo "$header" > "$SUMMARY_FILE"
fi

# ---------- HELPERS ----------
log() { echo "[$(date '+%H:%M:%S')] $*" | tee -a "$LOG_FILE" >&2; }
section() { echo "" | tee -a "$LOG_FILE" >&2; echo "========== $* ==========" | tee -a "$LOG_FILE" >&2; }
banner() { echo "$*" | tee -a "$LOG_FILE" >&2; }

detect_os() {
  case "$(uname -s)" in
    Darwin) echo "macos" ;;
    Linux)  echo "linux" ;;
    *)      echo "unknown" ;;
  esac
}

# ---------- PING TEST ----------
run_ping() {
  local target=$1
  local os=$(detect_os)
  local result loss avg

  if [ "$os" = "macos" ]; then
    result=$(ping -c "$PING_COUNT" -q "$target" 2>&1)
    loss=$(echo "$result" | grep -oE '[0-9]+(\.[0-9]+)?% packet loss' | grep -oE '[0-9]+(\.[0-9]+)?')
    avg=$(echo "$result" | grep 'round-trip' | awk -F'/' '{print $5}')
  else
    result=$(ping -c "$PING_COUNT" -q "$target" 2>&1)
    loss=$(echo "$result" | grep -oE '[0-9]+(\.[0-9]+)?% packet loss' | grep -oE '[0-9]+(\.[0-9]+)?')
    avg=$(echo "$result" | grep 'rtt' | awk -F'/' '{print $5}')
  fi

  loss=${loss:-"100"}
  avg=${avg:-"N/A"}

  log "  $target → avg latency: ${avg}ms | packet loss: ${loss}%"
  echo "$avg $loss"
}

# ---------- DNS TEST ----------
run_dns() {
  local os=$(detect_os)
  local dns_ms

  if [ "$os" = "macos" ]; then
    dns_ms=$(dig "$DNS_TARGET" | grep "Query time" | awk '{print $4}')
  else
    if command -v dig &>/dev/null; then
      dns_ms=$(dig "$DNS_TARGET" | grep "Query time" | awk '{print $4}')
    else
      dns_ms=$(nslookup "$DNS_TARGET" 2>&1 | grep "^;; Query time" | awk '{print $4}')
    fi
  fi

  dns_ms=${dns_ms:-"N/A"}
  log "  DNS resolution ($DNS_TARGET): ${dns_ms}ms"
  echo "$dns_ms"
}

# ---------- TRACEROUTE ----------
run_traceroute() {
  local target=$1
  local os=$(detect_os)

  traceroute -m 15 "$target" 2>&1 | tee -a "$LOG_FILE" >&2
}

# ---------- IPERF3 TEST ----------
run_iperf() {
  if ! command -v iperf3 &>/dev/null; then
    log "  iperf3 not installed — skipping"
    echo "N/A"
    return
  fi

  local result attempt
  for attempt in $(seq 1 "$IPERF_RETRIES"); do
    result=$(iperf3 -c "$IPERF_SERVER" -p "$IPERF_PORT" -t 10 --connect-timeout 5000 2>&1)

    if echo "$result" | grep -q "error\|failed\|unable\|Connection refused"; then
      if [ "$attempt" -lt "$IPERF_RETRIES" ]; then
        log "  iperf3 → attempt $attempt/$IPERF_RETRIES failed, retrying in ${IPERF_RETRY_DELAY}s..."
        sleep "$IPERF_RETRY_DELAY"
      else
        log "  iperf3 → could not connect to $IPERF_SERVER:$IPERF_PORT after $IPERF_RETRIES attempts"
        echo "N/A"
        return
      fi
    else
      local mbps
      mbps=$(echo "$result" | grep -E "sender|receiver" | tail -1 | awk '{print $(NF-2)}')
      log "  iperf3 throughput: ${mbps} Mbits/sec"
      echo "$mbps"
      return
    fi
  done
}

# ---------- MAIN SCAN ----------
run_scan() {
  local ts=$(date +"%Y-%m-%d %H:%M:%S")
  section "SCAN @ $ts"
  log "Logging to: $LOG_FILE"

  # Ping all targets - use indexed arrays for bash 3.2 compatibility
  section "PING TESTS"
  local ping_avg=()
  local ping_loss=()
  local i=0
  for target in "${PING_TARGETS[@]}"; do
    read -r avg loss <<< $(run_ping "$target")
    ping_avg[$i]="$avg"
    ping_loss[$i]="$loss"
    i=$((i + 1))
  done

  # DNS
  section "DNS TEST"
  dns_ms=$(run_dns)

  # Traceroute (only to first target, to avoid log bloat)
  section "TRACEROUTE → ${PING_TARGETS[0]}"
  run_traceroute "${PING_TARGETS[0]}"

  # iPerf3
  section "IPERF3 THROUGHPUT"
  iperf_mbps=$(run_iperf)

  # Write single summary CSV row for this scan
  local csv_row="$ts"
  i=0
  for target in "${PING_TARGETS[@]}"; do
    csv_row="${csv_row},${ping_avg[$i]},${ping_loss[$i]}"
    i=$((i + 1))
  done
  csv_row="${csv_row},${dns_ms},${iperf_mbps}"
  echo "$csv_row" >> "$SUMMARY_FILE"

  log ""
  if [ "$ONCE" = true ]; then
    log "Scan complete."
  else
    log "Scan complete. Next scan in ${INTERVAL}s. (Ctrl+C to stop)"
  fi
}

# ---------- LOOP ----------
banner "================================================"
banner " Network Scanner"
banner " iPerf3   : $IPERF_SERVER:$IPERF_PORT"
if [ "$ONCE" = true ]; then
banner " Mode     : single scan"
else
banner " Interval : ${INTERVAL}s"
fi
banner " Logs     : $LOG_DIR"
banner "================================================"
banner ""

if [ "$ONCE" = true ]; then
  run_scan
else
  while true; do
    run_scan
    sleep "$INTERVAL"
  done
fi
