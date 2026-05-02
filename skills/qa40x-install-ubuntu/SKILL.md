---
name: qa40x-install-ubuntu
description: Install QuantAsylum's QA40x audio-analyzer software (drives the QA402 / QA403 hardware) on Ubuntu / Debian-based Linux. The QA40x app is a Windows .NET program that runs on Linux via Mono; this skill handles the full setup — udev rules for USB access, Mono, libusb, optional Wine to extract the EXE installer, then running QA40x.exe under Mono. Trigger this skill whenever the user mentions installing, setting up, reinstalling, troubleshooting, or running QA40x / QA402 / QA403 / QuantAsylum software on Linux — even if they don't say the word "skill" or "install" explicitly. Also trigger for related issues like "QA403 isn't detected on Linux", "udev rules for QuantAsylum", "mono QA40x.exe won't start", "libgdiplus memory leak with QA40x", "Wine setup_QA40x_*.exe", "QA40x crashes on X11 BadAlloc", "GDI+ GenericError in mono", "QA40x renders only title bar / window header", "running QA40x in a VM / qemu / virt-manager", or QA40x XAA / xorg.conf tweaks.
---

# Install QuantAsylum QA40x on Ubuntu

QA40x is QuantAsylum's Windows .NET application for the QA402 / QA403 audio analyzer. On Linux it runs cleanly under Mono. This skill walks the user through a complete install, **detecting what's already in place and only doing the missing steps**, so a partial reinstall doesn't redo work.

## Tested versions

This skill has been validated against the following stack — when versions diverge significantly, re-verify each step before assuming the documented commands still apply:

| Component | Tested versions | Notes |
|---|---|---|
| Ubuntu (host) | **20.04 Focal**, **24.04 Noble** | The user's primary install is on 20.04 Focal. The clean-VM validation run was on 24.04.4 Noble. Codename in the WineHQ source URL must match the actual release (focal / jammy / noble / oracular). |
| QA40x installer | **1.220** (original install on 2025-12-30) and **1.222** (clean-VM test on 2026-05-02) | The application path / install behavior was identical between these two. Re-test if the user is on a substantially newer release (≥ 2.x), since QuantAsylum has signaled a future "QA40x V2" that requires .NET 8 instead of Mono. |
| QA40x firmware | matches the installer release used (firmware updates from Linux are unreliable; user is expected to keep firmware ↔ software paired) | |
| Mono | 6.12.0.x from the official Mono stable repo (works), 6.8.x from Ubuntu universe (slower, has at least one known bug); `mono-runtime` alone is **not enough**, must be `mono-complete` | |
| Wine | wine-stable 9.x and 10.x on 20.04, 11.0 on 24.04 | All three worked for the QA40x EXE installer |
| libusb | 1.0.23 (Focal, definitely works), 1.0.27 (Noble, USB transfers complete cleanly during install but device handshake reliability untested due to VM rendering issues) | |
| libgdiplus | Ubuntu's stock 6.0.4 (works on Focal/host with the XAA workaround); 6.0.5 from source recommended for long sessions | |

If the user is on a newer Ubuntu release (e.g. 26.04 LTS) or a much newer QA40x installer, follow the same procedure but re-test each step and update this skill afterward.

## Operating principles

- **Detect before doing.** Check current state (`which`, `dpkg -l`, `ls /etc/udev/rules.d/`, `mono -V`, etc.) and skip steps already done. Tell the user what's detected and what's left. Don't blindly run the full sequence.
- **Confirm before sudo.** Every step that touches `/etc/`, `/usr/`, or runs `apt`/`dpkg` is a system-level change. Show the exact command, explain what it does, and wait for user confirmation. Don't batch multiple sudo commands into one prompt.
- **Use the user's actual Ubuntu codename**, not a hardcoded one. Run `lsb_release -cs` once early and substitute that codename into the WineHQ source URL.
- **Prefer non-destructive paths.** The Wine step installs ~500 MB and is only needed to extract the EXE. If the user already has `~/qa403/QA40x.exe` or another copy of the install dir from a Windows machine, skip Wine entirely.
- **Don't fight the user's existing setup.** If they already chose Ubuntu's stock `mono-complete` over the Mono official repo, leave it alone. Only escalate if there's an actual problem.

