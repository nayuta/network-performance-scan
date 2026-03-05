# Network Performance Scan

Periodic network diagnostic scripts for investigating network performance. Designed to run continuously and log latency, packet loss, DNS resolution, traceroute hops, and throughput data over time.

Supports **Twingate** and **Tailscale** for secure tunneling to internal network resources.

## Scripts

### `network_scan.sh` (Client)

Runs periodic scans from a client machine, logging results to CSV and detailed log files.

**Tests performed per scan:**
- **Ping** — latency and packet loss to multiple targets (default: `8.8.8.8`, `1.1.1.1`, `google.com`)
- **DNS** — resolution time via `dig`/`nslookup`
- **Traceroute** — hop-by-hop path to first ping target
- **iPerf3** — throughput measurement against an iperf3 server

**Usage:**
```bash
./network_scan.sh --iperf-server <IP> [--interval 300] [--port 5201] [--once]
```

**Output:**
- Detailed logs: `./network_logs/scan_<timestamp>.log`
- Summary CSV: `./network_logs/summary.csv` (one row per scan)

### `network_scan_server.sh` (Server)

Sets up an iPerf3 server with automatic crash recovery (watchdog).

**Usage:**
```bash
./network_scan_server.sh [--port 5201] [--whitelist "1.2.3.4,5.6.7.8"] [--one-off] [--log-dir ~/iperf3_logs]
```

**Features:**
- Automatic restart on crash (watchdog every 30s)
- Firewall configuration reminders
- Local and Tailscale IP detection
- One-off mode for safer public exposure

## Prerequisites

- `iperf3` — `brew install iperf3` (macOS) / `sudo apt install iperf3` (Linux)
- `dig` — typically pre-installed (part of `dnsutils`/`bind-tools`)
- `traceroute` — typically pre-installed
- **Twingate** or **Tailscale** client connected for access to internal network targets

## Compatibility

macOS, Linux, WSL
