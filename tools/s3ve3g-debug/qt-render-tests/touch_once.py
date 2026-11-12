import os, subprocess, sys, time
sys.argv = [sys.argv[0], "0", "/tmp/touch_once"]
exec(open("/tmp/gltest/touch_glitch.py").read().split("for r in range(ROUNDS):")[0])
env = dict(os.environ, XDG_RUNTIME_DIR=RT, WAYLAND_DISPLAY=WL)
subprocess.run(["grim", "/tmp/touch_before.png"], env=env)
down(1225, 420)
for k in range(1, 9): move(1225, 420 - 30 * k); time.sleep(0.03)
time.sleep(0.2); subprocess.run(["grim", "/tmp/touch_during.png"], env=env)
up(); time.sleep(0.3)
subprocess.run(["grim", "/tmp/touch_after.png"], env=env)
ui.close()
