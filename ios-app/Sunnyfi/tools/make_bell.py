# The opening bell, rendered from the design's Web Audio recipe (New Home iPhone Preview, ring()):
# a clapper 18 times a second for 2.4 s, each strike jumping to 1 and decaying exponentially to 0.3 over 92% of the
# period; after 2.4 s one last strike that dies away to 0.0001 over 1.8 s. Four inharmonic partials of 840 Hz
# (1, 2.76, 5.4, 8.93; amplitudes 1, .45, .2, .08), each doubled 0.3% sharp at half level, /1.6; out gain 0.2;
# then Web Audio's default compressor (threshold -24 dB, knee 30, ratio 12, attack 3 ms, release 250 ms).
import sys, wave, numpy as np
SR = 44100; ring, rel, per = 2.4, 1.8, 1 / 18; t0 = 0.03
N = int(SR * (t0 + ring + rel + 0.1)); t = np.arange(N) / SR
env = np.full(N, 1e-4)
x = t0
while x < t0 + ring - 1e-9:
    a, b = int(round(x * SR)), int(round((x + per) * SR)); d = per * 0.92
    seg = t[a:b] - x
    env[a:b] = np.where(seg < d, 0.3 ** (seg / d), 0.3)          # exponential 1 -> .3, then hold
    x += per
a = int(round((t0 + ring) * SR)); seg = t[a:] - (t0 + ring)
env[a:] = np.where(seg < rel, 1e-4 ** (seg / rel), 1e-4)          # the last strike dies away
osc = np.zeros(N)
for r, amp in [(1, 1), (2.76, .45), (5.4, .2), (8.93, .08)]:
    for j, dt in enumerate([1, 1.003]):
        osc += amp * (0.5 if j else 1) / 1.6 * np.sin(2 * np.pi * 840 * r * dt * (t - t0))
osc[t < t0] = 0
sig = osc * env * 0.2
# Soft-knee compressor on the level (dB), attack/release smoothed.
thr, knee, ratio = -24.0, 30.0, 12.0
lvl = 20 * np.log10(np.abs(sig) + 1e-9)
def gain_db(x):
    lo, hi = thr - knee / 2, thr + knee / 2
    y = np.where(x <= lo, x, np.where(x >= hi, thr + (x - thr) / ratio,
                 x + (1 / ratio - 1) * (x - lo) ** 2 / (2 * knee)))
    return y - x
target = gain_db(lvl)
ga, gr = np.exp(-1 / (0.003 * SR)), np.exp(-1 / (0.25 * SR))
g = np.zeros(N); cur = 0.0
for i in range(N):
    c = ga if target[i] < cur else gr
    cur = c * cur + (1 - c) * target[i]; g[i] = cur
out = sig * 10 ** (g / 20)
out *= 10 ** (-1 / 20) / np.max(np.abs(out))                       # peak at -1 dBFS
# a 5 ms fade at the very end so the file never clicks
f = int(0.005 * SR); out[-f:] *= np.linspace(1, 0, f)
pcm = (out * 32767).astype('<i2')
with wave.open(sys.argv[1], 'wb') as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes(pcm.tobytes())
print(sys.argv[1], round(N / SR, 2), 's')
