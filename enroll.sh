#!/bin/bash
# =============================================================================
#  SARVIKA TECHNOLOGIES — Laptop Enrollment Script
#  Run as:  sudo bash enroll.sh
#
#  What it does:
#    1. Installs dependencies
#    2. Asks for NAS username, domain and password (3 tries)
#    3. Pulls local.yml from NAS and applies all fleet policies
#    4. Installs nightly auto-sync cron job
#    5. Deletes itself from /tmp when finished
# =============================================================================

set -euo pipefail

# ── Ensure UTF-8 Locale for Ansible ────────────────────────────────────────────
export LC_ALL=C.UTF-8
export LANG=C.UTF-8

# ── NAS settings ───────────────────────────────────────────────────────────────
NAS_HOST="172.26.3.101"
NAS_SHARE="softwares"
NAS_BASE_PATH="ansible/ubuntu-fleet-config-main"
GITHUB_URL="https://raw.githubusercontent.com/kunalislive/ubuntu-fleet-config/main/local.yml"
MOUNT_POINT="/mnt/nas-softwares"
CREDS_FILE="/etc/samba/nas-credentials"   # permanent — used by cron and ansible
# Security fix: private temp dir prevents TOCTOU symlink attacks on /tmp
TMPDIR_ENROLL=$(mktemp -d /root/enroll-XXXXXX)
PLAYBOOK="$TMPDIR_ENROLL/local.yml"
LOG_TAG="SARVIKA-ENROLL"

# ── Colour helpers ─────────────────────────────────────────────────────────────
RED='\033[0;31m';  GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m';     RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*"; exit 1; }

# ── Cleanup trap — unmounts NAS on exit and deletes script ─────────────────────
cleanup() {
    rm -rf "$TMPDIR_ENROLL" 2>/dev/null || true
    rm -f /tmp/enroll.sh 2>/dev/null || true
    mountpoint -q "$MOUNT_POINT" 2>/dev/null && umount "$MOUNT_POINT" 2>/dev/null || true
}
trap cleanup EXIT

# ── Safety check ───────────────────────────────────────────────────────────────
[[ $EUID -ne 0 ]] && error "Run as root:  sudo bash enroll.sh"

# =============================================================================
echo ""
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${CYAN}║   SARVIKA TECHNOLOGIES — Laptop Enrollment               ║${RESET}"
echo -e "${BOLD}${CYAN}║   $(date '+%Y-%m-%d %H:%M:%S')  •  $(hostname)           ║${RESET}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════╝${RESET}"
echo ""
echo -e "  Enter your ${BOLD}NAS credentials${RESET} to begin."
echo -e "  ${YELLOW}These will be securely stored for nightly auto-updates.${RESET}"
echo ""

logger -t "$LOG_TAG" "INFO: Enrollment started on $(hostname) at $(date '+%Y-%m-%d %H:%M:%S')"

# ── Step 1 — Install dependencies ─────────────────────────────────────────────
info "Step 1/5 — Installing dependencies (ansible, cifs-utils)..."
apt-get update -qq
apt-get install -y -qq software-properties-common cifs-utils smbclient curl gnupg
add-apt-repository --yes --update ppa:ansible/ansible 2>/dev/null || true
apt-get install -y -qq ansible
success "Dependencies ready"

# ── Step 2 — Collect NAS credentials and verify mount ─────────────────────────
info "Step 2/5 — NAS credentials & connection"
mkdir -p "$MOUNT_POINT"

MAX_TRIES=3
TRIES=0
MOUNT_SUCCESS=false

while [ $TRIES -lt $MAX_TRIES ]; do
    echo ""
    echo "Authentication Required (Attempt $((TRIES + 1))/$MAX_TRIES)"
    echo "Enter user and password for share “softwares” on “172.26.3.101”:"

    while true; do
        read -rp "User [firstname.lastname@sarvika.com]: " NAS_USER
        [[ -n "$NAS_USER" ]] && break
        warn "Username cannot be empty. Try again."
    done

    read -rp "Domain [WORKGROUP]: " NAS_DOMAIN
    NAS_DOMAIN="${NAS_DOMAIN:-WORKGROUP}"

    while true; do
        read -rsp "Password: " NAS_PASS; echo
        [[ -n "$NAS_PASS" ]] && break
        warn "Password cannot be empty. Try again."
    done

    # Write temp creds file
    mkdir -p /etc/samba
    install -m 600 /dev/null "$CREDS_FILE"
    printf "username=%s\npassword=%s\ndomain=%s\n" "$NAS_USER" "$NAS_PASS" "$NAS_DOMAIN" > "$CREDS_FILE"
    
    # Clear password from memory
    NAS_PASS=""; unset NAS_PASS

    # Test the mount
    mountpoint -q "$MOUNT_POINT" && umount "$MOUNT_POINT" 2>/dev/null || true
    
    if mount -t cifs "//${NAS_HOST}/${NAS_SHARE}" "$MOUNT_POINT" \
        -o credentials="$CREDS_FILE",uid=0,gid=0,file_mode=0644,dir_mode=0755,vers=3.0 \
        2>/dev/null; then
        success "Credentials accepted and NAS mounted successfully!"
        MOUNT_SUCCESS=true
        break
    else
        warn "Authentication or mount failed. Please check your credentials."
        rm -f "$CREDS_FILE"
        TRIES=$((TRIES + 1))
    fi
done

if [ "$MOUNT_SUCCESS" = false ]; then
    error "Failed to authenticate and mount NAS after $MAX_TRIES attempts. Cancelling enrollment."
