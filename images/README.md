# Gamebian ISO images

Edit PNGs here, then rebuild branding for either ISO profile:

```bash
cd Build/gamebian-iso
./setup.sh
./build.sh
```

```bash
cd Build/gamebian-iso-ubuntu
./setup.sh
./build.sh
```

## calamares/

| File | Used for |
|------|----------|
| `user-icon.png` | Calamares sidebar logo + window icon |
| `image.png` | Calamares welcome screen + slideshow hero |

## live/

| File | Used for |
|------|----------|
| `background.png` | Live ISO desktop wallpaper |

## installed/

| File | Used for |
|------|----------|
| `background.png` | Default installed wallpaper + LightDM greeter background |
| `green.png`, `yellow.png`, `blue.png`, `red.png`, `black.png`, `purple.png` | Per-color wallpapers (right-click desktop → Change Background) |

All PNG/JPG files in this folder are copied to `/usr/share/backgrounds/gamebian-installed/` at build time.

Recommended size: ~16:9 (e.g. 2752×1536).

## grub/

| File | Used for |
|------|----------|
| `grub-16x9.png` | Live USB GRUB menu + installed system GRUB background |
| `grub-4x3.png` | 4:3 displays / isolinux fallback (optional but recommended) |

Recommended size: 1024×640 and 1024×768.

## icons/

| File | Used for |
|------|----------|
| `menu-icon.png` | lxpanel menu button (live ISO) |
| `menu-icon-default.png` | Installed lxpanel menu + controller menu header |
| `user-installed-icon.png` | LightDM greeter avatar, new user `.face` icons |

Do not add extra PNGs here — only these files are copied by the build scripts.
