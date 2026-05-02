# Installing QuantAsylum QA40x on Ubuntu

The QA40x application from QuantAsylum drives the QA402 / QA403 audio analyzers.
It is a Windows .NET app, but it runs cleanly on Linux under Mono. This guide
installs it on Ubuntu using Wine to extract the installer payload, then runs the
extracted executable directly with Mono — no Wine is needed at runtime.

## Tested versions

This procedure has been verified against:

| Component | Tested versions |
|---|---|
| Ubuntu host | **20.04 Focal** (primary install, 2025-12-30), **24.04.4 Noble** (clean-VM validation run, 2026-05-02) |
| QA40x installer | **1.220** and **1.222** |
| Hardware | QA403 (USB VID:PID `16c0:4e39`) |
| Mono | `mono-complete` 6.12.0.x from the official Mono stable-focal repo |
| Wine | wine-stable 9.x / 10.x / 11.0 (all worked) |
| libusb | 1.0.23 on Focal, 1.0.27 on Noble |
| libgdiplus | 6.0.4 (stock Ubuntu); 6.0.5 from source for long sessions |

Earlier Ubuntu releases (22.04 Jammy) work the same way — substitute your
release codename in the Wine repo URL in step 4. If you're on a newer release
(e.g. 26.04 LTS) or a substantially newer QA40x installer (e.g. ≥ 2.x — note
QuantAsylum has signaled a future "QA40x V2" that uses .NET 8 instead of
Mono), re-verify each step before assuming the commands below still apply.

## Prerequisites

- Ubuntu 22.04 or newer (this guide assumes 24.04 Noble)
- A QA402 or QA403 audio analyzer
- A heavy-duty USB-A-to-USB-B cable with 24 AWG power conductors (recommended
  by QuantAsylum to avoid voltage drop on the QA40x's USB-powered analog
  front-end)
- The latest QA40x Windows installer EXE from the official releases page:
  https://github.com/QuantAsylum/QA40x/releases

## 1. Configure udev rules for USB device access

Without these rules, only root can talk to the device. Three rules cover the
QA403 in normal mode, the QA402 in normal mode, and either device in bootloader
mode (used for firmware operations). A fourth optional rule tells ModemManager
to leave the device alone (ModemManager probes new USB devices for AT commands
and can briefly leave non-modem devices in a confused state on first plug-in).

```bash
# QA403 (idVendor=16c0, idProduct=4e39)
sudo sh -c 'echo "SUBSYSTEM ==\"usb\", ATTRS{idVendor}==\"16c0\", ATTRS{idProduct}==\"4e39\", MODE=\"0666\"" > /etc/udev/rules.d/51-qa403.rules'

# QA402 (idVendor=16c0, idProduct=4e37)
sudo sh -c 'echo "SUBSYSTEM ==\"usb\", ATTRS{idVendor}==\"16c0\", ATTRS{idProduct}==\"4e37\", MODE=\"0666\"" > /etc/udev/rules.d/51-qa402.rules'

# Bootloader mode, both devices (idVendor=1fc9, idProduct=0022)
sudo sh -c 'echo "SUBSYSTEM ==\"usb\", ATTRS{idVendor}==\"1fc9\", ATTRS{idProduct}==\"0022\", MODE=\"0666\"" > /etc/udev/rules.d/51-qa40xBootloader.rules'

# Optional: tell ModemManager to ignore QA40x devices
sudo tee /etc/udev/rules.d/77-mm-qa40x-blacklist.rules > /dev/null <<'EOF'
SUBSYSTEMS=="usb", ATTRS{idVendor}=="16c0", ATTRS{idProduct}=="4e39", ENV{ID_MM_DEVICE_IGNORE}="1"
SUBSYSTEMS=="usb", ATTRS{idVendor}=="16c0", ATTRS{idProduct}=="4e37", ENV{ID_MM_DEVICE_IGNORE}="1"
SUBSYSTEMS=="usb", ATTRS{idVendor}=="1fc9", ATTRS{idProduct}=="0022", ENV{ID_MM_DEVICE_IGNORE}="1"
EOF

# Reload so the rules take effect without a reboot
sudo udevadm control --reload-rules
```

If the device was already plugged in, unplug and re-plug it so the new
permissions apply.

## 2. Install Mono

Two options. **2b is recommended** — Ubuntu's stock Mono is older and slower
than the upstream build, and we hit at least one Mono bug in stock 6.8.

### 2a. Easy path — Ubuntu's mono-complete

```bash
sudo apt install mono-complete
```

> **Don't use `mono-runtime` alone** — it's missing libraries QA40x needs, and
> the app will start and silently fail. Always install the full `mono-complete`
> package.

