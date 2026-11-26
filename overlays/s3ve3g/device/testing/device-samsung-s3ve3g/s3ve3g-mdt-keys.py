#!/usr/bin/python3
# The Samsung Galaxy S III Neo's keys relayed to MicroDexed-touch's control port (UDP 127.0.0.1:5000,
# one command per datagram), for the headless MDT session (s3ve3g-mdt starts it next to MDT).
# Installed as /usr/bin/s3ve3g-mdt-keys by device-samsung-s3ve3g. Reads the keys' evdev devices
# without grabbing them (the user is in the input group); the power key stays s3ve3g-powerkey's.
#
#   volume up / down (and their autorepeat)   right encoder +1 / -1   inject enc r 1 / -1
#   home, short                               right encoder push       inject push r   (enter)
#   home, held 0.6 s                          left encoder push        inject push l   (back)
#   back (touch key)                          left encoder push        inject push l   (back)
#   menu (touch key), short                   S1 (main menu)           inject s 1
#   menu, held 0.6 s                          sequencer start/stop     inject push l long
#
# A native evdev input in MDT's Linux host can replace this later.
import os, select, socket, struct, sys, time

PORT = ("127.0.0.1", int(os.environ.get("MDT_CONTROL_PORT", "5000")))
LONG = 0.6
EV_KEY = 1
KEY_VOLUMEDOWN, KEY_VOLUMEUP, KEY_MENU, KEY_BACK, KEY_HOMEPAGE = 114, 115, 139, 158, 172
DEVICES = ("GPIO Buttons", "tm2-touchkey")
# struct input_event: struct timeval (two longs: 8 bytes on armv7, 16 on 64-bit), u16 type,
# u16 code, s32 value
EVENT = struct.Struct("llHHi")

# key: (short command, long command or None)
PRESS = {
    KEY_HOMEPAGE: ("inject push r", "inject push l"),
    KEY_MENU: ("inject s 1", "inject push l long"),
    KEY_BACK: ("inject push l", None),
}
REPEAT = {KEY_VOLUMEUP: "inject enc r 1", KEY_VOLUMEDOWN: "inject enc r -1"}

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)


def send(cmd):
    try:
        sock.sendto(cmd.encode(), PORT)
    except OSError as e:  # MDT not listening (yet): the key is lost, nothing else
        print(f"{cmd}: {e}", file=sys.stderr)


def open_devices():
    fds = {}
    for ev in sorted(os.listdir("/sys/class/input")):
        if not ev.startswith("event"):
            continue
        try:
            with open(f"/sys/class/input/{ev}/device/name") as f:
                name = f.read().strip()
        except OSError:
            continue
        if name in DEVICES:
            fds[os.open(f"/dev/input/{ev}", os.O_RDONLY)] = name
    return fds


def main():
    fds = open_devices()
    if not fds:
        sys.exit("no key devices (" + ", ".join(DEVICES) + ")")
    print("keys from " + ", ".join(fds.values()), file=sys.stderr)
    # key with a long command: its press time, None once the long command was sent (then dropped
    # at its release without the short one)
    held = {}
    while True:
        now = time.monotonic()
        due = [t + LONG for k, t in held.items() if t is not None]
        timeout = max(0.0, min(due) - now) if due else None
        ready, _, _ = select.select(list(fds), [], [], timeout)
        now = time.monotonic()
        for k, t in list(held.items()):
            if t is not None and now - t >= LONG:  # held: the long command, nothing on release
                send(PRESS[k][1])
                held[k] = None
        for fd in ready:
            data = os.read(fd, EVENT.size * 64)
            for i in range(0, len(data) - EVENT.size + 1, EVENT.size):
                _, _, typ, code, value = EVENT.unpack_from(data, i)
                if typ != EV_KEY:
                    continue
                if code in REPEAT and value in (1, 2):
                    send(REPEAT[code])
                elif code in PRESS and value == 1:
                    if PRESS[code][1]:
                        held[code] = now
                    else:
                        send(PRESS[code][0])
                elif code in PRESS and value == 0 and code in held:
                    if held.pop(code) is not None:
                        send(PRESS[code][0])


if __name__ == "__main__":
    main()
