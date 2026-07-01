# Gamebian ISO profile metadata

Canonical distro-specific values for [`gamebian-iso/`](../gamebian-iso/) (Debian) and [`gamebian-iso-ubuntu/`](../gamebian-iso-ubuntu/) (Ubuntu).

Each profile's `setup.sh` and `build.sh` source the matching `*.env` file. `setup.sh` also stages the matching `*.distro.conf` to `/etc/gamebian/distro.conf` on the ISO.

## Files

| File | Profile | Used by |
|------|---------|---------|
| `debian.env` | Debian trixie | `gamebian-iso/setup.sh`, `gamebian-iso/build.sh` |
| `ubuntu.env` | Ubuntu resolute | `gamebian-iso-ubuntu/setup.sh`, `gamebian-iso-ubuntu/build.sh` |
| `debian.distro.conf` | Debian | Staged to `/etc/gamebian/distro.conf` on Debian ISO |
| `ubuntu.distro.conf` | Ubuntu | Staged to `/etc/gamebian/distro.conf` on Ubuntu ISO |

## Key reference

| Key | Debian | Ubuntu | Consumer |
|-----|--------|--------|----------|
| `GAMEBIAN_PROFILE_ID` | `debian` | `ubuntu` | `setup.sh`, `install-grub-branding.sh` |
| `GAMEBIAN_DISTRO` | `debian` | `ubuntu` | `/etc/gamebian/distro.conf` |
| `GAMEBIAN_SUITE` | `trixie` | `resolute` | `/etc/gamebian/distro.conf` |
| `GAMEBIAN_PRODUCT_NAME` | `Gamebian` | `GamebianUbuntu` | `/etc/gamebian/distro.conf`, Calamares branding |
| `GAMEBIAN_LIVE_HOSTNAME` | `gamebian-openbox` | `gamebian-ubuntu` | `lb --bootappend-live`, `/etc/gamebian/distro.conf` |
| `GAMEBIAN_BUILD_ROOT_VAR` | `GAMEBIANOS_BUILD_ROOT` | `GAMEBIANUBUNTU_BUILD_ROOT` | `setup.sh`, `build.sh` |
| `LB_DISTRIBUTION` | `trixie` | `resolute` | `lb config` |
| `LB_ARCHIVE_AREAS` | contrib/non-free | universe/multiverse | `lb config` |
| `GAMEBIAN_ENSURE_APT_SCRIPT` | `ensure-apt-contrib-nonfree.sh` | `ensure-apt-gaming-repos.sh` | `setup.sh` → `/usr/share/gamebian/` |
| `GAMEBIAN_RETROARCH_LIST` | `debian-retroarch.list` | `ubuntu-retroarch.list` | `setup.sh` → `/usr/share/gamebian/` |
| `GAMEBIAN_GAMESCOPE_STRATEGY` | `source_build` | `apt_preferred` | `/etc/gamebian/distro.conf` (future script unification) |
| `GAMEBIAN_GRUB_CERATOPSIAN` | `1` | `0` | `/etc/gamebian/distro.conf`, `install-grub-branding.sh` |
| `GAMEBIAN_CALAMARES_INSTALLER` | `calamares-install-debian` | `calamares-install-gamebian` | `/etc/gamebian/distro.conf`, live autostart |

## Still profile-specific (not in metadata yet)

These remain under each ISO profile's `overlay/`, `calamares/`, or hooks — documented here for a future unification pass:

- `gamebian-install-gamescope`, `gamebian-install-steam`, `gamebian-apt-unmix-sid.sh`
- Openbox `autostart` (Calamares live launch path)
- Hooks `995`, `997`, `991` (network manager on Ubuntu only)
- Ubuntu live DNS / Calamares prep services
- Calamares `settings.conf`, `welcome.conf`, `packages.conf` (per-ISO `calamares/` trees)

When adding a new distro profile, copy `debian.env` / `debian.distro.conf`, adjust values, and add a sibling `gamebian-iso-<name>/` profile directory.
