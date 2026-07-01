# Arrhive

A minimal Docker Compose media automation stack — Jellyfin, Sonarr, Radarr, Prowlarr, qBittorrent, SABnzbd, Seerr, Bazarr. All access via Tailscale, no open ports.

## Setup

**1. Clone & enter**

```bash
git clone https://github.com/mishl-dev/arrhive.git arr-stack && cd arr-stack
```

**2. Configure**

```bash
cp .env.example .env
nano .env
```

Set: `MEDIA_ROOT`, `PUID`/`PGID`, `LAN_SUBNET`, `TZ`.

**3. Start**

```bash
docker compose -f docker-compose.arr-stack.yml up -d
```

**4. Run configurator**

```bash
docker compose -f docker-compose.arr-stack.yml --profile setup up configurator
```

Creates media dirs (`/data/media/movies`, `/data/media/tv`), configures Sonarr/Radarr root folders, connects qBittorrent, and links Prowlarr.

**5. Auth Tailscale**

```bash
docker logs tailscale
# Open URL, authenticate, approve routes
```

**6. Access via Tailscale**

Connect to your tailnet, then hit internal IPs:

| Service | Address |
|---------|---------|
| Jellyfin | `http://172.20.0.4:8096` |
| Sonarr | `http://172.20.0.10:8989` |
| Radarr | `http://172.20.0.11:7878` |
| qBittorrent | `http://172.20.0.17:8085` |
| SABnzbd | `http://172.20.0.18:8080` |
| Prowlarr | `http://172.20.0.19:9696` |
| Seerr | `http://172.20.0.8:5055` |
| Bazarr | `http://172.20.0.9:6767` |
| Homer | `http://172.20.0.30:8080` |

**7. Configure in UIs**

- Prowlarr → add indexers (Nyaa.si for anime, etc.)
- Seerr → link Sonarr/Radarr
- Jellyfin → add media libraries at `/data/media`


