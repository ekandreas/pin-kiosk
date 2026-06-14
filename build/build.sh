#!/usr/bin/env bash
#
# Bygger Flipperklubben Kiosk-images med pi-gen.
#
#   ./build/build.sh                # bygger pi3, pi4 och pi5
#   ./build/build.sh pi4            # bygger endast pi4
#   USE_DOCKER=1 ./build/build.sh   # bygg i Docker (kräver inte Debian-host)
#
# Kräver en Debian/Ubuntu-host (eller Docker). Färdiga images hamnar i dist/.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/build"
DIST="$ROOT/dist"

PIGEN_DIR="${PIGEN_DIR:-$BUILD/pi-gen}"
PIGEN_REPO="${PIGEN_REPO:-https://github.com/RPi-Distro/pi-gen.git}"
PIGEN_BRANCH="${PIGEN_BRANCH:-arm64}"   # arm64 = 64-bitars Raspberry Pi OS
FIRST_USER_PASS="${FIRST_USER_PASS:-Magnetslingan10}"
ALL_MODELS=(pi3 pi4 pi5)

log() { printf '\033[1;36m[build]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[fel]\033[0m %s\n' "$*" >&2; exit 1; }

# --- Vilka modeller? --------------------------------------------------------
MODELS=("$@")
[ ${#MODELS[@]} -eq 0 ] && MODELS=("${ALL_MODELS[@]}")
for m in "${MODELS[@]}"; do
    [ -f "$BUILD/models/${m}.config.txt" ] || die "Okänd modell: $m (saknar models/${m}.config.txt)"
done

# --- Hämta pi-gen ----------------------------------------------------------
if [ ! -d "$PIGEN_DIR/.git" ]; then
    log "Klonar pi-gen ($PIGEN_BRANCH) → $PIGEN_DIR"
    git clone --depth 1 --branch "$PIGEN_BRANCH" "$PIGEN_REPO" "$PIGEN_DIR"
else
    log "Använder befintlig pi-gen i $PIGEN_DIR"
fi

mkdir -p "$DIST"

# --- Bygg per modell --------------------------------------------------------
for model in "${MODELS[@]}"; do
    log "=== Bygger $model ==="

    # Lägg in vår kiosk-stage i pi-gen.
    STAGE_DST="$PIGEN_DIR/stage-kiosk"
    rm -rf "$STAGE_DST"
    cp -r "$BUILD/stage-kiosk" "$STAGE_DST"

    # Payload = hela on-device-applikationen (kiosk/).
    rm -rf "$STAGE_DST/01-install/files/payload"
    mkdir -p "$STAGE_DST/01-install/files/payload"
    cp -r "$ROOT/kiosk/." "$STAGE_DST/01-install/files/payload/"
    # Inga Python-cachefiler ska bakas in i imagen.
    find "$STAGE_DST/01-install/files/payload" -name '__pycache__' -type d -prune -exec rm -rf {} + 2>/dev/null || true
    find "$STAGE_DST/01-install/files/payload" -name '*.pyc' -delete 2>/dev/null || true

    # Modellspecifik config.txt.
    mkdir -p "$STAGE_DST/02-config/files"
    cp "$BUILD/models/${model}.config.txt" "$STAGE_DST/02-config/files/model-config.txt"

    chmod +x "$STAGE_DST/prerun.sh" "$STAGE_DST"/*/*.sh 2>/dev/null || true

    # Generera pi-gen-config.
    CONFIG_FILE="$PIGEN_DIR/config-${model}"
    sed -e "s|__IMG_NAME__|flipperklubben-kiosk-${model}|g" \
        -e "s|__FIRST_USER_PASS__|${FIRST_USER_PASS}|g" \
        "$BUILD/pi-gen-config/config.tmpl" > "$CONFIG_FILE"

    # Kör bygget.
    (
        cd "$PIGEN_DIR"
        if [ "${USE_DOCKER:-0}" = "1" ]; then
            log "Bygger i Docker …"
            ./build-docker.sh -c "config-${model}"
        else
            [ "$(id -u)" -eq 0 ] || log "Tips: pi-gen kräver root – kör med sudo om bygget avbryts."
            ./build.sh -c "config-${model}"
        fi
    )

    # Samla resultat.
    if compgen -G "$PIGEN_DIR/deploy/*flipperklubben-kiosk-${model}*.img*" > /dev/null; then
        cp -v "$PIGEN_DIR"/deploy/*flipperklubben-kiosk-${model}*.img* "$DIST/"
    fi
    log "=== Klart: $model ==="
done

log "Alla images ligger i: $DIST"
