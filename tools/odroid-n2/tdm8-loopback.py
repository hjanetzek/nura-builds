#!/usr/bin/env python3
# 8-channel TDM loopback, long run on the N2 without disk writes in the audio path: the source is
# generated block by block into aplay's stdin, arecord writes to /tmp (RAM) with a 2 s buffer, and
# the comparison regenerates the source block by block. Usage: tdm8-long2.py SECONDS
import subprocess, sys, time, wave, numpy as np
fs, secs, ch = 48000, int(sys.argv[1]), 8
n = fs * secs; B = fs  # 1 s blocks
def block(i0, i1):
    t = np.arange(i0, i1) / fs
    x = np.empty((i1 - i0, ch), np.int32)
    for k in range(ch):
        x[:, k] = (0.9 / (k + 1) * np.sin(2 * np.pi * 500 * (k + 1) * t) * 2**31).astype(np.int32)
        s = 24000 + k * 1000
        a, b = max(s, i0), min(s + 200, i1)
        if a < b:
            x[a - i0:b - i0, k] = (np.arange(a - s, b - s, dtype=np.int64) * (1000003 * (k + 1))).astype(np.int32)
    return x
cap = '/tmp/tdm8-long-cap.wav'
rec = subprocess.Popen(['arecord', '-q', '-D', 'hw:ODROIDN2,3', '-f', 'S32_LE', '-c', '8', '-r', '48000',
                        '-B', '2000000', '-d', str(secs + 8), cap], stderr=subprocess.PIPE, text=True)
time.sleep(1)
play = subprocess.Popen(['aplay', '-q', '-D', 'hw:ODROIDN2,0', '-t', 'raw', '-f', 'S32_LE', '-c', '8',
                         '-r', '48000', '-B', '2000000', '-'], stdin=subprocess.PIPE, stderr=subprocess.PIPE)
for i0 in range(0, n, B):
    play.stdin.write(block(i0, min(i0 + B, n)).tobytes())
play.stdin.close(); perr = play.stderr.read().decode().strip(); play.wait()
_, rerr = rec.communicate()
print('aplay rc', play.returncode, perr, '| arecord rc', rec.returncode, rerr.strip())
w = wave.open(cap); total = w.getnframes()
head = np.frombuffer(w.readframes(5 * fs), np.int32).reshape(-1, ch)
c = np.correlate(head[:, 0].astype(float), block(23000, 25200)[:, 0].astype(float), mode='valid')
off = int(np.argmax(c)) - 23000
print(f'{secs} s, {n} frames x {ch} channels, offset {off}, captured {total} frames')
if off < 0 or total < off + n: raise SystemExit('capture too short or negative offset')
w.setpos(off); diff = np.zeros(ch, np.int64); first = [None] * ch
for i0 in range(0, n, B):
    i1 = min(i0 + B, n)
    y = np.frombuffer(w.readframes(i1 - i0), np.int32).reshape(-1, ch); x = block(i0, i1)
    d = y != x
    for k in range(ch):
        cnt = int(d[:, k].sum()); diff[k] += cnt
        if cnt and first[k] is None: first[k] = i0 + int(np.flatnonzero(d[:, k])[0])
for k in range(ch):
    print(f'ch{k}: {diff[k]} differ' + (f' (first {first[k]})' if diff[k] else ' -> bit-exact'))
