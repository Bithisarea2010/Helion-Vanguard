#!/usr/bin/env python3
"""Helion Vanguard — procedural audio synthesis. All sounds original.
Run with any python that has numpy (Blender's bundled python works)."""
import numpy as np, wave, os, sys

SR = 44100
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "audio")

def write_wav(name, data, sr=SR, music=False):
    d = os.path.join(OUT, "music" if music else "sfx")
    os.makedirs(d, exist_ok=True)
    data = np.clip(data, -1.0, 1.0)
    pcm = (data * 32767).astype(np.int16)
    with wave.open(os.path.join(d, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(pcm.tobytes())
    print("  ", name, round(len(data) / sr, 2), "s")

def t_axis(dur): return np.linspace(0, dur, int(SR * dur), endpoint=False)
def env_exp(dur, k=8.0): return np.exp(-k * t_axis(dur) / dur)
def env_adsr(dur, a=0.01, r=0.3):
    n = int(SR * dur); e = np.ones(n)
    na = min(max(int(SR * a), 1), n)
    nr = min(max(int(SR * r), 1), n)
    e[:na] = np.linspace(0, 1, na)
    e[-nr:] *= np.linspace(1, 0, nr)
    return e
def noise(dur): return np.random.uniform(-1, 1, int(SR * dur))
def sine(f, dur, ph=0.0):
    t = t_axis(dur)
    f = np.asarray(f) if np.ndim(f) else np.full_like(t, f)
    return np.sin(2 * np.pi * np.cumsum(f) / SR + ph)
def saw(f, dur):
    t = t_axis(dur)
    f = np.asarray(f) if np.ndim(f) else np.full_like(t, f)
    ph = np.cumsum(f) / SR
    return 2 * (ph % 1.0) - 1
def square(f, dur): return np.sign(sine(f, dur))
def lowpass(x, alpha):
    y = np.empty_like(x); acc = 0.0
    # vectorized one-pole via lfilter-style recursion (loop ok for short sfx)
    for i in range(len(x)):
        acc += alpha * (x[i] - acc); y[i] = acc
    return y
def lp_fft(x, cutoff):
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    X *= 1.0 / (1.0 + (f / max(cutoff, 20.0)) ** 3)
    return np.fft.irfft(X, len(x))
def hp_fft(x, cutoff):
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    X *= 1.0 / (1.0 + (max(cutoff, 20.0) / np.maximum(f, 1.0)) ** 3)
    return np.fft.irfft(X, len(x))
def bp_fft(x, lo, hi): return hp_fft(lp_fft(x, hi), lo)
def norm(x, g=0.9):
    m = np.max(np.abs(x))
    return x * (g / m) if m > 0 else x
def mix(*parts):
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[:len(p)] += p
    return out
def echo(x, delay_s, fb=0.3, n=3):
    out = np.copy(x); d = int(delay_s * SR)
    pad = np.zeros(len(x) + d * n)
    pad[:len(x)] = x
    for i in range(1, n + 1):
        pad[d * i:d * i + len(x)] += x * (fb ** i)
    return pad

def sat(x, drive=2.2):
    """Analog-style soft clip — fatter, denser sound."""
    return np.tanh(x * drive) / np.tanh(drive)

def sub_thump(f0, dur, k=6):
    """Pitch-dropping sine sub layer."""
    f = np.linspace(f0, f0 * 0.35, int(SR * dur))
    return sine(f, dur) * env_exp(dur, k)

def crackle(dur, density=90.0, lo=1200, hi=7000):
    """Sparse burning/debris crackle impulses."""
    n = int(SR * dur)
    x = np.zeros(n)
    n_imp = int(density * dur)
    idx = np.random.randint(0, max(n - 400, 1), n_imp)
    for i in idx:
        L = np.random.randint(60, 380)
        imp = np.random.uniform(-1, 1, L) * np.exp(-np.linspace(0, 9, L)) * np.random.uniform(0.2, 1.0)
        x[i:i + L] += imp[:len(x[i:i + L])]
    return bp_fft(x, lo, hi)

print("SFX ->", OUT)
rng = np.random.default_rng(7)

# ---------------- weapons (layered: transient + body + harmonic ring + tail)
f = np.linspace(2100, 380, int(SR * 0.16))
las_body = saw(f, 0.16) * env_exp(0.16, 6)
las_ring = sine(f * 1.5, 0.16) * env_exp(0.16, 9) * 0.5
las_click = hp_fft(noise(0.02), 3000) * env_exp(0.02, 14) * 0.8
las_tail = bp_fft(noise(0.16), 700, 4500) * env_exp(0.16, 11) * 0.35
las = mix(np.concatenate([las_click, np.zeros(int(SR * 0.14))]), sat(mix(las_body, las_ring), 2.6), las_tail)
write_wav("laser1", norm(las))
f = np.linspace(2400, 700, int(SR * 0.1))
write_wav("elaser", norm(mix(square(f, 0.1) * env_exp(0.1, 7) * 0.7, bp_fft(noise(0.1), 1200, 6000) * env_exp(0.1, 12) * 0.35)))
f = np.linspace(330, 70, int(SR * 0.3))
pl = sine(f, 0.3) * env_exp(0.3, 5) + sine(f * 2.02, 0.3) * env_exp(0.3, 7) * 0.5
write_wav("plasma", norm(mix(pl, lp_fft(noise(0.3), 900) * env_exp(0.3, 9) * 0.6)))
cn = mix(lp_fft(noise(0.09), 2600) * env_exp(0.09, 9), sine(np.linspace(190, 60, int(SR * 0.09)), 0.09) * env_exp(0.09, 7) * 0.9)
write_wav("cannon", norm(cn))
hc = mix(lp_fft(noise(0.22), 1500) * env_exp(0.22, 7), sine(np.linspace(120, 38, int(SR * 0.22)), 0.22) * env_exp(0.22, 5) * 1.2)
write_wav("heavycannon", norm(hc))
f = np.concatenate([np.linspace(240, 3200, int(SR * 0.22)), np.linspace(3200, 200, int(SR * 0.06))])
coil = sine(f, 0.28) * env_adsr(0.28, 0.02, 0.08)
crack = bp_fft(noise(0.28), 2000, 9000) * np.concatenate([np.zeros(int(SR * 0.2)), env_exp(0.08, 12)])
write_wav("coil", norm(mix(coil * 0.7, crack)))
t = t_axis(0.2)
ion = np.sin(2 * np.pi * (720 + 260 * np.sin(2 * np.pi * 27 * t)) * t) * env_exp(0.2, 6)
write_wav("ion", norm(mix(ion, bp_fft(noise(0.2), 400, 2400) * env_exp(0.2, 8) * 0.3)))
bm = mix(saw(215, 0.5) * 0.5, saw(219, 0.5) * 0.5, sine(430, 0.5) * 0.3) * env_adsr(0.5, 0.04, 0.1)
write_wav("beam", norm(lp_fft(bm, 2600), 0.7))
ln = mix(saw(96, 0.6) * 0.6, saw(97.5, 0.6) * 0.6, sine(192, 0.6) * 0.4,
         bp_fft(noise(0.6), 300, 1200) * 0.25) * env_adsr(0.6, 0.05, 0.12)
write_wav("lance", norm(lp_fft(ln, 1600), 0.75))
et = mix(lp_fft(noise(0.16), 2000) * env_exp(0.16, 8), sine(np.linspace(150, 50, int(SR * 0.16)), 0.16) * env_exp(0.16, 6))
write_wav("eturret", norm(et))

# ---------------- missiles / cm
wh = lp_fft(noise(0.9), 1400)
formant = np.linspace(0.15, 1.0, len(wh)) ** 2
ign = hp_fft(noise(0.06), 1800) * env_exp(0.06, 10)
roar = bp_fft(noise(0.9), 150, 600) * env_adsr(0.9, 0.12, 0.4) * 0.8
dopp = sine(np.linspace(260, 90, int(SR * 0.9)), 0.9) * env_adsr(0.9, 0.1, 0.4) * 0.45
write_wav("missile_launch", norm(sat(mix(np.concatenate([ign, np.zeros(int(SR * 0.84))]),
    wh * formant * env_adsr(0.9, 0.05, 0.3), roar, dopp), 1.8)))
write_wav("flare", norm(mix(bp_fft(noise(0.35), 900, 6000) * env_exp(0.35, 6),
    sine(np.linspace(600, 300, int(SR * 0.1)), 0.1) * env_exp(0.1, 8) * 0.6)))

# ---------------- explosions: transient crack + fireball + sub + crackle + rumble tail
def boom(dur, sub_f, cutoff, name, rumble=1.0):
    crack = hp_fft(noise(0.05), 2500) * env_exp(0.05, 12) * 1.1
    body = lp_fft(noise(dur), cutoff) * env_exp(dur, 5)
    sub = sub_thump(sub_f, dur, 4) * 1.25
    ckl = crackle(dur, 110.0) * env_exp(dur, 6) * 0.5
    tail_d = dur * 1.7 * rumble
    tail = lp_fft(noise(tail_d), 240) * env_adsr(tail_d, dur * 0.3, tail_d * 0.55) * 0.55
    full = mix(np.concatenate([crack, np.zeros(1)]), sat(mix(body, sub), 2.0), ckl, tail)
    write_wav(name, norm(full))
boom(0.7, 95, 1500, "explosion_small", 0.7)
boom(1.2, 75, 1200, "explosion")
boom(2.4, 52, 950, "explosion_big", 1.3)

# ---------------- hits
write_wav("hit_shield", norm(mix(sine(np.linspace(950, 500, int(SR * 0.16)), 0.16) * env_exp(0.16, 8),
    bp_fft(noise(0.16), 700, 3200) * env_exp(0.16, 10) * 0.5)))
# metallic clank: inharmonic ring modes + noise burst + low knock
ring = sum(sine(fq, 0.22) * env_exp(0.22, 7 + i * 3) * a for i, (fq, a) in
           enumerate([(613, 0.5), (947, 0.35), (1521, 0.25), (2340, 0.15)]))
write_wav("hit_armor", norm(sat(mix(bp_fft(noise(0.1), 1800, 7000) * env_exp(0.1, 11),
    ring, sub_thump(180, 0.14, 8) * 0.6), 2.0)))
write_wav("hit_rock", norm(lp_fft(noise(0.18), 700) * env_exp(0.18, 8)))
write_wav("collision", norm(mix(lp_fft(noise(0.5), 500) * env_exp(0.5, 5),
    bp_fft(noise(0.3), 900, 3000) * env_exp(0.3, 7) * 0.6,
    sine(np.linspace(70, 30, int(SR * 0.5)), 0.5) * env_exp(0.5, 4))))

# ---------------- alarms / ui
def beeps(freqs, blen, gap, name, wave_fn=sine, g=0.8):
    parts = []
    for fr in freqs:
        b = wave_fn(fr, blen) * env_adsr(blen, 0.005, 0.03)
        parts.append(b); parts.append(np.zeros(int(SR * gap)))
    write_wav(name, norm(np.concatenate(parts), g))
# avionics: lock = rising dual-chirp; missile alarm = urgent tri-tone sweep
fchirp = np.concatenate([np.full(int(SR*0.09), 740.0), np.full(int(SR*0.26), 1120.0)])
dur_lk = len(fchirp) / SR
lk = mix(sine(fchirp, dur_lk)[:len(fchirp)], sine(fchirp * 2.0, dur_lk)[:len(fchirp)] * 0.3)
env_lk = env_adsr(dur_lk, 0.008, 0.05)
n_lk = min(len(lk), len(env_lk))
write_wav("lock_tone", norm(lk[:n_lk] * env_lk[:n_lk], 0.7))
am_seg = []
for fr in (820, 1040, 1290, 820, 1040, 1290):
    am_seg.append(mix(square(fr, 0.075), sine(fr * 2, 0.075) * 0.25) * env_adsr(0.075, 0.004, 0.02))
    am_seg.append(np.zeros(int(SR * 0.028)))
write_wav("alarm_missile", norm(sat(np.concatenate(am_seg), 1.6), 0.6))
beeps([300, 300], 0.22, 0.1, "alarm_heat", square, 0.5)
beeps([1250], 0.035, 0.01, "ui_click", sine, 0.5)
beeps([900], 0.025, 0.01, "ui_hover", sine, 0.35)
beeps([420, 300], 0.09, 0.03, "ui_deny", square, 0.4)
beeps([600, 900], 0.07, 0.02, "ui_ready")
beeps([1500], 0.05, 0.01, "ui_target")
beeps([2300], 0.03, 0.005, "hitmarker", sine, 0.45)
ping = sine(1150, 0.5) * env_exp(0.5, 6)
write_wav("radar_ping", norm(echo(ping, 0.12, 0.4, 2), 0.5))
sq = bp_fft(noise(0.06), 1500, 5000) * env_adsr(0.06, 0.005, 0.02)
write_wav("radio", norm(np.concatenate([sq, np.zeros(int(SR * 0.03)), sq * 0.7]), 0.4))
beeps([620, 830, 1100], 0.09, 0.02, "objective")
fan = mix(np.concatenate([sine(523, 0.16), sine(659, 0.16), sine(784, 0.3)]) ,
          np.concatenate([sine(262, 0.16), sine(330, 0.16), sine(392, 0.3)]) * 0.5)
write_wav("mission_win", norm(fan * env_adsr(0.62, 0.01, 0.2), 0.7))
fail = mix(saw(np.linspace(220, 110, int(SR * 1.2)), 1.2), sine(np.linspace(110, 55, int(SR * 1.2)), 1.2))
write_wav("mission_fail", norm(lp_fft(fail, 800) * env_adsr(1.2, 0.05, 0.5), 0.6))

# ---------------- engine: multiband rumble + tonal harmonics + turbine whine
el = mix(lp_fft(noise(2.0), 200) * 0.75,
         bp_fft(noise(2.0), 300, 700) * 0.22,
         sine(52, 2.0) * 0.35, sine(104, 2.0) * 0.20, sine(156, 2.0) * 0.10,
         saw(26, 2.0) * 0.14,
         sine(410, 2.0) * 0.045, sine(823, 2.0) * 0.025)
lfo = 1.0 + 0.07 * np.sin(2 * np.pi * 3.1 * t_axis(2.0)) + 0.04 * np.sin(2 * np.pi * 7.7 * t_axis(2.0))
write_wav("engine_loop", norm(sat(el * lfo, 1.6), 0.55))
bo = lp_fft(noise(1.1), 900) * env_adsr(1.1, 0.15, 0.5)
write_wav("boost", norm(mix(bo, sine(np.linspace(60, 160, int(SR * 1.1)), 1.1) * env_adsr(1.1, 0.2, 0.4) * 0.5), 0.7))
write_wav("thruster", norm(lp_fft(noise(0.3), 800) * env_adsr(0.3, 0.04, 0.12), 0.4))

# ---------------- music (32 s loops)
def chord_pad(root_hz, semis, dur, detune=1.007, cutoff=900):
    out = np.zeros(int(SR * dur))
    for s in semis:
        f0 = root_hz * (2 ** (s / 12.0))
        out += saw(f0, dur) * 0.22 + saw(f0 * detune, dur) * 0.22
    return lp_fft(out, cutoff)

def make_menu_music():
    bar = 4.0  # seconds per chord
    prog = [(110.0, [0, 3, 7, 12]), (87.3, [0, 4, 7, 12]),
            (65.4, [0, 7, 12, 16]), (98.0, [0, 4, 7, 11])]
    pads = []
    for root, ch in prog + prog:
        pads.append(chord_pad(root, ch, bar) * env_adsr(bar, 0.8, 1.2))
    pad = np.concatenate(pads)
    # slow sparkle arp
    notes = [440, 523.25, 659.25, 880, 659.25, 523.25]
    arp = np.zeros_like(pad)
    step = int(SR * 1.3333)
    for i in range(0, len(pad) - step, step):
        n = notes[(i // step) % len(notes)]
        seg = sine(n, 0.9) * env_exp(0.9, 5) * 0.12
        arp[i:i + len(seg)] += seg
    swell = 0.8 + 0.2 * np.sin(2 * np.pi * np.arange(len(pad)) / len(pad))
    write_wav("menu", norm((pad * 0.8 + arp) * swell, 0.55), music=True)

def make_combat_music():
    bpm = 100.0
    beat = 60.0 / bpm
    bars = 16
    total = beat * 4 * bars
    n = int(SR * total)
    out = np.zeros(n)
    # kick on 1 & 3, snare-ish noise on 2 & 4
    kick = sine(np.linspace(120, 40, int(SR * 0.18)), 0.18) * env_exp(0.18, 7)
    snare = bp_fft(noise(0.14), 900, 5000) * env_exp(0.14, 9) * 0.5
    hat = hp_fft(noise(0.05), 6000) * env_exp(0.05, 10) * 0.2
    for b in range(int(bars * 4)):
        i = int(b * beat * SR)
        if i + len(kick) < n and b % 2 == 0:
            out[i:i + len(kick)] += kick
        if i + len(snare) < n and b % 4 == 2:
            out[i:i + len(snare)] += snare
        for h8 in range(2):
            ih = i + int(h8 * beat / 2 * SR)
            if ih + len(hat) < n:
                out[ih:ih + len(hat)] += hat
    # driving bass: A minor riff, 8ths
    riff = [55.0, 55.0, 65.4, 55.0, 73.4, 65.4, 55.0, 49.0]
    for b8 in range(int(bars * 8)):
        i = int(b8 * beat / 2 * SR)
        f0 = riff[b8 % 8]
        seg = saw(f0, beat / 2 * 0.9) * env_adsr(beat / 2 * 0.9, 0.01, 0.08) * 0.4
        seg = lp_fft(seg, 700)
        if i + len(seg) < n:
            out[i:i + len(seg)] += seg
    # tense pad
    pad_prog = [(110.0, [0, 3, 7]), (103.8, [0, 3, 7]), (110.0, [0, 3, 7]), (116.5, [0, 3, 6])]
    pads = []
    for root, ch in pad_prog * 4:
        pads.append(chord_pad(root, ch, beat * 4, cutoff=650) * env_adsr(beat * 4, 0.4, 0.6) * 0.5)
    pad = np.concatenate(pads)
    out[:len(pad)] += pad[:n] if len(pad) > n else np.pad(pad, (0, n - len(pad)))
    # arp urgency
    arp_notes = [220, 261.6, 329.6, 261.6]
    for b16 in range(int(bars * 16)):
        i = int(b16 * beat / 4 * SR)
        seg = square(arp_notes[b16 % 4] * 2, beat / 4 * 0.7) * env_exp(beat / 4 * 0.7, 6) * 0.05
        if i + len(seg) < n:
            out[i:i + len(seg)] += seg
    write_wav("combat", norm(out, 0.6), music=True)

make_menu_music()
make_combat_music()
print("ALL AUDIO DONE")
