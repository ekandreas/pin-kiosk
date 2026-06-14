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

# Återställ pi-gen-klonen till orört läge så att bygget blir deterministiskt
# oavsett patchar från tidigare körningar.
git -C "$PIGEN_DIR" checkout -- . 2>/dev/null || true
find "$PIGEN_DIR" -name '*.bak' -delete 2>/dev/null || true
find "$PIGEN_DIR" -name '*.bak2' -delete 2>/dev/null || true

# Slopa stage2:s image-export ("-lite") – vi vill bara ha den färdiga
# kiosk-imagen. Stage2-rootfsen byggs fortfarande som bas för vår stage.
rm -f "$PIGEN_DIR/stage2/EXPORT_IMAGE" "$PIGEN_DIR/stage2/EXPORT_NOOBS" 2>/dev/null || true

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
            # Vid native arm64-bygge behövs ingen qemu-emulering, men pi-gen kör
            # ändå dpkg-reconfigure qemu-user-binfmt vilket failar och kortsluter
            # &&-kedjan (cd /pi-gen hoppas över → ./build.sh hittas inte). Gör
            # steget feltolerant.
            sed -i.bak2 's#dpkg-reconfigure qemu-user-binfmt &&#(dpkg-reconfigure qemu-user-binfmt || true) \&\&#' build-docker.sh
            # På native arm64 (t.ex. Apple Silicon) behövs ingen qemu alls, men
            # pi-gens dependency_check kräver ändå kommandot qemu-arm. Ta bort
            # det kravet just då. På x86-host lämnas det kvar (qemu krävs för cross-build).
            DOCKER_ARCH="$(docker info --format '{{.Architecture}}' 2>/dev/null || echo unknown)"
            if [ "$DOCKER_ARCH" = "aarch64" ] || [ "$DOCKER_ARCH" = "arm64" ]; then
                log "Native arm64-motor ($DOCKER_ARCH) – tar bort qemu-kravet ur depends"
                sed -i.bak '/qemu-arm:qemu-user-binfmt/d' depends
            fi
            # Rensa ev. container från en tidigare (misslyckad) körning så att
            # build-docker.sh inte fastnar på en interaktiv fråga.
            docker rm -f pigen_work >/dev/null 2>&1 || true
            ./build-docker.sh -c "config-${model}"
        else
            [ "$(id -u)" -eq 0 ] || log "Tips: pi-gen kräver root – kör med sudo om bygget avbryts."
            ./build.sh -c "config-${model}"
        fi
    )

    # Samla resultat. pi-gen lägger images i deploy/ med varierande ändelse
    # (.zip/.img/.img.xz beroende på komprimering). Kopiera image-filer för
    # denna modell till dist/, men hoppa över .info/.log och ev. -lite.
    found=0
    for f in "$PIGEN_DIR"/deploy/*"flipperklubben-kiosk-${model}"*; do
        [ -e "$f" ] || continue
        case "$f" in
            *-lite*|*.info|*.log) continue ;;
            *.zip|*.img|*.img.gz|*.img.xz) cp -v "$f" "$DIST/"; found=1 ;;
        esac
    done
    [ "$found" = 1 ] || log "VARNING: hittade ingen image för $model i $PIGEN_DIR/deploy/"
    log "=== Klart: $model ==="
done

log "Alla images ligger i: $DIST"
