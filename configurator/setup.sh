#!/bin/sh
set -e

# ─── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[setup]${NC} $*"; }
warn() { echo -e "${YELLOW}[setup]${NC} $*"; }
err()  { echo -e "${RED}[setup]${NC} $*"; }

# ─── Media directories ────────────────────────────────────────────────────────
log "Creating media directories..."
mkdir -p /data/media/movies /data/media/tv
chmod -R 777 /data/media
log "Media directories ready: /data/media/{movies,tv}"

# ─── Wait for service ─────────────────────────────────────────────────────────
wait_for() {
  local name="$1" url="$2" max="${3:-60}"
  local i=0
  log "Waiting for ${name}..."
  while ! curl -sf "$url" >/dev/null 2>&1; do
    i=$((i + 1))
    if [ "$i" -ge "$max" ]; then
      err "${name} not ready after ${max}s, skipping"
      return 1
    fi
    sleep 2
  done
  log "${name} is ready"
  return 0
}

# ─── API helpers ──────────────────────────────────────────────────────────────
api_get() {
  curl -sf -H "X-Api-Key: $2" "$1" 2>/dev/null
}

api_post() {
  curl -sf -X POST \
    -H "Content-Type: application/json" \
    -H "X-Api-Key: $3" \
    -d "$2" \
    "$1" 2>/dev/null
}

api_put() {
  curl -sf -X PUT \
    -H "Content-Type: application/json" \
    -H "X-Api-Key: $3" \
    -d "$2" \
    "$1" 2>/dev/null
}

# ─── Read API key from config.xml ─────────────────────────────────────────────
get_api_key() {
  local config_file="$1"
  if [ -f "$config_file" ]; then
    grep -o '<ApiKey>[^<]*</ApiKey>' "$config_file" | sed 's/<[^>]*>//g'
  fi
}

# ─── Wait for all services ────────────────────────────────────────────────────
log "Waiting for services to start (30s)..."
sleep 30

wait_for "Sonarr"  "http://sonarr:8989/api/v3/system/status" || true
wait_for "Radarr"  "http://radarr:7878/api/v3/system/status" || true
wait_for "Prowlarr" "http://prowlarr:9696/api/v1/system/status" || true
wait_for "qBittorrent" "http://qbittorrent:8085/" || true
wait_for "Tdarr"   "http://tdarr:8265" || true
wait_for "Bazarr"  "http://bazarr:6767" || true

# ─── Read API keys from config volumes ────────────────────────────────────────
SONARR_API=$(get_api_key /config/sonarr/config.xml)
RADARR_API=$(get_api_key /config/radarr/config.xml)
PROWLARR_API=$(get_api_key /config/prowlarr/config.xml)

if [ -z "$SONARR_API" ]; then
  warn "Could not read Sonarr API key from /config/sonarr/config.xml"
  warn "Set SONARR_API_KEY env var or check volume mounts"
fi
if [ -z "$RADARR_API" ]; then
  warn "Could not read Radarr API key from /config/radarr/config.xml"
  warn "Set RADARR_API_KEY env var or check volume mounts"
fi
if [ -z "$PROWLARR_API" ]; then
  warn "Could not read Prowlarr API key from /config/prowlarr/config.xml"
  warn "Set PROWLARR_API_KEY env var or check volume mounts"
fi

# Allow env var overrides
SONARR_API="${SONARR_API_KEY:-$SONARR_API}"
RADARR_API="${RADARR_API_KEY:-$RADARR_API}"
PROWLARR_API="${PROWLARR_API_KEY:-$PROWLARR_API}"

# Bazarr API key from config.ini
BAZARR_API=""
if [ -f /config/bazarr/config.ini ]; then
  BAZARR_API=$(grep -A1 '\[auth\]' /config/bazarr/config.ini 2>/dev/null | grep 'api_key' | cut -d'=' -f2 | tr -d ' ')
fi
BAZARR_API="${BAZARR_API_KEY:-$BAZARR_API}"

# ═════════════════════════════════════════════════════════════════════════════
# SONARR Configuration
# ═════════════════════════════════════════════════════════════════════════════
if [ -n "$SONARR_API" ]; then
  log "Configuring Sonarr..."

  # Add root folder
  api_post "http://sonarr:8989/api/v3/rootfolder" \
    '{"path":"/data/media/tv"}' \
    "$SONARR_API" >/dev/null || warn "Sonarr root folder may already exist"

  # Add qBittorrent download client
  api_post "http://sonarr:8989/api/v3/downloadclient" \
    '{
      "enable":true,
      "protocol":"torrent",
      "name":"qBittorrent",
      "implementation":"QBittorrent",
      "configContract":"QBittorrentSettings",
      "fields":[
        {"name":"host","value":"qbittorrent"},
        {"name":"port","value":8085},
        {"name":"username","value":"'"${QBIT_USERNAME:-admin}"'"},
        {"name":"password","value":"'"${QBIT_PASSWORD:-adminadmin}"'"},
        {"name":"movieCategory","value":"sonarr"},
        {"name":"recentMoviePriority","value":0},
        {"name":"olderMoviePriority","value":0},
        {"name":"initialState","value":0},
        {"name":"sequentialOrder","value":false},
        {"name":"firstAndLast","value":false}
      ]
    }' \
    "$SONARR_API" >/dev/null || warn "Sonarr qBittorrent client may already exist"

  log "Sonarr configured"
