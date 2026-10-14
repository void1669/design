# Kali Linux in Docker

`kali.sh` runs the official `kalilinux/kali-rolling` image as a persistent container
named `kali` (host networking, `NET_ADMIN`/`NET_RAW` for scanners, `/root` kept in the
`kali-root` volume).

```bash
./kali/kali.sh up                        # start dockerd if needed, pull, create/start container
./kali/kali.sh install                   # apt install kali-linux-headless (CLI toolset)
./kali/kali.sh install kali-tools-web    # or any other metapackage / package
./kali/kali.sh shell                     # interactive root shell
./kali/kali.sh exec nmap -sV 127.0.0.1   # one-off command
./kali/kali.sh down | rm                 # stop / delete (volume is kept)
```

## Behind an egress proxy (Claude Code cloud sessions)

The script detects `HTTPS_PROXY` and the CA bundle (`SSL_CERT_FILE`, or
`/root/.ccr/ca-bundle.crt`), mounts the bundle into the container, switches apt to
the `https://kali.download/kali` CDN (override with `KALI_MIRROR`), and points apt at the proxy.

`apt` can only reach Kali's repositories if the environment's network policy allows
them. Add these under **Allowed domains** (environment settings → Network access):

- `kali.download` (Kali's CDN; apt is pointed at it directly)
- `http.kali.org` (optional; only if you switch back to the redirector, which also
  sends downloads to third-party mirrors that would each need allowing)

Docker Hub (`registry-1.docker.io`, `auth.docker.io`, `production.cloudflare.docker.com`)
must also be reachable to pull the image. It is under the default policy.

Cloud containers are ephemeral, so run `./kali/kali.sh up` again at the start of a new session.
