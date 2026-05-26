# GamebianOS QA Checklist (Production Readiness)

This checklist is a **test matrix** for validating GamebianOS across the key production flows: **Live ISO**, **installed disk**, **Steam install + sign-in**, **autologin routing**, **Openbox notices**, **controller menu**, and **Steam/gamescope kiosk**.

## Conventions

- **Target**: the machine you are testing (bare metal preferred; VM ok for some cases).
- **Autologin routing rule (installed)**: autologin goes to **Steam/gamescope** only when Steam is **installed** and the user is **signed in** (`loginusers.vdf` exists). Otherwise autologin goes to **Openbox**.
- **Signed in check**: presence of `loginusers.vdf` in one of:
  - `~/.local/share/Steam/config/loginusers.vdf`
  - `~/.steam/debian-installation/config/loginusers.vdf`
  - `~/.steam/root/config/loginusers.vdf`
- **Openbox notices (installed)**: every time Openbox starts, it must show **all three**:
  - Welcome to desktop mode
  - Visit `http://127.0.0.1:8844` (and LAN IP if available)
  - Logout/reboot guidance (wording changes based on Steam sign-in)

## Quick “state reset” for clean retesting

Run as the install user on the target:

```bash
rm -f ~/.config/gamebian-firstboot-steam.prompted
rm -f ~/.config/gamebian-firstboot-steam.done
rm -f ~/.config/gamebian-firstboot-steam.run-finished
rm -f ~/.config/gamebian/prefer-openbox-desktop
rm -f ~/.config/gamebian/switch-to-openbox
rm -f ~/.config/gamebian/in-gamescope-kiosk-session
rm -f ~/.config/gamebian/pending-openbox-notify
```

If you need to simulate “not signed in” again, you must also remove/rename Steam’s `loginusers.vdf` (paths above).

## Test matrix

### A. Live ISO boot flow

- **A1 — Live ISO always Openbox**
  - **Preconditions**: Boot ISO with `boot=live`
  - **Steps**: Boot to login manager and wait for autologin
  - **Expected**:
    - Autologin lands in **Openbox**
    - Calamares starts (live-only behavior)
    - Steam first-boot terminal does **not** auto-run on live

### B. Installed autologin routing (core production rule)

- **B1 — Steam not installed → Openbox**
  - **Preconditions**: Fresh install; ensure Steam not installed
  - **Steps**: Reboot
  - **Expected**:
    - Autologin goes to **Openbox**
    - Openbox notices show (3 popups)
    - Steam setup terminal launches (once)

- **B2 — Steam bootstrap in progress → Openbox**
  - **Preconditions**: Start Steam install/bootstrap; ensure it is mid-download/first-run
  - **Steps**: Reboot while bootstrap is still running or `.needs-steam-bootstrap` exists
  - **Expected**:
    - Autologin still goes to **Openbox**
    - Openbox notices show (3 popups)
    - No attempt to start gamescope kiosk until bootstrap completes and user signs in

- **B3 — Steam installed but not signed in → Openbox**
  - **Preconditions**: Steam client files present; `loginusers.vdf` does not exist
  - **Steps**: Reboot
  - **Expected**:
    - Autologin goes to **Openbox**
    - Openbox notices show (3 popups)
    - Logout/reboot notice wording mentions “after installed and signed in”

- **B4 — Steam installed and signed in → gamescope Steam**
  - **Preconditions**: Steam installed; user signed in; `loginusers.vdf` exists
  - **Steps**: Reboot
  - **Expected**:
    - Autologin goes to **Steam/gamescope kiosk**
    - Steam launches in gamepad UI

- **B5 — Force desktop override**
  - **Preconditions**: Steam installed and signed in
  - **Steps**:
    - Create `~/.config/gamebian/prefer-openbox-desktop`
    - Reboot
  - **Expected**:
    - Autologin goes to **Openbox** even though signed in
    - Openbox notices show (3 popups)

### C. Openbox notices (must show every time)

- **C1 — Notices appear on first Openbox login**
  - **Preconditions**: Installed disk, Openbox session
  - **Steps**: Log in (autologin) to Openbox
  - **Expected**: You see 3 notifications:
    - **Welcome to desktop**
    - **Visit `http://127.0.0.1:8844`** (and LAN IP if detected)
    - **Logout/reboot guidance**

