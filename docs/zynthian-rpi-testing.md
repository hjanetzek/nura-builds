# zynthian on Nura: test images for zynthian kits (Raspberry Pi 4)

Images of [Nura](https://github.com/hjanetzek/nura-builds) (postmarketOS) with zynthian's new Qt
Quick UI, for zynthian kits. Write one to a **second SD card**: your ZynthianOS card stays as it
is, and you switch back by swapping the card.

| Image | For |
|---|---|
| `zynthian-zynthian-rpi4-V4.img.zst` | zynthian V4 (Raspberry Pi 4, ZynScreen 3.5" SPI panel, HifiBerry DAC+ADC Pro) |
| `zynthian-zynthian-rpi4-V5.img.zst` | zynthian V5 on a Raspberry Pi 4 (DSI panel 800x480) |

The V5.1 (Raspberry Pi 5) isn't supported yet (the image will probably boot on a Pi 5, untested).
Other kits: use either image and change the `kit=` line in `zynthian.txt` on the card's FAT
partition (`zynthian-kit list` on the device shows the kits zynthian-sys knows).

## Install

1. Download the image for your kit and write it to an SD card (8 GB or more):
   - Raspberry Pi Imager: "Use custom", pick the `.img.zst` file;
   - or on Linux: `zstd -d < zynthian-zynthian-rpi4-V4.img.zst | sudo dd of=/dev/sdX bs=4M status=progress`
     (`/dev/sdX`: your SD card, check with `lsblk`).
2. Put the card in the kit, connect Ethernet if you want to log in, power on.
3. The first boot sets the kit up (sound card, display, encoders and switches) and **reboots once
   by itself**; then zynthian starts. Give it a few minutes.

## Logging in

SSH is on: user `user`, password `raspberry` (as on ZynthianOS; change it with `passwd`). The host name is
`nura-zynthian`; find the address in your router, or `ssh user@nura-zynthian.local` if your
network resolves it. `sudo` works without a password for this user (zynthian needs root for some
settings; a first step).

Useful on the device:
- `zynthian-kit` shows the kit, `zynthian-kit V5` switches it (then reboot)
- `kiosk-session list` shows the kiosk session (zynthian-fb on SPI panels, zynthian on HDMI/DSI)
- `journalctl -b -u tinydm` the kiosk's log, `journalctl -b -u zynthian-kit-boot` the kit setup

## What works, what doesn't yet

Works on the V4 kit (tested 2026-11-10, before these images): booting with Alpine's Raspberry Pi
kernel, the HifiBerry DAC+ADC, the MCP23017 encoders and switches, ADS7846 touch, the Qt UI on the
SPI panel.

Known gaps:
- **V4's SPI panel**: the Qt UI runs there without a compositor (Qt's framebuffer backend): no
  native plugin windows on the V4. The layout isn't adapted to 480x320 yet.
- **V5**: first images, not tested on a V5 yet.
- Plugin set: the plugins of zynthian's Nura port; not everything of ZynthianOS is packaged.
- The real-time kernel (PREEMPT_RT) is packaged but not the default yet.

## Please check and report

- [ ] Boots, sets the kit up, reboots once, zynthian appears on the panel
- [ ] Audio out (headphones / line out) and in
- [ ] Encoders turn, switches (short, bold, long press) do what they do on ZynthianOS
- [ ] Touch hits where you tap
- [ ] A chain with an LV2 synth plays from a MIDI keyboard (USB MIDI)
- [ ] CPU load and xruns with a few chains (the status bar, or `top`)

Bugs and results: <https://github.com/hjanetzek/nura-builds/issues> (kit, image file name, what
you did, what happened; `journalctl -b > log.txt` helps).
