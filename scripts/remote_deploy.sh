#!/usr/bin/env bash
set -euo pipefail

if [[ $(id -u) -ne 0 ]]; then
  echo 'ERROR: run as root on the VPS' >&2
  exit 2
fi
if [[ ! -f /etc/os-release ]]; then
  echo 'ERROR: cannot identify Linux distribution' >&2
  exit 2
fi
. /etc/os-release
if [[ ${ID:-} != ubuntu && ${ID:-} != debian && " ${ID_LIKE:-} " != *" debian "* ]]; then
  echo 'ERROR: automatic deployment supports Debian/Ubuntu only' >&2
  exit 2
fi
package_default_config() {
  [[ -f /etc/sing-box/config.json ]] || return 1
  dpkg -S /etc/sing-box/config.json 2>/dev/null | grep -q '^sing-box:' || return 1
  ! systemctl is-active --quiet sing-box || return 1
  local verify_output
  verify_output=$(dpkg --verify sing-box 2>/dev/null) || return 1
  [[ -z "$verify_output" ]]
}
if [[ -e /etc/sing-box/config.json ]] && ! package_default_config; then
  echo 'ERROR: existing sing-box configuration is not an inactive package default; refusing to replace it' >&2
  exit 2
fi
if command -v ss >/dev/null && ss -ltnH '( sport = :443 )' | grep -q .; then
  echo 'ERROR: TCP 443 is already in use' >&2
  exit 2
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq ca-certificates curl openssl python3 iproute2
if ! command -v sing-box >/dev/null; then
  install -d -m 755 /etc/apt/keyrings
  curl -fsSL https://sing-box.app/gpg.key -o /etc/apt/keyrings/sagernet.asc
  chmod a+r /etc/apt/keyrings/sagernet.asc
  printf '%s\n' 'Types: deb' 'URIs: https://deb.sagernet.org/' 'Suites: *' 'Components: *' 'Enabled: yes' 'Signed-By: /etc/apt/keyrings/sagernet.asc' > /etc/apt/sources.list.d/sagernet.sources
  apt-get update -qq
  apt-get install -y -qq sing-box
fi

UUID=$(sing-box generate uuid | tr -d '\r\n')
KEYPAIR=$(sing-box generate reality-keypair)
PRIVATE_KEY=$(printf '%s\n' "$KEYPAIR" | awk -F': *' 'tolower($1) ~ /^private.?key$/ {print $2; exit}')
PUBLIC_KEY=$(printf '%s\n' "$KEYPAIR" | awk -F': *' 'tolower($1) ~ /^public.?key$/ {print $2; exit}')
SHORT_ID=$(openssl rand -hex 4)
if [[ ! "$UUID" =~ ^[0-9a-fA-F-]{36}$ || ! "$PRIVATE_KEY" =~ ^[A-Za-z0-9_-]{43}$ || ! "$PUBLIC_KEY" =~ ^[A-Za-z0-9_-]{43}$ ]]; then
  echo 'ERROR: unexpected sing-box key-generation output' >&2
  exit 2
fi

install -d -m 755 /etc/sing-box
PACKAGE_BACKUP=
if [[ -e /etc/sing-box/config.json ]]; then
  if ! package_default_config; then
    echo 'ERROR: package default changed during installation; refusing to replace it' >&2
    exit 2
  fi
  PACKAGE_BACKUP="/etc/sing-box/config.json.package-default.$(date -u +%Y%m%dT%H%M%SZ)"
  mv /etc/sing-box/config.json "$PACKAGE_BACKUP"
fi
export UUID PRIVATE_KEY SHORT_ID
python3 - <<'PY'
import json
import os
from pathlib import Path

config = {
    "log": {"level": "info"},
    "inbounds": [{
        "type": "vless", "tag": "vless-reality", "listen": "0.0.0.0",
        "listen_port": 443,
        "users": [{"uuid": os.environ["UUID"], "flow": "xtls-rprx-vision"}],
        "tls": {
            "enabled": True, "server_name": "www.cloudflare.com",
            "reality": {
                "enabled": True,
                "handshake": {"server": "www.cloudflare.com", "server_port": 443},
                "private_key": os.environ["PRIVATE_KEY"],
                "short_id": [os.environ["SHORT_ID"]],
            },
        },
    }],
    "outbounds": [{"type": "direct", "tag": "direct"}],
}
path = Path("/etc/sing-box/config.json")
with path.open("x") as file:
    json.dump(config, file, indent=2)