- **C2 — Notices re-appear on every Openbox login**
  - **Preconditions**: Installed disk, Openbox session
  - **Steps**: Logout/login (or reboot) into Openbox multiple times
  - **Expected**: The same 3 notices show **every** time

- **C3 — Notice wording changes after sign-in**
  - **Preconditions**: Installed disk; sign in to Steam so `loginusers.vdf` exists
  - **Steps**: Return to Openbox (e.g., desktop mode) and/or log in to Openbox
  - **Expected**: The “Steam session” notice changes to the signed-in wording (“You are signed in… logout or reboot…”)

### D. Steam install + sign-in (first-time flow)

- **D1 — Steam setup terminal launches once**
  - **Preconditions**: Installed disk; `~/.config/gamebian-firstboot-steam.prompted` absent
  - **Steps**: Boot into Openbox
  - **Expected**:
    - A terminal opens titled “Install Steam” or “Steam setup”
    - It runs the Steam first-boot helper

- **D2 — Signing in enables Steam session preference**
  - **Preconditions**: Steam setup terminal open
  - **Steps**:
    - Install Steam updates if prompted
    - **Sign in** to a Steam account
    - Quit Steam
  - **Expected**:
    - `loginusers.vdf` exists
    - Steam session enable step succeeds (writes LightDM drop-in + markers)
    - Openbox notices remind to logout/reboot to enter Steam session

- **D3 — Reboot/logout required (no auto reboot)**
  - **Preconditions**: Signed in to Steam
  - **Steps**: Do nothing for 1–2 minutes
  - **Expected**: System does **not** reboot automatically; user must explicitly reboot/logout

### E. Controller menu (conflicts and user messaging)

- **E1 — Controller menu opens on Openbox**
  - **Preconditions**: Openbox session, controller connected
  - **Steps**: Press configured trigger (Guide/Mode or Select+Start)
  - **Expected**:
    - Menu opens
    - Header includes desktop guidance (welcome + reboot/logout + `8844`)

- **E2 — Controller menu disabled during Steam Big Picture on Openbox**
  - **Preconditions**: Openbox session
  - **Steps**:
    - Launch Steam Big Picture (gamepad UI) on the desktop
    - Press the controller-menu trigger
  - **Expected**: Menu does **not** open (prevents input conflict)

- **E3 — Controller menu suppressed in exclusive gamescope kiosk**
  - **Preconditions**: In Steam/gamescope kiosk session
  - **Steps**: Press controller-menu trigger
  - **Expected**: Menu does not open

### F. Steam/gamescope kiosk session

- **F1 — Steam kiosk boots fullscreen**
  - **Preconditions**: Steam installed + signed in
  - **Steps**: Reboot
  - **Expected**:
    - gamescope starts
    - Steam launches in gamepad UI

- **F2 — Switching to Desktop**
  - **Preconditions**: In Steam kiosk
  - **Steps**: Use Steam power menu “Switch to Desktop”
  - **Expected**:
    - Steam/kiosk exits to Openbox (current session handoff)
    - Openbox notices appear

### G. Web UI (`localhost:8844`)

- **G1 — Local web UI reachable**
  - **Preconditions**: Installed disk; Openbox; network up
  - **Steps**: Open a browser to `http://127.0.0.1:8844`
  - **Expected**: UI loads quickly and is usable

- **G2 — LAN web UI reachable**
  - **Preconditions**: Installed disk; Openbox; network up
  - **Steps**: From another device on the LAN, open `http://<target-ip>:8844`
  - **Expected**: UI is reachable (if firewall policy allows)

## Pass/Fail gate (production)

Consider the build **production-ready** only if all are true:

- Autologin routing matches the installed rule in **B1–B4**
- Openbox notices show **every login** in **C1–C3**
- Steam install/sign-in flow works cleanly in **D1–D3**
- Controller menu does **not** conflict with Steam Big Picture in **E2**
- Steam/gamescope kiosk is stable in **F1–F2**
- `localhost:8844` workflow is usable in **G1** (and ideally **G2**)

