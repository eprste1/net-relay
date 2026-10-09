#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOSTNAME_PUBLIC="${RELAY_HOSTNAME:-vpn.example.com}"

echo "==> [1/2] Self-signed TLS certificate for the Nginx -> tunnel hop"
kubectl create namespace net-relay --dry-run=client -o yaml | kubectl apply -f -
if kubectl get secret net-relay-tls -n net-relay &>/dev/null; then
  echo "    already exists, skipping"
else
  TMP="$(mktemp -d)"
  openssl req -x509 -newkey rsa:2048 -keyout "$TMP/relay.key" -out "$TMP/relay.crt" \
    -days 3650 -nodes -subj '/CN=net-relay' 2>/dev/null
  kubectl create secret tls net-relay-tls -n net-relay \
    --cert="$TMP/relay.crt" --key="$TMP/relay.key"
  rm -rf "$TMP"
  echo "    created"
fi

echo "==> [2/2] Kubernetes manifests"
kubectl apply -k "$DIR"
kubectl rollout status deployment/net-relay -n net-relay --timeout=120s

echo
echo "Next: point a Cloudflare Tunnel public hostname at the service."
echo "  Hostname:      ${HOSTNAME_PUBLIC}"
echo "  Service:       https://$(kubectl get svc net-relay -n net-relay -o jsonpath='{.spec.clusterIP}'):8080"
echo "  No TLS Verify: ON (the certificate above is self-signed)"
echo "See README.md for the cloudflared install and client setup."