### 2b. Recommended path — Mono official stable repository

This installs Mono 6.12.x, which has noticeable performance improvements over
the Ubuntu repository's 6.8.

```bash
sudo apt install gnupg ca-certificates
sudo apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 \
  --recv-keys 3FA7E0328081BFF6A14DA29AA6A19B38D3D831EF
echo "deb https://download.mono-project.com/repo/ubuntu stable-focal main" \
  | sudo tee /etc/apt/sources.list.d/mono-official-stable.list
sudo apt update
sudo apt install mono-complete

# Verify
mono -V
```

The `stable-focal` line is correct even on Ubuntu 22.04 / 24.04 — Mono publishes
a single rolling repo that works across recent Ubuntu releases.

## 3. Install libusb

QA40x talks to the analyzer over libusb.

```bash
sudo apt install libusb-1.0-0 libusb-1.0-0-dev
```

## 4. Install Wine (only needed to run the EXE installer)

We only use Wine to extract the installer payload — the application itself runs
under Mono, not Wine.

```bash
sudo dpkg --add-architecture i386
sudo mkdir -pm755 /etc/apt/keyrings
sudo wget -O /etc/apt/keyrings/winehq-archive.key \
  https://dl.winehq.org/wine-builds/winehq.key
sudo wget -NP /etc/apt/sources.list.d/ \
  https://dl.winehq.org/wine-builds/ubuntu/dists/noble/winehq-noble.sources
# Replace 'noble' with your Ubuntu codename if different (jammy, focal, etc.)
sudo apt update
sudo apt install --install-recommends winehq-stable
```

If `apt update` complains about missing files after adding the WineHQ source,
run `sudo apt-get update --fix-missing` and retry the install.

## 5. Run the QA40x installer under Wine

Download `setup_QA40x_X.YYY.exe` from the releases page (link in Prerequisites)
and run it. The current release at the time of writing is 1.222 — adjust the
filename to whatever you downloaded:

```bash
ls ~/Downloads/setup_QA40x_*.exe
wine ~/Downloads/setup_QA40x_1.222.exe
```

**On first Wine run** you may see prompts to install Wine's internal Mono and
Gecko (for .NET / browser support inside Wine). You can either accept them
(Wine downloads ~50 MB and installs) or cancel — both work for our use case
since QA40x runs under system Mono, not Wine's internal Mono. **Click through
the QA40x installer dialogs and accept the defaults** — installation goes into
the standard Windows location inside the Wine prefix.

If the installer window seems to disappear, check:

```bash
ps -ef | grep -i setup_QA40x | grep -v grep
```

If it's still running, the dialog may be hidden behind another window —
Alt+Tab or check the taskbar. If it's not running, re-run the wine command.

## 6. Copy the installed files out of the Wine prefix

The installer puts everything under
`~/.wine/drive_c/Program Files (x86)/QuantAsylum/QA40x/`. Copy it to a regular
home-directory location so we don't keep walking through the Wine prefix:

```bash
mkdir ~/qa403
cp -rv ~/.wine/drive_c/Program\ Files\ \(x86\)/QuantAsylum/QA40x/* ~/qa403/
ls ~/qa403/
```

You should see:

```
Documentation/      QA40x.exe       UserWeighting/       UserWindows/
unins000.dat        unins000.exe
```

`QA40x.exe` is the application. `Documentation/` holds the user manual PDF.
`UserWeighting/` holds RIAA / weighting files. `UserWindows/` holds custom FFT
window source. The `unins000.*` files are the Windows uninstaller — you can
delete them on Linux.

## 7. Run the application with Mono

```bash
cd ~/qa403
mono QA40x.exe
```

The QA40x GUI should open. The lower-left status corner shows whether the
analyzer is connected. **On first run** the status bar will say "Connect the
QA403. See File → Device to change." — open the **File → Devices** submenu and
pick **QA403** (or QA402, depending on your hardware). The app remembers this
selection across launches.

## 8. Fix the libcanberra-gtk-module warning

On first launch you'll likely see in the terminal:

```
Failed to load module "canberra-gtk-module"
```

It's harmless but noisy. Install the module:

```bash
sudo apt install libcanberra-gtk-module
```

## 9. (Optional) Build libgdiplus 6.0.5 to fix a memory leak

Ubuntu's stock `libgdiplus` is version 6.0.4, which has a known leak that caps
GDI+ object acquisitions to roughly 5000 over the lifetime of a process. For
long-running measurement sessions you can replace it with a self-built 6.0.5.

Check what you have:

