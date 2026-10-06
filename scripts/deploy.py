#!/usr/bin/env python3
"""Deploy a new VLESS Reality node and save client configurations locally."""

import argparse
import ipaddress
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import sys
import time
import urllib.parse


REMOTE_SCRIPT = Path(__file__).with_name("remote_deploy.sh")


def valid_ip(value):
    address = ipaddress.ip_address(value)
    if address.version != 4:
        raise ValueError("automatic deployment currently requires IPv4")
    return str(address)


def client_outputs(ip, name, node):
    name_json = json.dumps(name, ensure_ascii=False)
    clash = f'''mixed-port: 7890
allow-lan: false
mode: rule
proxies:
  - name: {name_json}
    type: vless
    server: {ip}
    port: {node["port"]}
    uuid: {node["uuid"]}
    network: tcp
    tls: true
    udp: true
    flow: xtls-rprx-vision
    servername: {node["sni"]}
    client-fingerprint: chrome
    reality-opts:
      public-key: {node["public_key"]}
      short-id: {node["short_id"]}
proxy-groups:
  - name: 节点选择
    type: select
    proxies:
      - {name_json}
      - DIRECT
rules:
  - GEOIP,CN,DIRECT
  - MATCH,节点选择
'''
    params = urllib.parse.urlencode({
        "encryption": "none", "security": "reality", "sni": node["sni"],
        "fp": "chrome", "pbk": node["public_key"], "sid": node["short_id"],
        "type": "tcp", "flow": "xtls-rprx-vision",
    })
    link = (f'vless://{node["uuid"]}@{ip}:{node["port"]}?{params}'
            f'#{urllib.parse.quote(name)}')
    return clash, link


def ssh_run(ip, ssh_port, user, script):
    command = [
        "ssh", "-p", str(ssh_port), "-o", "StrictHostKeyChecking=ask",
        "-o", "ConnectTimeout=10", "-o", "ServerAliveInterval=15",
        f"{user}@{ip}", "bash", "-s",
    ]
    return subprocess.run(command, input=script, text=True, capture_output=True)


def write_private(path, content):
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w") as file:
        file.write(content)


def tcp_probe(ip, port, attempts=3):
    times = []
    for _ in range(attempts):
        start = time.monotonic()
        try:
            socket.create_connection((ip, port), timeout=5).close()
            times.append(round((time.monotonic() - start) * 1000, 1))
        except OSError:
            break
    return times


def main(argv=None):
    parser = argparse.ArgumentParser(description="Deploy sing-box on a new Debian/Ubuntu VPS")
    parser.add_argument("ip", type=valid_ip, help="VPS public IPv4 address")
    parser.add_argument("--ssh-port", type=int, default=22)
    parser.add_argument("--user", default="root")
    parser.add_argument("--name", help="Client node name")
    parser.add_argument("--output", type=Path, help="Directory for client files")
    args = parser.parse_args(argv)
    if not 1 <= args.ssh_port <= 65535:
        parser.error("--ssh-port must be 1..65535")
    if args.user != "root":
        parser.error("automatic deployment currently requires root SSH")
    if not shutil.which("ssh"):
        parser.error("ssh is required")

    ip = args.ip
    name = args.name or f"VPS-{ip}"
    output = args.output or Path.home() / ".codex" / "vps-nodes" / ip
    if output.exists():
        parser.error(f"output already exists: {output}; choose --output for a new deployment")
    print(f"Checking SSH {ip}:{args.ssh_port}...", flush=True)
    try:
        socket.create_connection((ip, args.ssh_port), timeout=5).close()
    except OSError as exc:
        parser.error(f"SSH TCP connection failed: {exc}")

    print("Deploying via SSH (the first connection may ask to verify host fingerprint)...", flush=True)
    result = ssh_run(ip, args.ssh_port, args.user, REMOTE_SCRIPT.read_text())
    if result.returncode:
        print(result.stdout, file=sys.stderr)
        print(result.stderr, file=sys.stderr)
        return result.returncode
    lines = [line.split("=", 1)[1] for line in result.stdout.splitlines()
             if line.startswith("CODEX_NODE_JSON=")]
    if len(lines) != 1:
        print("Deployment output missing node details; inspect VPS before retrying.", file=sys.stderr)
        return 2
    node = json.loads(lines[0])
    clash, link = client_outputs(ip, name, node)
    connect_ms = tcp_probe(ip, node["port"])

    output.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    output.mkdir(mode=0o700)
    write_private(output / "clash.yaml", clash)
    write_private(output / "shadowrocket.txt", link + "\n")
    report = {
        "server": ip, "ssh_port": args.ssh_port,
        "sing_box_version": node["sing_box_version"], "bbr": node["bbr"],
        "vps_system": {key: node.get(key) for key in ("os", "kernel", "cpu_count", "memory_mb", "disk_total_gb")},
        "server_config_checked": True, "server_listening": True,
        "client_to_server_tcp_ms": connect_ms,
        "vps_ip_info": node.get("geo", {}),
        "vps_to_cloudflare_download": node.get("vps_to_cloudflare_download", {}),
        "client_egress_verified": False,
    }
    write_private(output / "report.json", json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(f"Server: {ip}:443; sing-box: {node['sing_box_version']}; BBR: {node['bbr']}")
    print(f"IP info: {node.get('geo', {})}")
    print(f"VPS: {report['vps_system']}")
    print(f"Mac-to-VPS TCP 443: {connect_ms or 'unreachable'} ms")
    print(f"VPS-to-Cloudflare download: {node.get('vps_to_cloudflare_download', {})}")
    print(f"Clash Party: {output / 'clash.yaml'}")
    print(f"Shadowrocket: {output / 'shadowrocket.txt'}")
    print(f"Report: {output / 'report.json'}")
    print("Client egress is not verified until a client imports and selects this node.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
