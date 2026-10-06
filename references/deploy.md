# New VPS deployment

On a fresh Debian/Ubuntu VPS, from the Mac terminal run:

```bash
python3 scripts/deploy.py VPS_IP --name NODE_NAME
```

For a nonstandard SSH port, append `--ssh-port PORT`. The default is root on port 22. The first SSH connection may ask for a host fingerprint or password. Compare a new fingerprint with the provider console; changed fingerprints are not accepted automatically. The script stops if TCP 443 or `/etc/sing-box/config.json` already exists. It does not change provider firewalls, so allow inbound TCP 443 there if necessary.

The command saves `clash.yaml`, `shadowrocket.txt`, and `report.json` in `~/.codex/vps-nodes/VPS_IP/` with restricted permissions. Use `--output PATH` for a second run or a different location. `report.json` records server-side validation, BBR, IP information, Mac-to-VPS TCP timing, and VPS-to-Cloudflare download speed. Import the generated client file/link and verify its exit IP; that last step is not automatic because it depends on the user's client selection.

The bundled probe replaces the requested `curl -fsSL https://dl.gsvps.com/install.sh | sh` step with direct IP-information and download checks. It does not provide the broader hardware, streaming-unlock, or return-route report that a specialized third-party probe may generate. If that report is needed, inspect the downloaded script before running it and report the resulting URL separately.

For existing VPS nodes or other Linux distributions, use the manual procedure below.

This is a procedure, not a fixed one-shot installer. Check current official sing-box installation and configuration documentation before choosing commands, because versions and schemas change. The documented Debian/Ubuntu installation is the official package repository or `https://sing-box.app/install.sh`; do not execute an unverified third-party script. Prefer OS-packaged commands appropriate to the actual host.

1. On the Mac, SSH using the confirmed port: `ssh -p SSH_PORT root@SERVER_IP`. Confirm the prompt is on the VPS. If the key has changed, verify its fingerprint through the provider console before updating `known_hosts`.
2. On the VPS, inspect `cat /etc/os-release`, `command -v sing-box`, `sing-box version` if present, `systemctl status sing-box --no-pager`, `ss -lntp`, `ufw status`, and the active SSH port. Inspect `/etc/sing-box/config.json` without printing private keys into chat. If sing-box exists, determine whether to preserve or modify its current inbound.
3. Install sing-box from its official source if absent. Before writing a replacement config, save a dated, root-readable backup of any existing file. Generate a fresh UUID with `sing-box generate uuid`, Reality keypair with `sing-box generate reality-keypair`, and 4-byte hex short ID with `openssl rand -hex 4`. Keep the private key on the VPS.
4. For a simple TCP VLESS Reality inbound, set `listen` to `0.0.0.0`, select the authorized port, set the user `uuid` and `flow` to `xtls-rprx-vision`, and configure TLS Reality with a verified handshake target, the generated private key and short ID. Use a direct outbound. Match client SNI to the configured server name. Do not assume the example target or port is suitable for every host.
5. Run `sing-box check -c /etc/sing-box/config.json`. If it fails, repair the configuration before restart. Open the inbound TCP port in the actual provider firewall and host firewall while preserving the verified SSH port. Start/enable or restart sing-box; inspect `systemctl status sing-box --no-pager`, `journalctl -u sing-box -n 50 --no-pager`, and `ss -lntp4` for the selected port.
6. Generate the Clash Party node and Shadowrocket URL from the public key, UUID, short ID, server address, port, and SNI. Import/select the node. On the Mac, check its proxy egress with `curl -x http://127.0.0.1:7890 --connect-timeout 10 -s https://ipinfo.io/ip` if Clash Party uses port 7890. The result should match the intended VPS egress (which can differ from the server's ingress IP). On Shadowrocket, use its connection/log view or an IP-check page while the node is selected.
7. If egress works, compare speed on the same Mac/network by repeating a fixed download with and without the proxy. Example proxy test: `curl -x http://127.0.0.1:7890 --connect-timeout 10 -L -o /dev/null -w 'speed=%{speed_download} B/s time=%{time_total}s code=%{http_code}\n' 'https://speed.cloudflare.com/__down?bytes=5000000'`. A VPS-local curl is a separate server-to-target measurement.

The automated fresh-server path enables BBR and fq when supported, then reports the actual algorithm. For an existing VPS, record baseline results, check kernel support and the current congestion algorithm, then change only the necessary settings and remeasure. Avoid speculative MTU/MSS and port changes.
