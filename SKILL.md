---
name: sing-box-vps
description: Deploy or troubleshoot a sing-box VLESS Reality node on a Linux VPS, then generate Clash Party and Shadowrocket client configurations and verify end-to-end connectivity. Use for VPS-to-client proxy setup, node migration, or connection failures; not for unrelated VPN protocols.
---

# sing-box VPS to client

Help the user complete the whole chain: VPS access, server configuration, firewall, client import, actual proxy egress, and optional speed comparison. For a fresh Debian/Ubuntu VPS with root SSH, use [scripts/deploy.py](scripts/deploy.py) from the Mac. Read [references/deploy.md](references/deploy.md) for invocation and limitations. For an existing node, inspect its current configuration and skip installation.

## Working rules

- Distinguish Mac shell (`user@Mac %`) from VPS shell (`root@host:~#`) in every command block. `apt`, `systemctl`, and `/etc/sing-box` commands run only on the VPS. Never infer that an SSH command succeeded from a screenshot of a local prompt.
- Gather the actual VPS IP/SSH port, OS, current SSH login method, desired inbound port, and whether sing-box or another service already owns that port. Do not overwrite a working config or rotate node credentials merely to regenerate a client link.
- Treat changed SSH host keys as a verification problem. Ask the user to compare the new fingerprint with the VPS provider console before replacing a `known_hosts` entry. Never disable host-key checking to make the connection work.
- Keep private keys on the VPS. Do not place Reality private keys, SSH private keys, or root passwords in chat, client profiles, or local artifacts. Public key, UUID, and short ID are client credentials: share only with intended users; rotate after unintended exposure.
- Before changing a live service, back up its config and check whether the proposed port is in use. Preserve the active SSH port through any firewall changes. Do not enable a firewall blindly; account for both provider security groups and the VPS firewall.
- Validate the configuration before restarting; then verify service state, IPv4 listening socket, provider firewall/port reachability, client connection, and proxy egress. A running service or open TCP port alone does not prove the node works.
- If a tool can access the VPS, perform authorized deployment and verification. Otherwise give short, copyable commands labeled by machine and ask for output at the point it determines the next step. State which stages remain unverified.
- The automation enables BBR when the VPS kernel offers it, and records `unsupported` or `failed` otherwise. It performs a built-in IP/geolocation and download probe. Do not run `curl ... | sh` for a third-party probe; use a separately reviewed tool only when the user needs a more extensive report.
- For speed claims, test the same target, payload size, client network, and proxy mode more than once. VPS-local download speed does not measure the Mac-to-VPS path. Keep latency and throughput separate.

## Client outputs

For Clash Party (Mihomo), emit one `proxies` item with `type: vless`, `network: tcp`, `tls: true`, `flow: xtls-rprx-vision`, `servername`, `client-fingerprint: chrome`, and `reality-opts.public-key` / `short-id`. Add its exact `name` to the chosen `proxy-groups[].proxies`; check references for stale or misspelled names. Do not promise compatibility with a different Clash core.

For Shadowrocket, emit a URL of this shape, URL-encoding values when needed:

```text
vless://UUID@SERVER:PORT?encryption=none&security=reality&sni=SNI&fp=chrome&pbk=PUBLIC_KEY&sid=SHORT_ID&type=tcp&flow=xtls-rprx-vision#NAME
```

Use a literal hostname such as `www.cloudflare.com`, without Markdown link syntax or backslashes. Give import instructions for the requested client. A link containing credentials is not a hosted subscription URL; do not claim that it auto-updates.

## Completion evidence

Report the server version and config check result, service/listen state, VPS IP information, BBR status, Mac-to-VPS TCP timing, client node selection, observed client exit IP, and speed results if measured. Mark any unperformed step explicitly. The automation's VPS probe and TCP check do not prove client proxy egress; that requires importing/selecting the node and testing through the client.