fi

# ── Step 3 — Fetch local.yml ──────────────────────────────────────────────────
info "Step 3/5 — Fetching local.yml from NAS..."

NAS_FETCH_OK=false
NAS_FILE="${MOUNT_POINT}/${NAS_BASE_PATH}/local.yml"

if [ -f "$NAS_FILE" ]; then
    cp "$NAS_FILE" "$PLAYBOOK"
    success "local.yml fetched from NAS (CIFS mount)"
    NAS_FETCH_OK=true
else
    warn "File not found via mount — trying smbclient fallback..."
    if smbclient "//${NAS_HOST}/${NAS_SHARE}" -A "$CREDS_FILE" \
        -c "get ${NAS_BASE_PATH}/local.yml ${PLAYBOOK}" 2>/dev/null && [ -s "$PLAYBOOK" ]; then
        success "local.yml fetched via smbclient"
        NAS_FETCH_OK=true
    fi
fi

# Fall back to GitHub
if [ "$NAS_FETCH_OK" = false ]; then
    warn "NAS fetch failed — falling back to GitHub..."
    # Security fix: removed -k (TLS certificate verification now enforced)
    if curl -sfL "$GITHUB_URL" -o "$PLAYBOOK" && [ -s "$PLAYBOOK" ]; then
        success "local.yml fetched from GitHub (fallback)"
    else
        error "Could not fetch local.yml from NAS or GitHub. Check network/credentials."
    fi
fi

# ── Step 4 — Apply fleet policies via Ansible ─────────────────────────────────
echo ""
echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${BOLD}  Step 4/5 — Applying fleet policies (~5–10 minutes)            ${RESET}"
echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""

ansible-playbook "$PLAYBOOK"
success "Fleet policies applied"

# ── Step 5 — Install nightly auto-sync cron job ───────────────────────────────
info "Step 5/5 — Installing nightly auto-sync..."

# Security: remove immutable flag first so re-enrollment can overwrite fleet-sync.sh
chattr -i /usr/local/bin/fleet-sync.sh 2>/dev/null || true

cat > /usr/local/bin/fleet-sync.sh << 'SYNC_SCRIPT'
#!/bin/bash
# Sarvika Fleet — nightly policy sync
# Pulls latest local.yml from NAS (or GitHub fallback) and re-applies it.
NAS_HOST="172.26.3.101"
NAS_SHARE="softwares"
NAS_YML_PATH="ansible/ubuntu-fleet-config-main/local.yml"
GITHUB_URL="https://raw.githubusercontent.com/kunalislive/ubuntu-fleet-config/main/local.yml"
CREDENTIALS_FILE="/etc/samba/nas-credentials"
LOG_TAG="SARVIKA-FLEET"
# Security fix: private temp file prevents TOCTOU attacks on /tmp
DEST=$(mktemp /root/fleet-XXXXXX.yml)
_cleanup_fleet() { rm -f "$DEST" 2>/dev/null || true; }
trap _cleanup_fleet EXIT

if [ -f "$CREDENTIALS_FILE" ]; then
    SMBOPTS="-A $CREDENTIALS_FILE"
else
    SMBOPTS="-N"
fi

if smbclient "//${NAS_HOST}/${NAS_SHARE}" $SMBOPTS \
    -c "get ${NAS_YML_PATH} ${DEST}" 2>/dev/null && [ -s "$DEST" ]; then
    logger -t "$LOG_TAG" "INFO: local.yml synced from NAS on $(hostname)"
elif curl -sfL "$GITHUB_URL" -o "$DEST" && [ -s "$DEST" ]; then
    logger -t "$LOG_TAG" "WARN: NAS unreachable — used GitHub fallback on $(hostname)"
else
    logger -t "$LOG_TAG" "ERROR: local.yml sync FAILED on $(hostname)"
    exit 1
fi

ansible-playbook "$DEST" >> /var/log/ansible-fleet.log 2>&1
SYNC_SCRIPT

chmod 0750 /usr/local/bin/fleet-sync.sh
chattr +i /usr/local/bin/fleet-sync.sh  # immutable: prevents replacement attack

# Install cron — runs nightly at 02:00
echo "0 2 * * * root /usr/local/bin/fleet-sync.sh" > /etc/cron.d/ansible-fleet-pull
chmod 0644 /etc/cron.d/ansible-fleet-pull

success "Nightly sync installed (runs every night at 02:00)"

# ── One-time: give stpl zero dconf restrictions ───────────────────────────────
# stpl profile = user-db:user only → no system-db → no locks of any kind.
# Done here so local.yml never needs to touch the stpl account.
if [ ! -f /etc/dconf/profile/stpl ]; then
    mkdir -p /etc/dconf/profile
    printf 'user-db:user\n' > /etc/dconf/profile/stpl
    success "stpl dconf profile created (zero restrictions)"
else
    success "stpl dconf profile already present — not overwritten"
fi

# cleanup trap fires here → unmounts NAS, deletes /tmp/enroll.sh

echo ""
echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${GREEN}║    Enrollment Complete! Laptop is now managed.           ║${RESET}"
echo -e "${BOLD}${GREEN}║     Nightly sync: every day at 02:00                     ║${RESET}"
echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════════╝${RESET}"
echo ""

logger -t "$LOG_TAG" "INFO: Enrollment COMPLETE on $(hostname) at $(date '+%Y-%m-%d %H:%M:%S')"