```bash
strings /usr/lib/libgdiplus.so | grep "6\.0\."
# 6.0.4 -> stock; 6.0.5 -> already patched
```

If you're on 6.0.4 and want 6.0.5, install the build deps, grab the libgdiplus
6.0.5 source tarball from
https://github.com/mono/libgdiplus/releases, then:

```bash
sudo apt install libgif-dev autoconf libtool automake build-essential gettext \
                 libglib2.0-dev libcairo2-dev libtiff-dev libexif-dev

# inside the extracted libgdiplus-6.0.5/ source tree:
./configure
make
sudo make install

# swap the system symlinks
cd /usr/lib
sudo rm libgdiplus.so libgdiplus.so.0
sudo ln -s /usr/local/lib/libgdiplus.so.0.0.0 libgdiplus.so
sudo ln -s /usr/local/lib/libgdiplus.so.0.0.0 libgdiplus.so.0

# verify
strings /usr/lib/libgdiplus.so | grep "6\.0\."
```

This step is optional. Skip it unless you actually run into the leak.

## 10. First-run notes

- Plug in the QA40x **after** the udev reload in step 1. If it was already
  plugged in, unplug and re-plug.
- Watch the USB voltage indicator in QA40x's status bar. Orange or red means
  inadequate USB power and you should swap to a heavier-gauge cable.
- **Do not apply firmware updates to the device from Linux.** QuantAsylum's
  wiki warns the firmware update path is not reliable on Linux. If the app
  prompts you to update firmware, decline. Instead, install the QA40x release
  whose software version matches your device's existing firmware, or do the
  firmware update on a Windows machine.

## 11. Troubleshooting X11 rendering errors (`BadAlloc`, GDI+ GenericError)

Mono's WinForms / `libgdiplus` stack does aggressive offscreen pixmap
allocation for double buffering. On certain X drivers / acceleration methods
this fails with errors like:

```
X11 Error encountered: Error: BadAlloc (insufficient resources for operation)
  Request: 53 (CreatePixmap)
  Control: System.Windows.Forms.SplitContainer

System.Exception: Generic Error [GDI+ status: GenericError]
  at System.Drawing.Graphics.FillRectangle (...)
```

The fix that works on this host is to force the X driver to use the older
**XAA** acceleration method (which has a simpler pixmap manager). This file
already exists at `/etc/X11/xorg.conf` — keep it intact, and copy it to any
new install where you hit the same symptoms:

```bash
sudo tee /etc/X11/xorg.conf > /dev/null <<'EOF'
Section "Device"
    Identifier "My GPU"
    Option "AccelMethod" "XAA"
EndSection
EOF
sudo systemctl restart gdm   # or log out and back in
```

`XAA` is supported by the legacy `intel`, `radeon`, and `nouveau` drivers.
**It is NOT supported by the modern `modesetting` driver** (used by most
fresh Ubuntu installs and inside QEMU/KVM VMs). On those systems the option
is silently ignored, so the BadAlloc returns. If the XAA fix doesn't apply
to your X driver, the next things to try in order are:

1. **Bump kernel SHM limits** — `libgdiplus` allocates pixmaps via the
   X server's MIT-SHM extension; tight default limits cause failures:
   ```bash
   sudo sysctl -w kernel.shmmax=2147483648 kernel.shmall=524288
   ```
   Persist across reboots in `/etc/sysctl.d/99-qa40x.conf`.
2. **Force an X11 session** instead of Wayland — at the GDM login screen,
   click the gear icon and pick "Ubuntu on Xorg". Mono WinForms has X11
   bindings, not Wayland; running under XWayland adds another pixmap
   allocator that can fail.
3. **Build `libgdiplus` 6.0.5** — Section 9 above. The 6.0.5 release fixed
   several pixmap-lifetime bugs.
4. **VMs only** — switch the VM's USB controller from xHCI (USB 3.0) to
   `ich9-ehci1` (USB 2.0) and bump video VRAM. QEMU's xHCI emulation has
   known issues with QA40x's multi-interface USB layout. Even after that,
   Mono+WinForms in software-rendered VM displays remains fragile — the
   tested install path is bare-metal Ubuntu, not virtualized.

## References

- Official Linux/macOS install wiki:
  https://github.com/QuantAsylum/QA40x/wiki/Linux-and-MacOS
- Getting Started:
  https://github.com/QuantAsylum/QA40x/wiki/Getting-Started
- Releases (download installer EXEs here):
  https://github.com/QuantAsylum/QA40x/releases
- Mono official stable repo:
  https://www.mono-project.com/download/stable/
- WineHQ Ubuntu install instructions:
  https://wiki.winehq.org/Ubuntu
