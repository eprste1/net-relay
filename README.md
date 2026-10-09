# net-relay: a personal VPN behind Cloudflare Tunnel

A small VPN relay for Kubernetes (tested on K3s). Clients connect with
**VLESS over XHTTP**; to anyone watching the network it looks like ordinary
HTTPS to a site hosted on Cloudflare. Nothing is exposed on your own network:
`cloudflared` makes only outbound connections.

```
Phone / laptop (VLESS + XHTTP + TLS)
        |
        v
Cloudflare edge          <- TLS terminates here
        |
        v
cloudflared              <- outbound-only tunnel connector
        |
        v
Pod "net-relay"
  |- nginx :8080         <- strips Cloudflare headers
  '- xray  :8081         <- VLESS server, DNS over HTTPS (localhost only)
        |
        v
Internet (your server's IP)
```

## What each piece is for

| Piece | Purpose |
|-------|---------|
| Xray (VLESS + XHTTP) | The VPN engine. XHTTP wraps traffic in plain HTTP requests, so it is not recognisable as a VPN protocol. |
| Cloudflare proxy + Tunnel | Public TLS endpoint and outbound-only connection to your server. No open inbound ports. |
| Nginx | Removes Cloudflare headers (`CF-Connecting-IP`, `X-Forwarded-For`, ...) before Xray sees them, and streams long-lived connections without buffering. |
| DNS over HTTPS | Xray resolves names via 1.1.1.1 / 8.8.8.8 over HTTPS, never plain port 53. |
| Logging off | Xray `access: none`, Nginx `access_log off`. |
| Hardened pod | Non-root, read-only root filesystem, all capabilities dropped, resource limits, image pinned by digest. |

## What privacy this gives you (and what it does not)

This is **not anonymity**.

It protects you from:

- people on the same Wi-Fi / mobile network (they see HTTPS to Cloudflare);
- your ISP seeing destinations;
- networks that block well-known VPN protocols.

It does **not** hide you from:

- **You, the operator.** The server sees destination IPs. Logging is off, but
  that is a configuration choice, not a guarantee.
- **Cloudflare.** It terminates TLS, so it can in principle see the relay
  traffic metadata. End-to-end HTTPS to the sites you visit stays encrypted.
- **Sites you log in to.** Accounts, cookies and fingerprinting still identify you.

Exit traffic leaves from your server's IP. This is a private relay, not Tor.

## Requirements

- A Kubernetes cluster (K3s is fine) and `kubectl`
- A domain on Cloudflare and a Cloudflare Tunnel (Zero Trust -> Networks -> Tunnels)
- `cloudflared` installed on the server, running the tunnel

## Deploy

1. Generate a UUID for each user and put it in `01-configmap.yaml`,
   replacing `REPLACE_WITH_UUID` (add more `{ "id": ..., "level": 0 }` entries
   for more users). Also set `host` to your own hostname.

   ```bash
   cat /proc/sys/kernel/random/uuid
   ```

2. Run the bootstrap (creates a self-signed cert for the Nginx hop and applies
   the manifests):

   ```bash
   RELAY_HOSTNAME=vpn.example.com ./bootstrap.sh
   ```

3. In the Cloudflare dashboard add a **public hostname** to your tunnel:
   - Hostname: your domain, e.g. `vpn.example.com`
   - Service: `https://<ClusterIP printed by bootstrap>:8080`
   - **No TLS Verify: ON** (the Nginx certificate is self-signed)

## Client

Any client that supports VLESS + XHTTP (for example v2rayTUN on Android).
Share link format:

```
vless://<UUID>@vpn.example.com:443?encryption=none&security=tls&sni=vpn.example.com&type=xhttp&path=%2Fapi%2Fdata&mode=auto&host=vpn.example.com#my-vpn
```

The `path` must match `xhttpSettings.path` in `01-configmap.yaml`.

## Add or remove a user

Edit the `clients` list in `01-configmap.yaml`, then:

```bash
kubectl apply -f 01-configmap.yaml
kubectl rollout restart deployment/net-relay -n net-relay
```

## Check it works

```bash
kubectl get pods -n net-relay          # 2/2 Running
curl -s -o /dev/null -w "%{http_code}\n" https://vpn.example.com/api/data   # 400 is expected
```

A plain HTTP request to the XHTTP path is rejected with `400`; that is normal.

## Rotating the Nginx certificate

The self-signed certificate is valid for 10 years. To replace it, delete the
`net-relay-tls` secret and run `./bootstrap.sh` again, then restart the deployment.

## License

MIT
