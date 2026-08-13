# Sarvika Technologies — Ubuntu Fleet Management

> **Ansible-based fleet management** — a single-command solution to enroll, harden, and centrally manage Ubuntu laptops across the organisation.

---

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [How It Works](#how-it-works)
- [How to Enroll a New Laptop](#how-to-enroll-a-new-laptop)
- [Recycling / Re-assigning a Laptop](#recycling--re-assigning-a-laptop)
- [File Structure](#file-structure)
- [What the Playbook Does](#what-the-playbook-does)
- [Operations Cheat Sheet](#operations-cheat-sheet)
- [Logs](#logs)
- [Known Issues / TODO](#known-issues--todo)

---

## Overview

This repository manages the **automated, zero-touch configuration** for the Sarvika Technologies Ubuntu fleet. It uses a **NAS-Primary, GitHub-Fallback** architecture:

- **Primary Source (Synology NAS)** — hosts `enroll.sh` and `local.yml` at:
  `smb://172.26.3.101/softwares/ansible/ubuntu-fleet-config-main/`
- **Fallback (GitHub)** — if the NAS is unreachable, machines automatically fall back to pulling `local.yml` from this GitHub repository.
- **Endpoints** — each enrolled laptop runs `/usr/local/bin/fleet-sync.sh` nightly at **2:00 AM** via cron. It tries the NAS first, falls back to GitHub, and runs the Ansible playbook automatically.

Updating `local.yml` on the NAS is **all it takes** to push a policy change to all 90+ laptops within 24 hours.

---

## Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│                     SARVIKA IT INFRASTRUCTURE                        │
│                                                                      │
│  ┌─────────────────────┐          ┌──────────────────────────────┐   │
│  │    Synology NAS     │          │  GitHub (Fallback only)      │   │
│  │    172.26.3.101     │          │  ubuntu-fleet-config         │   │
│  │                     │          │                              │   │
│  │  enroll.sh  ◄───────┤─primary  │  local.yml (if NAS down)     │   │
│  │  local.yml (primary)│ fallback►│                              │   │
│  └──────────┬──────────┘          └──────────────────────────────┘   │
│             │                                                        │
│             ▼ (office — standard or VPN for WFH)                     │
│                              Managed Ubuntu Laptops                  │
│                              fleet-sync.sh (nightly 02:00)           │
│                              1. Try NAS for local.yml                │
│                              2. Fallback to GitHub if NAS down       │
│                              3. ansible-playbook local.yml           │
└──────────────────────────────────────────────────────────────────────┘
```

---

## How It Works

```
New Ubuntu Machine
      │
      ▼
 enroll.sh              ← Run ONCE as root (stpl account) on Day 1
      │
      ├─ Installs dependencies (Ansible, cifs-utils, smbclient)
      ├─ Asks for NAS credentials (firstname.lastname@sarvika.com) — 3 attempts
      ├─ Verifies NAS mount is successful before proceeding
      ├─ Downloads local.yml from NAS (or GitHub fallback)
      ├─ Runs ansible-playbook local.yml (applies all fleet policies)
      ├─ Installs nightly cron job (/etc/cron.d/ansible-fleet-pull)
      ├─ Saves NAS credentials to /etc/samba/nas-credentials (for nightly sync)
      ├─ Creates /etc/dconf/profile/stpl (exempts stpl from all locks)
      └─ Deletes itself from /tmp automatically on exit
             │
             ▼
         local.yml      ← Ansible playbook (idempotent, runs nightly)
             │
             ├─ Validates OS is Ubuntu
             ├─ Installs base packages (git, curl, vim, htop, openssh-server)
             ├─ Configures sudoers / AD group privileges
             ├─ Enables unattended security patching
             ├─ Locks down GNOME desktop (USB, autorun, screen lock, wallpaper)
             ├─ Hardens kernel & network (sysctl, AppArmor, auditd, fail2ban)
             ├─ Deploys legal login banners (SSH + console)
             └─ Schedules monthly software audit → syslog
```

---

## How to Enroll a New Laptop

> ⚠️ **Policy:** `enroll.sh` is hosted exclusively on the internal Synology NAS and is **never distributed publicly**. All enrollments must go through the NAS.

### Step 1 — Download `enroll.sh` from the NAS

Log in to the laptop using your **Active Directory account** (e.g. `kunal.ranjan@sarvika.com`). Open the terminal and run:

```bash
smbclient //172.26.3.101/softwares -U kunal.ranjan -W sarvika.com \
  -c "get ansible/ubuntu-fleet-config-main/enroll.sh /tmp/enroll.sh"
```

*(Enter your AD password when prompted. The file will be saved to `/tmp/enroll.sh`.)*

### Step 2 — Switch to the local IT Admin account

```bash
su - stpl
```

*(Enter the stpl account password. Your terminal will switch to `stpl@...`.)*

### Step 3 — Run the enrollment script

```bash
sudo bash /tmp/enroll.sh
```

The script will now:
1. Install all required dependencies automatically.
2. Ask for your **NAS credentials** (in this exact format):
   ```
   Authentication Required (Attempt 1/3)
   Enter user and password for share "softwares" on "172.26.3.101":
   User [firstname.lastname@sarvika.com]: kunal.ranjan
   Domain [WORKGROUP]: sarvika.com
   Password:
   ```
   > 💡 **Important:** Enter **only your short username** (e.g. `kunal.ranjan`), NOT `kunal.ranjan@sarvika.com`. The `@sarvika.com` part must go in the Domain field.
3. Test the mount immediately — if credentials are wrong, it retries up to **3 times**, then cancels.
4. Download and apply all fleet policies via Ansible.
5. Install the nightly auto-update cron job.
6. Delete itself from `/tmp` automatically when done.

When complete, you will see:
```
╔══════════════════════════════════════════════════════════╗
║    Enrollment Complete! Laptop is now managed.           ║
║     Nightly sync: every day at 02:00                     ║
╚══════════════════════════════════════════════════════════╝
```

### Step 4 — Test the enrollment

Reboot the laptop, then log in as a regular domain user and verify:

| Test | Expected Result |
|---|---|
| Right-click desktop → change wallpaper | ❌ Option is greyed out / locked |
| `sudo apt install vlc` | ❌ Blocked — "not in sudoers file" |
| `sudo /usr/local/bin/safe-update.sh` | ✅ Runs without password (updates the laptop) |
| `id` shows group `1405200512` | ✅ Domain Admin — has full sudo |
| `id` shows only group `1405200513` | ✅ Domain User — restricted correctly |

---

## Recycling / Re-assigning a Laptop

When an employee leaves and you want to give their laptop to someone new:

### Step 1 — Remove the old user from the laptop

Log into `stpl` on the laptop and run:

```bash
# Remove a single specific user
sudo userdel -r old.employee@sarvika.com

# OR remove ALL domain users at once (keeps stpl safe)
for dir in /home/*; do
    user=$(basename "$dir")
    if [ "$user" != "stpl" ]; then
        echo "Removing: $user"
        sudo userdel -r "$user" 2>/dev/null || true
    fi
done
```

> ✅ **Safe:** This only removes the user's **local files** from this laptop. Their Active Directory account on the Windows Server is completely untouched.

### Step 2 — Clear from login screen history

```bash
USERNAME="old.employee"
sudo rm -f /var/lib/AccountsService/users/${USERNAME}
sudo rm -f "/var/lib/AccountsService/users/${USERNAME}@sarvika.com"
sudo rm -f /var/cache/gdm/${USERNAME}
sudo rm -rf "/var/cache/gdm/${USERNAME}@sarvika.com"
sudo systemctl restart gdm3
```

### Step 3 — Re-enroll (optional but recommended)

Run the enrollment script again to ensure all policies are fully up to date:

```bash
smbclient //172.26.3.101/softwares -U kunal.ranjan -W sarvika.com \
  -c "get ansible/ubuntu-fleet-config-main/enroll.sh /tmp/enroll.sh"
sudo bash /tmp/enroll.sh
```

---

## File Structure

```
ubuntu-fleet-config/
├── enroll.sh             # One-time enrollment script — run once on Day 1 as stpl
├── local.yml             # Ansible playbook — keep in sync between NAS and GitHub
└── README.md             # This file

NAS (smb://172.26.3.101/softwares/ansible/ubuntu-fleet-config-main/):
├── enroll.sh             # ← PRIMARY source for enrollment
└── local.yml             # ← PRIMARY source for nightly sync (always update this)

Installed on each laptop by enroll.sh:
├── /usr/local/bin/fleet-sync.sh           # Nightly sync (NAS → GitHub → ansible)
├── /usr/local/bin/safe-update.sh          # Update script — domain users can run this
├── /etc/cron.d/ansible-fleet-pull         # Cron job — runs fleet-sync.sh at 02:00
├── /etc/samba/nas-credentials             # NAS credentials (root-only, mode 600)
└── /etc/dconf/profile/stpl               # Exempts stpl from all dconf locks
```

---

## What the Playbook Does

### 1. Pre-flight Check

- Aborts immediately if the OS is not Ubuntu.

---

### 2. Base Packages

| Package | Purpose |
|---|---|
| `git` | Version control |
| `curl` | Download tool |
| `htop` | Process monitor |
| `vim` | Terminal editor |
| `openssh-server` | Remote SSH access |
| `cifs-utils` | NAS/SMB mounting |
| `smbclient` | NAS file transfer |

Also **disables `fwupd`** (firmware update daemon) to prevent uncontrolled firmware changes.

---

### 3. AD Privilege Control (sudoers)

Deploys `/etc/sudoers.d/ad-policy`:

| AD Group | GID | Permissions |
|---|---|---|
| `domain admins@sarvika.com` | `1405200512` | Full `sudo` (all commands) |
| `domain users@sarvika.com` | `1405200513` | NOPASSWD for `safe-update.sh` only |

Also deploys `/usr/local/bin/safe-update.sh` — domain users run it to update software without root access.

**Sudo hardening:**
- Session timeout: **15 minutes**
- Max password attempts: **3**
- All sudo activity logged to `/var/log/sudo.log`

> 💡 **Note:** The `stpl` local account is NOT affected by these AD rules because it is a local Ubuntu account, not an AD account. It always retains full root access.

---

### 4. Automatic Security Patching

- Daily package list updates
- Daily unattended security upgrades
- Weekly apt cache auto-clean

---

### 5. Desktop Lockdown

| Setting | Value |
|---|---|
| Autorun (USB/media) | Disabled |
| Screen lock | Enabled |
| Screen lock delay | 5 minutes |
| USB mass storage | Blacklisted |
| Network hotspot creation | Blocked (Polkit) |
| Desktop wallpaper | Locked to company wallpaper |

> ✅ **stpl is exempt from all locks** — a special `/etc/dconf/profile/stpl` file with only `user-db:user` (no `system-db`) is created by `enroll.sh` so `stpl` can freely change wallpaper, settings, etc.

---

### 6. Corporate Wallpaper

- Deploys company wallpaper to `/usr/share/backgrounds/company-wallpaper.jpg`
- Locked via `dconf` for all domain users — cannot be changed from GNOME Settings

---

### 7. Security Hardening

**fail2ban** — SSH brute-force protection (max 15 retries, 1 hour ban)

**auditd** — watches `/etc/passwd`, `/etc/sudoers`, `/var/log/auth.log`, and all `execve` calls

**AppArmor** — all profiles enforced

**sysctl** — kernel hardening (ASLR, SYN flood protection, IP forwarding disabled, no ICMP redirects)

---

### 8. Legal Login Banners

Deploys a legal notice to `/etc/issue.net` (SSH) and `/etc/issue` (console).

---

### 9. Software Audit

Runs monthly on the 1st at 02:00. Logs all installed packages (APT, Snap, GUI apps) to syslog:

```
SoftwareAudit: OS=Ubuntu, Host=<hostname>, Date=<YYYY-MM-DD>, Type=<APT|Snap|GUI>, Pkg=<name>, Ver=<version>
```

Rsyslog forwards `SoftwareAudit:` entries to `192.168.1.100:514`.

---

## Operations Cheat Sheet

### Update policies on all laptops (within 24 hours)
1. Edit `local.yml` on your Windows PC.
2. Copy `local.yml` to the NAS at:
   `\\172.26.3.101\softwares\ansible\ubuntu-fleet-config-main\local.yml`
3. Done — all laptops pick it up at 02:00 tonight.

### Force an immediate update on a specific laptop
SSH into the laptop (or open a terminal as `stpl`) and run:
```bash
sudo /usr/local/bin/fleet-sync.sh
```

### Install software on ONE laptop manually (as stpl)
```bash
su - stpl
sudo apt install ./software.deb
# OR
sudo apt install software-name
```

### Check if a laptop is enrolled
```bash
cat /etc/cron.d/ansible-fleet-pull          # Should show the nightly cron
ls -la /usr/local/bin/fleet-sync.sh         # Should exist
ls -la /etc/samba/nas-credentials           # Should exist (mode 600)
```

### See who has admin (sudo) access
```bash
getent group 1405200512   # Domain Admins — full sudo
getent group 1405200513   # Domain Users — restricted
```

### Check what sudo permissions your account has
```bash
sudo -l
```

### Remove a domain user from a laptop
```bash
sudo userdel -r username@sarvika.com
```

### Check nightly sync logs
```bash
cat /var/log/ansible-fleet.log
journalctl -t SARVIKA-FLEET
journalctl -t SARVIKA-ENROLL
```

---

## Scheduled Pull (Auto-Update)

`enroll.sh` installs `/etc/cron.d/ansible-fleet-pull` on each laptop:

```cron
0 2 * * * root /usr/local/bin/fleet-sync.sh
```

`fleet-sync.sh` runs every night at 02:00:

```
1. Try NAS (172.26.3.101) → /etc/samba/nas-credentials used automatically
      └─ Success → run ansible-playbook
2. NAS unreachable? → fetch local.yml from GitHub
      └─ Success → run ansible-playbook
3. Both fail? → log ERROR to syslog, exit (retry tomorrow)
```

---

## Logs

| Log file | Contents |
|---|---|
| `/var/log/ansible-fleet.log` | Output of every nightly Ansible run |
| `/var/log/sudo.log` | All sudo command activity |
| `/var/log/auth.log` | Authentication events |
| `journalctl -t SARVIKA-FLEET` | NAS sync success / GitHub fallback / failures |
| `journalctl -t SARVIKA-ENROLL` | Enrollment events per machine |
| `journalctl -t SARVIKA-BOOTSTRAP` | (legacy) Enrollment events |

---

## Known Issues / TODO

- [ ] Software audit log aggregator IP (`192.168.1.100:514`) is hardcoded — make it a variable.
- [ ] No idempotency guard on `aa-enforce` — minor harmless warning on every run.
- [ ] Keep `local.yml` in sync between NAS and GitHub to avoid drift.

---

> Maintained by the IT Infrastructure team at **Sarvika Technologies**.
