# zynthian on Nura: test images for zynthian kits (Raspberry Pi 4)

[Nura](https://github.com/hjanetzek/nura-builds) (postmarketOS) with zynthian's Qt Quick UI.

| Image | Kit |
|---|---|
| `zynthian-zynthian-rpi4-V4.img.zst` | V4 (ZynScreen 3.5" SPI panel) |
| `zynthian-zynthian-rpi4-V5.img.zst` | V5 on a Pi 4 (DSI 800x480) |

Other kits: change `kit=` in `zynthian.txt` on the boot partition (`zynthian-kit list`). V5.1 /
Pi 5: not supported yet.

The first boot sets up the kit and reboots once. SSH: `user` / `raspberry`, host `nura-zynthian`.
`zynthian-kit` shows or switches the kit; logs: `journalctl -b -u zynthian-kit-boot`, `-u tinydm`.

Known gaps:
- V4: the Qt UI runs on the SPI panel without a compositor (Qt linuxfb): no plugin windows; the
  layout isn't adapted to 480x320 yet.
- V5: not tested on hardware yet.
- Not every engine/plugin of ZynthianOS is packaged. PREEMPT_RT kernel packaged, not the default.

Reports (audio, encoders/switches, touch, chains, CPU/xruns):
<https://github.com/hjanetzek/nura-builds/issues>
