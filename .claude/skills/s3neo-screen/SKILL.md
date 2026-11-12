---
name: s3neo-screen
description: Look at the Samsung Galaxy S III Neo's (s3ve3g) screen through the camera pointed at it, and judge what it shows. Use whenever a test needs to know what is on the phone's display (display/panel bring-up, console, boot splash, test patterns, burn-in blanking) instead of asking the user.
---

# The S III Neo's screen, seen by a camera

Another phone with the "Android IP Camera" app (github.com/DigitallyRefined/android-ip-camera)
points at the S III Neo; its snapshot endpoint gives a photo of the screen.

## Take a picture

```sh
tools/s3ve3g-screenshot.sh [NAME]     # prints the path of the scaled copy
```

Then view the printed `*-small.jpg` with the Read tool. The full-size photo is next to it
(`out/s3ve3g/screens/NAME.jpg`) for detail: crop it with python3/PIL before reading if small text
matters. Environment: `CAM` (default `https://192.168.178.58:4444`), `CAM_USER`/`CAM_PASS` when the
app's authentication is on, `SIZE` (default 900).

If it fails:
- "Authentication credentials not properly configured": the app wants a user and password set in
  its settings, or authentication off: ask the user.
- Connection refused or a timeout: the app or the phone with the camera isn't running: ask the user.

Wait a moment after a change before shooting (the panel needs ~100 ms to show a new frame, the
camera's auto-exposure a second or two); take a second picture when the first looks transitional.

## Judge it

Say what is actually visible, not what was expected:
- Panel dark or lit: an AMOLED's black is black, so compare with the bezel and the glass's
  reflections (the reflections are always there; a lit panel shows content behind them).
- Text: read it (console lines, the login prompt, messages written to /dev/tty1 for the test, e.g.
  `echo "marker N" | sudo tee /dev/tty1`): a unique marker string proves the picture is current.
- Test patterns written to the framebuffer: which colours appear where (order of red, green and blue
  bands tells the pixel format), whether white is white, stripes, tearing, shifted or doubled images.
- Brightness and uniformity (dim, fading, purple/green casts are panel or gamma problems).
- Orientation (upside down, mirrored).

For display bring-up, report the result together with the phone's own state (panel power mode in
dmesg, DSI FIFO_STATUS, dsi_isr rate): see docs/samsung-s3ve3g-gpu.md.

The burn-in protection (`s3ve3g-screen-off`, default runlevel) blanks the screen after boot: stop it
(`sudo rc-service s3ve3g-screen-off stop`) before looking, and start it again afterwards.