else
  warn "Skipping Sonarr configuration (no API key)"
fi

# ═════════════════════════════════════════════════════════════════════════════
# RADARR Configuration
# ═════════════════════════════════════════════════════════════════════════════
if [ -n "$RADARR_API" ]; then
  log "Configuring Radarr..."

  # Add root folder
  api_post "http://radarr:7878/api/v3/rootfolder" \
    '{"path":"/data/media/movies"}' \
    "$RADARR_API" >/dev/null || warn "Radarr root folder may already exist"

  # Add qBittorrent download client
  api_post "http://radarr:7878/api/v3/downloadclient" \
    '{
      "enable":true,
      "protocol":"torrent",
      "name":"qBittorrent",
      "implementation":"QBittorrent",
      "configContract":"QBittorrentSettings",
      "fields":[
        {"name":"host","value":"qbittorrent"},
        {"name":"port","value":8085},
        {"name":"username","value":"'"${QBIT_USERNAME:-admin}"'"},
        {"name":"password","value":"'"${QBIT_PASSWORD:-adminadmin}"'"},
        {"name":"movieCategory","value":"radarr"},
        {"name":"recentMoviePriority","value":0},
        {"name":"olderMoviePriority","value":0},
        {"name":"initialState","value":0},
        {"name":"sequentialOrder","value":false},
        {"name":"firstAndLast","value":false}
      ]
    }' \
    "$RADARR_API" >/dev/null || warn "Radarr qBittorrent client may already exist"

  log "Radarr configured"
else
  warn "Skipping Radarr configuration (no API key)"
fi

# ═════════════════════════════════════════════════════════════════════════════
# PROWLARR Configuration
# ═════════════════════════════════════════════════════════════════════════════
if [ -n "$PROWLARR_API" ]; then
  log "Configuring Prowlarr..."

  # Add Sonarr as an application
  if [ -n "$SONARR_API" ]; then
    api_post "http://prowlarr:9696/api/v1/applications" \
      '{
        "syncLevel":"fullSync",
        "name":"Sonarr",
        "implementation":"Sonarr",
        "configContract":"SonarrSettings",
        "fields":[
          {"name":"prowlarrUrl","value":"http://prowlarr:9696"},
          {"name":"baseUrl","value":"http://sonarr:8989"},
          {"name":"apiKey","value":"'"$SONARR_API"'"},
          {"name":"syncCategories","value":[5000,5010,5020,5030,5040,5045,5060,5070,5080]}
        ]
      }' \
      "$PROWLARR_API" >/dev/null || warn "Prowlarr Sonarr app may already exist"
  fi

  # Add Radarr as an application
  if [ -n "$RADARR_API" ]; then
    api_post "http://prowlarr:9696/api/v1/applications" \
      '{
        "syncLevel":"fullSync",
        "name":"Radarr",
        "implementation":"Radarr",
        "configContract":"RadarrSettings",
        "fields":[
          {"name":"prowlarrUrl","value":"http://prowlarr:9696"},
          {"name":"baseUrl","value":"http://radarr:7878"},
          {"name":"apiKey","value":"'"$RADARR_API"'"},
          {"name":"syncCategories","value":[2000,2010,2020,2030,2040,2045,2060,2070,2080]}
        ]
      }' \
      "$PROWLARR_API" >/dev/null || warn "Prowlarr Radarr app may already exist"
  fi

  log "Prowlarr configured"
else
  warn "Skipping Prowlarr configuration (no API key)"
fi

# ═════════════════════════════════════════════════════════════════════════════
# BAZARR Configuration
# ═════════════════════════════════════════════════════════════════════════════
if [ -n "$BAZARR_API" ]; then
  log "Configuring Bazarr..."

  # Add Sonarr
  if [ -n "$SONARR_API" ]; then
    api_post "http://bazarr:6767/api/sonarr" \
      '{
        "name":"Sonarr",
        "hostname":"sonarr",
        "port":8989,
        "api_key":"'"$SONARR_API"'",
        "use_ssl":false,
        "base_url":"",
        "root_folder":"/data/media/tv"
      }' \
      "$BAZARR_API" >/dev/null || warn "Bazarr Sonarr connection may already exist"
  fi

  # Add Radarr
  if [ -n "$RADARR_API" ]; then
    api_post "http://bazarr:6767/api/radarr" \
      '{
        "name":"Radarr",
        "hostname":"radarr",
        "port":7878,
        "api_key":"'"$RADARR_API"'",
        "use_ssl":false,
        "base_url":"",
        "root_folder":"/data/media/movies"
      }' \
      "$BAZARR_API" >/dev/null || warn "Bazarr Radarr connection may already exist"
  fi

  log "Bazarr configured"
else
  warn "Skipping Bazarr configuration (no API key)"
fi

# ═════════════════════════════════════════════════════════════════════════════
# JELLYFIN Configuration
# ═════════════════════════════════════════════════════════════════════════════
log "Jellyfin — add media libraries manually in the web UI:"
log "  Movies: /data/media/movies"
log "  TV Shows: /data/media/tv"

# ═════════════════════════════════════════════════════════════════════════════
# TDARR Configuration
# ═════════════════════════════════════════════════════════════════════════════
log "Tdarr — configure libraries in the web UI:"
log "  Movies: /data/media/movies"
log "  TV Shows: /data/media/tv"

log "Setup complete!"