## When to use this skill

Trigger on any of these intents:
- Fresh install of QA40x / QA402 / QA403 on a new Ubuntu machine
- Reinstall on an existing machine (skill detects state and resumes)
- "Why isn't my QA403 detected?" → likely missing udev rules
- "Mono QA40x.exe won't launch" → likely `mono-runtime` instead of `mono-complete`, or missing libgdiplus / libcanberra
- Upgrading Mono, libgdiplus, or QA40x version
- Audio playback through QA40x as ALSA device → out of scope here, just QA40x app install

## The install flow

The full reference document, written from a known-good install, lives at `~/qa403/INSTALL.md` on this user's machine (and at the repo root in this skill's source). The flow has 10 numbered steps. This skill walks through them in order, but **state-detect each one and skip if already done**.

### Faster path: the bundled `install-qa40x.sh` script

The plugin ships a one-shot installer at `scripts/install-qa40x.sh` (in the plugin's source tree, e.g. `~/.claude/plugins/marketplaces/<marketplace>/plugins/qa40x-install-ubuntu/scripts/install-qa40x.sh` or wherever the user cloned the repo). It does everything from Steps 1–6 (and 8) idempotently and is safe to re-run.

**Offer the user the script first** before walking through the steps manually — most people prefer one command over ten:

```bash
./scripts/install-qa40x.sh                              # phase 1: deps
./scripts/install-qa40x.sh --exe ~/Downloads/setup_QA40x_*.exe   # phase 2: install QA40x
```

Useful flags:
- `--exe PATH` — run the QA40x Windows installer under Wine and copy the result into `~/qa403/`. Without this flag the script just installs system dependencies and tells the user where to download the EXE from.
- `--skip-wine` — don't install Wine (use this if the user is copying `~/qa403/` from a Windows machine instead).
- `--no-mono-official` — use Ubuntu's stock `mono-complete` (6.8.x) instead of adding the Mono official `stable-focal` apt source. Slightly older but no third-party repo.
- `-y` / `--yes` — skip the one-time sudo confirmation prompt. Sudo password is still required, just no extra "are you sure?" prompts.

Walk the user through the manual steps below only if they explicitly want to step through them, or if they hit a failure mode the script doesn't handle (e.g., the X11 BadAlloc / GDI+ rendering issues — those need Section "Troubleshooting" below, not a different install path).

### Step 0 — Sanity check & gather context

Run all of these in parallel — they're cheap reads:

```bash
lsb_release -cs                             # ubuntu codename (focal/jammy/noble/...)
uname -m                                    # arch (expect x86_64)
ls /etc/udev/rules.d/51-qa40*.rules 2>/dev/null   # existing udev rules
ls /etc/udev/rules.d/77-mm-qa40x*.rules 2>/dev/null  # ModemManager blacklist (optional)
which mono && mono -V 2>&1 | head -3        # mono presence/version
dpkg -l libusb-1.0-0-dev 2>/dev/null | tail -1   # libusb dev headers
which wine && wine --version 2>/dev/null    # wine presence
ls ~/qa403/QA40x.exe 2>/dev/null            # is QA40x.exe already extracted?
lsusb | grep -iE "16c0:4e3[79]|1fc9:0022" || echo "QA40x device not currently plugged in"
cat /etc/X11/xorg.conf 2>/dev/null | grep -i AccelMethod   # is the XAA workaround in place?
echo "$XDG_SESSION_TYPE"                    # x11 or wayland (Mono needs x11)
systemd-detect-virt                         # is this a VM? affects troubleshooting
```

Summarize the state to the user before proposing any changes. Example: "You already have udev rules for QA403/QA402/bootloader, mono 6.12 from the official repo, libusb-dev, and Wine. `~/qa403/QA40x.exe` is present. Nothing to install — let's just run it."

### Step 1 — udev rules (USB device permissions)

Without these, only root can talk to the analyzer. There are three rules. Check `/etc/udev/rules.d/` for `51-qa403.rules`, `51-qa402.rules`, `51-qa40xBootloader.rules` and only create the ones that are missing.

The exact content (do NOT modify the IDs):

| Rule | VID:PID | File |
|---|---|---|
| QA403 normal mode | `16c0:4e39` | `/etc/udev/rules.d/51-qa403.rules` |
| QA402 normal mode | `16c0:4e37` | `/etc/udev/rules.d/51-qa402.rules` |
| Either device, bootloader mode | `1fc9:0022` | `/etc/udev/rules.d/51-qa40xBootloader.rules` |

Each rule is a single line:

```
SUBSYSTEM =="usb", ATTRS{idVendor}=="<vid>", ATTRS{idProduct}=="<pid>", MODE="0666"
```

Create with `sudo sh -c 'echo "..." > /etc/udev/rules.d/<file>'`. Also drop a ModemManager blacklist so MM doesn't probe non-modem QA40x devices on hot-plug:

```bash
sudo tee /etc/udev/rules.d/77-mm-qa40x-blacklist.rules > /dev/null <<'EOF'
SUBSYSTEMS=="usb", ATTRS{idVendor}=="16c0", ATTRS{idProduct}=="4e39", ENV{ID_MM_DEVICE_IGNORE}="1"
SUBSYSTEMS=="usb", ATTRS{idVendor}=="16c0", ATTRS{idProduct}=="4e37", ENV{ID_MM_DEVICE_IGNORE}="1"
SUBSYSTEMS=="usb", ATTRS{idVendor}=="1fc9", ATTRS{idProduct}=="0022", ENV{ID_MM_DEVICE_IGNORE}="1"
EOF
```

After all rules are in place: `sudo udevadm control --reload-rules`. Tell the user to unplug and re-plug the device if it was already connected.

### Step 2 — Mono runtime

QA40x.exe runs under Mono. Two install paths:

**2a. Stock Ubuntu (simpler):** `sudo apt install mono-complete`

**2b. Mono official stable repo (recommended for long sessions, newer 6.12.x):**

```bash
sudo apt install gnupg ca-certificates
sudo apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 \
  --recv-keys 3FA7E0328081BFF6A14DA29AA6A19B38D3D831EF
echo "deb https://download.mono-project.com/repo/ubuntu stable-focal main" \
  | sudo tee /etc/apt/sources.list.d/mono-official-stable.list
sudo apt update
sudo apt install mono-complete
```

The repo URL says `stable-focal` even on Jammy/Noble — Mono publishes one rolling repo for all recent Ubuntu releases. This is intentional; do not substitute the codename here.

**Critical detail:** Always use `mono-complete`, never `mono-runtime` alone. `mono-runtime` is a stripped-down package missing the WinForms / GDI+ assemblies QA40x needs; the app silently fails to render. If the user already installed `mono-runtime`, run `sudo apt install mono-complete` to upgrade — the meta-package pulls in everything needed.

Verify: `mono -V` should print something like `Mono JIT compiler version 6.12.0.x`.

### Step 3 — libusb development headers

```bash
sudo apt install libusb-1.0-0 libusb-1.0-0-dev
```

Both packages are needed; the QA40x DLLs link against the dev headers' shared object name.

### Step 4 — Wine (only if QA40x.exe is not already extracted)

**Skip this entire step** if `~/qa403/QA40x.exe` already exists, or if the user can copy the install directory from a Windows machine where they ran the installer (`C:\Program Files (x86)\QuantAsylum\QA40x\`).

If Wine is needed, get the user's Ubuntu codename from Step 0 and substitute it into the source URL:

```bash
sudo dpkg --add-architecture i386
sudo mkdir -pm755 /etc/apt/keyrings
sudo wget -O /etc/apt/keyrings/winehq-archive.key \
  https://dl.winehq.org/wine-builds/winehq.key
sudo wget -NP /etc/apt/sources.list.d/ \
  https://dl.winehq.org/wine-builds/ubuntu/dists/<CODENAME>/winehq-<CODENAME>.sources
sudo apt update
sudo apt install --install-recommends winehq-stable
```

**Important:** the codename in the URL must match the actual Ubuntu release (focal / jammy / noble / oracular). Hardcoding the wrong codename is the #1 source of silent install failure here — `apt update` will appear to succeed but `apt install winehq-stable` will fail with "Unable to locate package".

If `apt update` complains about missing files after adding the source: `sudo apt-get update --fix-missing`, then retry.

### Step 5 — Run the installer EXE under Wine

Download the latest installer from <https://github.com/QuantAsylum/QA40x/releases> (look for `setup_QA40x_X.YYY.exe` — current is 1.222 as of 2026-05). Then:

```bash
ls ~/Downloads/setup_QA40x_*.exe   # confirm exact filename (Firefox may save as "setup_QA40x_1.222(1).exe" if duplicate)
wine ~/Downloads/setup_QA40x_<version>.exe
```

On first Wine run you may see prompts to install Wine's own Mono / Gecko (~50 MB) — accept or cancel, doesn't matter; QA40x runs under system Mono. Click through the QA40x installer dialogs and accept defaults. **If the installer window seems to vanish**, it's just hidden behind another window — check `wmctrl -l | grep -i qa40x` or Alt+Tab. If `setup_QA40x_*.tmp` shows in `ps -ef` but no window appears, kill with `wineserver -k` and retry.

### Step 6 — Copy install dir out of the Wine prefix

The Wine prefix path has spaces and parentheses, which is annoying long-term. Copy to `~/qa403/`:

```bash
mkdir -p ~/qa403
cp -rv ~/.wine/drive_c/Program\ Files\ \(x86\)/QuantAsylum/QA40x/* ~/qa403/
```

Expected contents: `QA40x.exe`, `Documentation/`, `UserWeighting/`, `UserWindows/`, `unins000.{exe,dat}`. The `unins000.*` files are the Windows uninstaller and harmless on Linux — they can be deleted but don't have to be.

### Step 7 — Run the app

```bash
cd ~/qa403
mono QA40x.exe
```

The GUI should open. Bottom-left status corner shows whether the analyzer is connected.

### Step 8 — libcanberra-gtk-module (cosmetic)

If the launch terminal shows `Failed to load module "canberra-gtk-module"`, the GUI still works but the warning is noisy. Fix once with:

```bash
sudo apt install libcanberra-gtk-module
```

### Step 9 (optional) — libgdiplus 6.0.5 from source (memory leak fix)

Ubuntu's stock `libgdiplus` is 6.0.4, which has a leak that caps GDI+ object acquisitions to roughly 5000 over a single process lifetime. For users running long measurement sessions this matters; for a casual user, skip it. Verify which version is installed:

```bash
strings /usr/lib/libgdiplus.so | grep "6\.0\."
```

If the user wants 6.0.5, build from source. Get the tarball from <https://github.com/mono/libgdiplus/releases>, then:

```bash
sudo apt install libgif-dev autoconf libtool automake build-essential gettext \
                 libglib2.0-dev libcairo2-dev libtiff-dev libexif-dev
# inside extracted libgdiplus-6.0.5/
./configure
make
sudo make install
cd /usr/lib
sudo rm libgdiplus.so libgdiplus.so.0
sudo ln -s /usr/local/lib/libgdiplus.so.0.0.0 libgdiplus.so
sudo ln -s /usr/local/lib/libgdiplus.so.0.0.0 libgdiplus.so.0
strings /usr/lib/libgdiplus.so | grep "6\.0\."   # should now say 6.0.5
```

The symlink swap step is the riskiest part — never run it without explicit user confirmation, and warn that it overrides the package-managed file (future `apt upgrade` of `libgdiplus` may restore 6.0.4 silently).

### Step 10 — Hardware notes (mention once at the end)

- Use a **heavy-duty USB-A→USB-B cable** with 24 AWG power conductors. The QA40x is USB-bus-powered and a thin cable will drop voltage enough to upset the analog front-end.
- The QA40x app's status bar shows USB voltage. Orange/red background = inadequate power, swap cables.
- **Do not apply firmware updates from Linux.** QuantAsylum's wiki warns the firmware update path is unreliable under Linux. If the app prompts to update firmware, decline. Instead, install the QA40x release whose software version matches the device's existing firmware, or do firmware updates from a Windows machine.

## Common failure modes & fixes

| Symptom | Cause | Fix |
|---|---|---|
| `mono QA40x.exe` opens then immediately closes | `mono-runtime` installed instead of `mono-complete` | `sudo apt install mono-complete` |
| App opens but only the title bar / menu renders, body is transparent | MIT-SHM extension was disabled in the X session | Log out and back in (re-enables MIT-SHM for the new X session) |
| `X11 BadAlloc` on `CreatePixmap` (request 53) at startup, in `Control+DoubleBuffer.Start` | Mono+WinForms+modern X driver pixmap-cache exhaustion | Apply the `AccelMethod XAA` xorg.conf workaround if your X driver supports it (intel/radeon/nouveau). For `modesetting` (default on fresh Ubuntu and VMs): bump `kernel.shmmax`, force X11 (not Wayland), or build libgdiplus 6.0.5. See "X11 rendering troubleshooting" below |
| `System.Exception: Generic Error [GDI+ status: GenericError]` at `Graphics.FillRectangle` | Same root cause as BadAlloc — surfaces here when offscreen pixmap allocation fails inside libgdiplus | Same fixes as BadAlloc above |
| Device not detected even though `lsusb` shows it | udev rules missing or not reloaded; or device was plugged in before reload | Verify rules in `/etc/udev/rules.d/51-qa40*.rules`, run `sudo udevadm control --reload-rules`, unplug and re-plug |
| QA40x window says "Connect the QA403. See File→Device" in orange even though `lsusb` shows the device | The app needs the model selected | `File → Devices → QA403` (or `QA402`) inside the app GUI |
| `apt install winehq-stable` says "Unable to locate package" | Wrong codename in the WineHQ source URL | Re-download with the codename from `lsb_release -cs` |
| `apt update` errors after adding Mono / WineHQ source | Stale lists or signed-by mismatch | `sudo apt-get update --fix-missing`, re-import the GPG key if needed |
| GDI+ exceptions after long sessions, plot stops updating | libgdiplus 6.0.4 leak | Step 9 — build 6.0.5 from source |
| `Failed to load module "canberra-gtk-module"` warning | Module not installed | `sudo apt install libcanberra-gtk-module` (cosmetic only) |
| Wine first-run shows "Install Mono?" / "Install Gecko?" dialogs | Wine wants its own .NET / browser engine | Either accept (~50 MB) or cancel — both work; QA40x runs under system Mono, not Wine's |
| QA40x installer process running but no visible window | Window is hidden behind another | `Alt+Tab` or check taskbar; `wmctrl -l \| grep -i qa40x` to confirm |
| In a VM: lots of `xhci_hcd: WARN Set TR Deq Ptr cmd failed` in dmesg | QEMU xHCI emulation bug with QA40x's interface-claim sequence | Switch VM USB controller to `ich9-ehci1` + 3 UHCI companions. See "Using QA40x in a VM" below |
| ModemManager probing leaves device in confused state on first plug | MM tries to send AT commands to non-modem USB devices | Add `/etc/udev/rules.d/77-mm-qa40x-blacklist.rules` (see updated Step 1) |

## X11 rendering troubleshooting

Mono's WinForms + libgdiplus does aggressive offscreen pixmap allocation for double-buffered controls (charts, panels, splitters). On certain X driver / acceleration combinations this fails with `BadAlloc` on `X_CreatePixmap` (request 53). The failures cascade into `System.Exception: Generic Error [GDI+ status: GenericError]` at `Graphics.FillRectangle` — same root cause, different surface.

**First-line fix (works on this user's host):** force XAA acceleration. The user already has `/etc/X11/xorg.conf` with `Section "Device" / Option "AccelMethod" "XAA"` — keep it intact. If a new install hits the same symptoms and is using `intel`, `radeon`, or `nouveau` X drivers:

```bash
sudo tee /etc/X11/xorg.conf > /dev/null <<'EOF'
Section "Device"
    Identifier "My GPU"
    Option "AccelMethod" "XAA"
EndSection
EOF
sudo systemctl restart gdm
```

**XAA is silently ignored by the modern `modesetting` driver** (default on fresh Ubuntu desktops and inside QEMU/KVM). For those:

1. Bump SHM limits — `sudo sysctl -w kernel.shmmax=2147483648 kernel.shmall=524288` (persist via `/etc/sysctl.d/99-qa40x.conf`).
2. Force X11 session (not Wayland) — at GDM, gear icon → "Ubuntu on Xorg".
3. Build libgdiplus 6.0.5 (Step 9).

## Using QA40x in a VM

The install procedure validates end-to-end on a clean Ubuntu 24.04 KVM/libvirt VM, but the GUI rendering layer is fragile (no real GPU, modesetting driver, no XAA support). What we found:

- **USB controller**: replace QEMU's default `qemu-xhci` (USB 3.0) with `ich9-ehci1` + 3 `ich9-uhci*` companions. xHCI emulation hits `Set TR Deq Ptr cmd failed` and breaks QA40x's interface-claim sequence on the QA403's 5 USB interfaces. EHCI is far more stable.
- **Video model**: switch from `virtio` to `qxl` with `ram=131072 vram=131072 vgamem=32768` for more pixmap headroom.
- **USB passthrough caveats**: when libvirt host-passes the QA403 by VID:PID, the address (`bus`/`device` in the hostdev XML) is captured at attach time. If the user unplugs/replugs on the host, the address changes and libvirt does NOT auto-rebind — you have to `virsh detach-device` then `attach-device` again with the new address.
- **Result**: install procedure validates fine (Mono, Wine, mono QA40x.exe launches, libusb bulk transfers complete with status=0). Connection-handshake reliability remains shaky because of the X11 paint-loop crashes. The tested install path is bare-metal Ubuntu, not virtualized — recommend that for serious use.

## After a successful install

Confirm by running `mono QA40x.exe` from `~/qa403/` and verifying:
1. The GUI opens.
2. With the QA40x device plugged in, the bottom-left status corner shows it as connected.
3. The USB voltage indicator in the status bar is green (not orange/red).

If all three are true, the install is good. Mention to the user that they can update the install reference in `~/qa403/INSTALL.md` if they discovered any new wrinkles during this run.

## References

- Official Linux/macOS wiki: <https://github.com/QuantAsylum/QA40x/wiki/Linux-and-MacOS>
- Getting Started: <https://github.com/QuantAsylum/QA40x/wiki/Getting-Started>
- Releases (installer EXEs): <https://github.com/QuantAsylum/QA40x/releases>
- Mono official stable repo: <https://www.mono-project.com/download/stable/>
- WineHQ Ubuntu instructions: <https://wiki.winehq.org/Ubuntu>
- The user's own install reference: `~/qa403/INSTALL.md` (distilled from a real Noble install on 2026-05-02)
