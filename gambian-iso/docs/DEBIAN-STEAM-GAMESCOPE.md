# Debian trixie: Steam + gamescope (Gamebian)

Gamebian ISOs use **Debian trixie only** for apt — **no sid mixing** (that broke `steam-installer` / `libgpg-error0:i386`).

## ISO / live-build

| Step | What |
|------|------|
| `package-lists/gamescope-build.list.chroot` | `meson`, `ninja`, `git`, gamescope `-dev` deps on squashfs |
| `hooks/normal/997-gamebian-extra-apt-packages.hook.chroot` | Runs `gamebian-install-gamescope` (clone + meson + install) |
| Log | `/var/log/gamebian-install-gamescope.log` inside the chroot during build |

**`./build.sh` needs network** while hook 997 runs (git clone GitHub). Default tag: **`GAMEBIAN_GAMESCOPE_GIT_REF=3.16.22`**.

After a successful ISO build, the live and installed images should report:

```text
gamescope --help
# [gamescope] [Info]  console: gamescope version 3.16.22+ds-1 ...
```

## Steam

- Package: `steam-installer` (non-free + **i386**)
- Install: `sudo gamebian-install-steam` or first-boot terminal (auto-install)
- Requires: `dpkg --add-architecture i386`, contrib + non-free

## gamescope

**Not** installed from sid `.deb` or apt pins.

| Method | When |
|--------|------|
| **trixie apt** | If `gamescope` appears in trixie — tried first |
| **Build from source** | Default — `gamebian-install-gamescope` |

Source build (same as manual flow):

```bash
sudo gamebian-install-gamescope
# or: GAMEBIAN_GAMESCOPE_GIT_REF=3.16.22 sudo gamebian-install-gamescope
```

The script:

1. Disables any legacy `gamebian-sid-install.list` / `gamebian-gamescope-from-sid` pin files
2. `apt build-dep gamescope` + build packages from trixie
3. `git clone https://github.com/ValveSoftware/gamescope.git`
4. `git submodule update --init --recursive`
5. `meson setup build --prefix=/usr` → `ninja -C build install`

Logs on install: `/var/log/gamebian-install-gamescope.log` (Calamares sshprep).

### Fallback

If the build fails (no network, missing deps, VM GPU):

- `/etc/gamebian/steam-without-gamescope` is created
- LightDM **Steam** session runs **fullscreen Steam on X** (no compositor)

## Order on a VM

1. `sudo gamebian-install-steam` (or `scripts/repair-apt-for-steam.sh` if sid was tried earlier)
2. `sudo gamebian-install-gamescope` (needs network + ~10–20 min compile)
3. `gamescope --help`
4. First-boot Steam / reboot → **Steam** session

## Other Debian releases (reference)

| Suite | Steam + gamescope from apt alone |
|-------|--------------------------------|
| bookworm | Both in one suite (gamescope 3.11) |
| trixie | Steam yes; gamescope **source build** (this doc) |
| sid only | Both in apt; whole OS unstable |

## Recovery after old sid experiments

```bash
sudo scripts/repair-apt-for-steam.sh
sudo gamebian-install-gamescope
```
