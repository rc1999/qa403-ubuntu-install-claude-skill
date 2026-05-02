# qa403-ubuntu-install-claude-skill

A Claude Code [skill](https://docs.claude.com/en/docs/claude-code/skills) and a
companion install document for getting **QuantAsylum's QA40x audio-analyzer
software** running on Ubuntu Linux. Tested with the **QA403** hardware on
Ubuntu 20.04 (Focal) and 24.04 (Noble) using the official QA40x installers
1.220 and 1.222.

QA40x is a Windows .NET app from QuantAsylum that drives the QA402 / QA403
audio analyzers. It runs cleanly on Linux under Mono — this repo captures
the full install procedure plus the gotchas you only learn the hard way
(udev rules, ModemManager probing, libgdiplus pixmap exhaustion, the X11
`BadAlloc` issue and its `xorg.conf` fix, ...).

## Contents

- **[`scripts/install-qa40x.sh`](scripts/install-qa40x.sh)** — one-shot
  installer. Idempotent (safe to re-run), state-detects what's already in
  place, handles all the apt installs / udev rules / Wine setup. Use this
  if you don't want to step through the install manually.
- **[`INSTALL.md`](INSTALL.md)** — human-readable, paste-and-run install
  guide. Read this if you want to understand each step or run them by hand.
- **[`skills/qa40x-install-ubuntu/SKILL.md`](skills/qa40x-install-ubuntu/SKILL.md)** —
  the Claude Code skill version. When loaded into Claude Code, this lets
  Claude walk you through the install (or a partial reinstall, or
  troubleshoot connection / rendering issues), state-detecting what's
  already in place and only running the missing steps.

## Quick install (one-shot script)

If you don't want to step through INSTALL.md by hand:

```bash
git clone https://github.com/rc1999/qa403-ubuntu-install-claude-skill.git
cd qa403-ubuntu-install-claude-skill

# 1. install dependencies (mono, libusb, wine, udev rules)
./scripts/install-qa40x.sh

# 2. download setup_QA40x_X.YYY.exe from
#    https://github.com/QuantAsylum/QA40x/releases  (current: 1.222)

# 3. re-run the script with the EXE path — it'll wine-install and copy out
./scripts/install-qa40x.sh --exe ~/Downloads/setup_QA40x_1.222.exe

# 4. run it
cd ~/qa403 && mono QA40x.exe
```

Useful flags: `--skip-wine` (use this if you're copying `~/qa403/` from a
Windows machine), `--no-mono-official` (use Ubuntu's stock 6.8.x instead of
adding the Mono official repo), `-y` (skip confirmation prompts). See the
script's `--help` for the full list.

## Installing the skill into Claude Code

This repo is packaged as a Claude Code **plugin**, so the easy path is:

```bash
claude plugin install rc1999/qa403-ubuntu-install-claude-skill
```

(That installs from this GitHub repo. Restart Claude Code and the skill is
live.) After install, the skill loads automatically and will trigger on
prompts like "install QA40x on this machine", "QA403 isn't detected on
Linux", "mono QA40x.exe crashes with BadAlloc", "running QA40x in a VM",
etc.

To uninstall: `claude plugin uninstall qa40x-install-ubuntu`.

### Manual install (if you don't want the plugin wrapper)

The skill itself is just one markdown file. Copy it directly:

```bash
mkdir -p ~/.claude/skills/qa40x-install-ubuntu
curl -fsSL https://raw.githubusercontent.com/rc1999/qa403-ubuntu-install-claude-skill/main/skills/qa40x-install-ubuntu/SKILL.md \
  -o ~/.claude/skills/qa40x-install-ubuntu/SKILL.md
```

Or clone the repo and copy:

```bash
git clone https://github.com/rc1999/qa403-ubuntu-install-claude-skill.git
mkdir -p ~/.claude/skills/qa40x-install-ubuntu
cp qa403-ubuntu-install-claude-skill/skills/qa40x-install-ubuntu/SKILL.md \
   ~/.claude/skills/qa40x-install-ubuntu/
```

Either way, restart Claude Code afterwards.

## Scope

This skill / guide is **strictly the QA40x install** — udev rules, Mono,
libusb, Wine to extract the installer, copy out, `mono QA40x.exe`. It does
not cover:

- Using QA40x as an ALSA playback device (separate work, see ALSA `qa40x_plug` configs).
- Running on macOS (the same Mono recipe ports, but isn't tested here).
- The newer "QA40x V2" branch, which uses .NET 8 instead of Mono. If the
  installer you downloaded targets V2, reuse this guide's udev / libusb /
  hardware sections and replace the Mono section with `dotnet-runtime-8.0`.

## Status

- **Validated end-to-end** on bare-metal Ubuntu 20.04 (the maintainer's
  primary install) and through `mono QA40x.exe` GUI launch on a clean
  Ubuntu 24.04 KVM VM.
- **VM-specific gotcha**: the QA40x app's WinForms paint loop is fragile
  under software-rendered X (no GPU) and the `modesetting` driver. The XAA
  workaround that fixes it on bare metal is silently ignored by
  `modesetting`. See the troubleshooting sections in `INSTALL.md` and
  `SKILL.md` for partial workarounds (`kernel.shmmax`, X11 vs Wayland,
  `libgdiplus` 6.0.5). Bare-metal install is recommended for serious use.

## License

MIT — see [LICENSE](LICENSE).

## Contributing

Issues and PRs welcome. If you hit a new failure mode, add it to the
"Common failure modes & fixes" table in `SKILL.md` (and the matching
section in `INSTALL.md`) along with the cause and the fix. Keep both
files in sync.

## References

- [QuantAsylum QA40x official Linux/macOS wiki](https://github.com/QuantAsylum/QA40x/wiki/Linux-and-MacOS)
- [QuantAsylum QA40x releases (installer EXEs)](https://github.com/QuantAsylum/QA40x/releases)
- [Getting Started wiki](https://github.com/QuantAsylum/QA40x/wiki/Getting-Started)
- [Claude Code Skills documentation](https://docs.claude.com/en/docs/claude-code/skills)
