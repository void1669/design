#!/usr/bin/env bash
# Run Kali Linux (kalilinux/kali-rolling) as a persistent Docker container.
#
#   ./kali/kali.sh up                  start dockerd if needed, pull image, create container
#   ./kali/kali.sh install [metapkg]   apt install a Kali metapackage (default: kali-linux-headless)
#   ./kali/kali.sh shell               interactive shell inside Kali
#   ./kali/kali.sh exec <cmd...>       run a command inside Kali
#   ./kali/kali.sh status | down | rm
#
# Works behind an HTTPS-only egress proxy (HTTPS_PROXY + custom CA bundle): apt is
# switched to https:// mirrors and pointed at the proxy and CA.
set -euo pipefail

IMAGE="${KALI_IMAGE:-kalilinux/kali-rolling}"
NAME="${KALI_CONTAINER:-kali}"
CA_BUNDLE="${KALI_CA_BUNDLE:-${SSL_CERT_FILE:-/root/.ccr/ca-bundle.crt}}"
PROXY="${HTTPS_PROXY:-${https_proxy:-}}"

log() { printf '\033[1;34m[kali]\033[0m %s\n' "$*" >&2; }

ensure_dockerd() {
  docker info >/dev/null 2>&1 && return
  log "starting dockerd"
  nohup dockerd >/var/log/dockerd.log 2>&1 &
  for _ in $(seq 30); do docker info >/dev/null 2>&1 && return; sleep 1; done
  log "dockerd failed to start; see /var/log/dockerd.log"; exit 1
}

exists()  { docker container inspect "$NAME" >/dev/null 2>&1; }
running() { [ "$(docker container inspect -f '{{.State.Running}}' "$NAME" 2>/dev/null)" = true ]; }

configure_apt() {
  # Kali's default sources use http://; the proxy only tunnels HTTPS.
  docker exec "$NAME" sed -i 's#http://http.kali.org#https://http.kali.org#g' /etc/apt/sources.list.d/kali.sources
  local conf=""
  [ -n "$PROXY" ] && conf+="Acquire::https::Proxy \"$PROXY\";\n"
  [ -f "$CA_BUNDLE" ] && conf+="Acquire::https::CAInfo \"/etc/ssl/certs/host-ca-bundle.crt\";\n"
  docker exec "$NAME" sh -c "printf '$conf' > /etc/apt/apt.conf.d/99host-proxy"
}

up() {
  ensure_dockerd
  docker image inspect "$IMAGE" >/dev/null 2>&1 || { log "pulling $IMAGE"; docker pull "$IMAGE"; }
  if ! exists; then
    log "creating container $NAME"
    local args=(-d --name "$NAME" --hostname kali --network host --cap-add NET_ADMIN --cap-add NET_RAW
                -v kali-root:/root -w /root)
    [ -f "$CA_BUNDLE" ] && args+=(-v "$CA_BUNDLE:/etc/ssl/certs/host-ca-bundle.crt:ro"
                                  -e SSL_CERT_FILE=/etc/ssl/certs/host-ca-bundle.crt)
    [ -n "$PROXY" ] && args+=(-e "HTTPS_PROXY=$PROXY" -e "https_proxy=$PROXY" -e "NO_PROXY=${NO_PROXY:-}")
    docker run "${args[@]}" "$IMAGE" sleep infinity >/dev/null
    configure_apt
  elif ! running; then
    docker start "$NAME" >/dev/null
  fi
  docker exec "$NAME" sh -c '. /etc/os-release; echo "$PRETTY_NAME ($VERSION_ID) is running as container '"$NAME"'"'
}

install() {
  up >/dev/null
  local pkg="${1:-kali-linux-headless}"
  log "apt-get update"
  # Capture first: piping into `grep -q` SIGPIPEs tee and fails the pipeline under pipefail.
  local out
  out="$(docker exec "$NAME" apt-get update -o Acquire::Retries=2 2>&1 || true)"
  printf '%s\n' "$out" >&2
  if ! grep -q '^Hit\|^Get' <<<"$out"; then
    log "cannot reach the Kali mirror (http.kali.org). If you are behind an egress allowlist,"
    log "allow http.kali.org and kali.download, then re-run: $0 install $pkg"
    exit 1
  fi
  log "installing $pkg"
  docker exec -e DEBIAN_FRONTEND=noninteractive "$NAME" apt-get install -y "$pkg"
}

case "${1:-up}" in
  up)      up ;;
  install) shift; install "$@" ;;
  shell)   up >/dev/null; docker exec -it "$NAME" bash -l ;;
  exec)    shift; up >/dev/null; docker exec "$NAME" "$@" ;;
  status)  ensure_dockerd; docker ps -a --filter "name=^${NAME}$" ;;
  down)    docker stop "$NAME" ;;
  rm)      docker rm -f "$NAME" ;;
  *)       sed -n '2,12p' "$0"; exit 1 ;;
esac