path.chmod(0o600)
PY
chown root:sing-box /etc/sing-box /etc/sing-box/config.json
chmod 750 /etc/sing-box
chmod 640 /etc/sing-box/config.json
if ! sing-box check -c /etc/sing-box/config.json; then
  rm -f /etc/sing-box/config.json
  if [[ -n "$PACKAGE_BACKUP" ]]; then
    mv "$PACKAGE_BACKUP" /etc/sing-box/config.json
    chown root:root /etc/sing-box
    chmod 755 /etc/sing-box
  fi
  echo 'ERROR: sing-box rejected generated config' >&2
  exit 2
fi

if command -v ufw >/dev/null && ufw status | grep -q '^Status: active'; then
  ufw allow 443/tcp >/dev/null
fi
systemctl enable --now sing-box >/dev/null
SERVICE_READY=0
for _ in {1..20}; do
  if systemctl is-active --quiet sing-box && ss -ltnH '( sport = :443 )' | grep -q .; then
    SERVICE_READY=1
    break
  fi
  sleep 0.25
done
if [[ "$SERVICE_READY" -ne 1 ]]; then
  echo 'ERROR: sing-box did not start listening on TCP 443' >&2
  journalctl -u sing-box -n 20 --no-pager >&2 || true
  exit 2
fi

BBR_STATUS=unsupported
if ! sysctl -n net.ipv4.tcp_available_congestion_control | grep -qw bbr; then
  modprobe tcp_bbr 2>/dev/null || true
fi
if sysctl -n net.ipv4.tcp_available_congestion_control | grep -qw bbr; then
  printf '%s\n' 'net.core.default_qdisc=fq' 'net.ipv4.tcp_congestion_control=bbr' > /etc/sysctl.d/99-sing-box-bbr.conf
  if sysctl -p /etc/sysctl.d/99-sing-box-bbr.conf >/dev/null 2>&1; then
    BBR_STATUS=$(sysctl -n net.ipv4.tcp_congestion_control)
  else
    BBR_STATUS=failed
  fi
fi

export PUBLIC_KEY BBR_STATUS
python3 - <<'PY'
import json
import os
from pathlib import Path
import subprocess

def command(*args):
    try:
        return subprocess.run(args, capture_output=True, text=True, timeout=35).stdout.strip()
    except (OSError, subprocess.TimeoutExpired):
        return ""

def memory_mb():
    for line in Path("/proc/meminfo").read_text().splitlines():
        if line.startswith("MemTotal:"):
            return round(int(line.split()[1]) / 1024)
    return None

geo_raw = command("curl", "-fsS", "--max-time", "10", "https://ipinfo.io/json")
try:
    geo = json.loads(geo_raw)
    geo = {key: geo.get(key) for key in ("ip", "city", "region", "country", "org")}
except json.JSONDecodeError:
    geo = {}

speed_raw = command(
    "curl", "-fsSL", "--max-time", "30", "-o", "/dev/null",
    "-w", "%{speed_download} %{time_total} %{http_code}",
    "https://speed.cloudflare.com/__down?bytes=5000000",
)
speed = {}
try:
    speed_bps, seconds, code = speed_raw.split()
    speed = {"bytes_per_second": float(speed_bps), "seconds": float(seconds), "http_code": int(code)}
except ValueError:
    pass

data = {
    "uuid": os.environ["UUID"],
    "public_key": os.environ["PUBLIC_KEY"],
    "short_id": os.environ["SHORT_ID"],
    "port": 443,
    "sni": "www.cloudflare.com",
    "sing_box_version": subprocess.run(["sing-box", "version"], capture_output=True, text=True).stdout.splitlines()[0],
    "bbr": os.environ["BBR_STATUS"],
    "os": Path("/etc/os-release").read_text().splitlines()[0],
    "kernel": command("uname", "-r"),
    "cpu_count": os.cpu_count(),
    "memory_mb": memory_mb(),
    "disk_total_gb": round(__import__("shutil").disk_usage("/").total / 1_000_000_000, 1),
    "geo": geo,
    "vps_to_cloudflare_download": speed,
}
print("CODEX_NODE_JSON=" + json.dumps(data, separators=(",", ":")))
PY
