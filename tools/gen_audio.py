#!/usr/bin/env python3
"""Helion Vanguard — procedural audio synthesis. All sounds original.

Run with any python that has numpy. The system python here does not, but
Blender's bundled interpreter does:

    BLENDER="/Applications/.../Blender.app/Contents/MacOS/Blender"
    "$BLENDER" --background --python tools/gen_audio.py

Design notes for whoever tunes this next:

* Everything is layered as transient / body / sub / tail. A sound that is only
  a body reads as a synth patch; the transient is what makes it feel like an
  event, and the tail is what gives it a size.
* Reverb is convolution against a synthesised decaying-noise impulse. Space has
  no reverb, but the player is inside a hull, and without a tail every explosion
  sounded like it happened in an anechoic chamber two metres away.
* 3D sounds MUST stay mono — AudioStreamPlayer3D pans them itself. Only the
  music is stereo.
* Looping sounds (engine_loop) are wrapped through seamless(), which crossfades
  the tail into the head. Noise layers never line up at a loop boundary, so
  without it the engine ticks once per cycle.
"""
import numpy as np, wave, os

SR = 44100
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "audio")
rng = np.random.default_rng(7)


def tail_trim(x, max_dur, fade=0.07, floor_db=-62.0):
    """Cut a reverb tail once it is inaudible, or at max_dur, then fade the cut.

    Convolution pads every one-shot out to the length of the impulse response:
    without this a 0.2 s laser ships as a 2.5 s file that is 90% silence, and
    a big explosion holds one of the 32 positional voices for twelve seconds.
    """
    n_max = int(SR * max_dur)
    x = np.array(x[..., :n_max], dtype=np.float64, copy=True)
    mag = np.abs(x) if x.ndim == 1 else np.max(np.abs(x), axis=0)
    peak = np.max(mag) + 1e-12
    idx = np.where(mag > peak * (10 ** (floor_db / 20.0)))[0]
    if len(idx):
        x = x[..., :min(x.shape[-1], idx[-1] + int(SR * fade))]
    nf = min(int(SR * fade), x.shape[-1])
    if nf > 1:
        x[..., -nf:] *= np.linspace(1, 0, nf)
    return x


DEFAULT_SFX_MAX = 2.2   # only explosions and the engine loop need longer


def write_wav(name, data, sr=SR, music=False, max_dur="auto"):
    d = os.path.join(OUT, "music" if music else "sfx")
    os.makedirs(d, exist_ok=True)
    data = np.asarray(data, dtype=np.float64)
    if max_dur == "auto":
        max_dur = None if music else DEFAULT_SFX_MAX
    if max_dur is not None:
        data = tail_trim(data, max_dur)
    if data.ndim == 1:
        nch, inter = 1, data
    else:                                  # (2, n) -> interleaved
        nch, inter = data.shape[0], data.T.reshape(-1)
    inter = np.clip(inter, -1.0, 1.0)
    pcm = (inter * 32767).astype(np.int16)
    with wave.open(os.path.join(d, name + ".wav"), "wb") as w:
        w.setnchannels(nch)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(pcm.tobytes())
    print("  ", name, round(len(inter) / nch / sr, 2), "s", "stereo" if nch == 2 else "")


# ------------------------------------------------------------------ generators
def t_axis(dur): return np.linspace(0, dur, int(SR * dur), endpoint=False)
def env_exp(dur, k=8.0): return np.exp(-k * t_axis(dur) / dur)


def env_adsr(dur, a=0.01, r=0.3):
    n = int(SR * dur); e = np.ones(n)
    na = min(max(int(SR * a), 1), n)
    nr = min(max(int(SR * r), 1), n)
    e[:na] = np.linspace(0, 1, na)
    e[-nr:] *= np.linspace(1, 0, nr)
    return e


def noise(dur): return rng.uniform(-1, 1, int(SR * dur))


def sine(f, dur, ph=0.0):
    t = t_axis(dur)
    f = np.asarray(f) if np.ndim(f) else np.full_like(t, f)
    return np.sin(2 * np.pi * np.cumsum(f) / SR + ph)


def saw(f, dur):
    t = t_axis(dur)
    f = np.asarray(f) if np.ndim(f) else np.full_like(t, f)
    return 2 * ((np.cumsum(f) / SR) % 1.0) - 1


def square(f, dur): return np.sign(sine(f, dur))


def sweep(f0, f1, dur, curve=1.0):
    """Frequency ramp; curve > 1 spends longer near f0."""
    x = np.linspace(0, 1, int(SR * dur)) ** curve
    return f0 + (f1 - f0) * x


# ------------------------------------------------------------------ filters
def lp_fft(x, cutoff, order=3):
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    X *= 1.0 / (1.0 + (f / max(cutoff, 20.0)) ** order)
    return np.fft.irfft(X, len(x))


def hp_fft(x, cutoff, order=3):
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    X *= 1.0 / (1.0 + (max(cutoff, 20.0) / np.maximum(f, 1.0)) ** order)
    return np.fft.irfft(X, len(x))


def bp_fft(x, lo, hi): return hp_fft(lp_fft(x, hi), lo)


def resonate(x, freq, q=12.0, gain=1.0):
    """Narrow resonant peak — the cheapest way to give noise a pitch and a body."""
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    bw = max(freq / q, 1.0)
    X *= 1.0 + gain / (1.0 + ((f - freq) / bw) ** 2)
    return np.fft.irfft(X, len(x))


def fft_convolve(x, h):
    n = len(x) + len(h) - 1
    N = 1 << (n - 1).bit_length()
    return np.fft.irfft(np.fft.rfft(x, N) * np.fft.rfft(h, N), N)[:n]


def reverb_ir(dur=2.2, rt60=1.5, lo=160, hi=6500, pre=0.011, seed=11):
    """Exponentially decaying band-limited noise, thinned at the front so it
    diffuses in rather than starting as an audible noise burst."""
    r = np.random.default_rng(seed)
    n = int(SR * dur)
    t = np.arange(n) / SR
    env = np.exp(-6.9078 * t / rt60)
    dens = np.clip(t / 0.05, 0.04, 1.0)
    h = bp_fft(r.uniform(-1, 1, n) * env * dens, lo, hi)
    h /= (np.max(np.abs(h)) + 1e-9)
    return np.concatenate([np.zeros(int(SR * pre)), h])


def reverb(x, mix=0.3, **kw):
    h = reverb_ir(**kw)
    wet = fft_convolve(x, h)
    peak_x = np.max(np.abs(x)) + 1e-9
    wet *= peak_x / (np.max(np.abs(wet)) + 1e-9)
    out = np.zeros(len(wet))
    out[:len(x)] += x
    return out * (1.0 - mix) + wet * mix


# ------------------------------------------------------------------ shaping
def sat(x, drive=2.2):
    """Analog-style soft clip — fatter, denser, and it glues layers together."""
    return np.tanh(x * drive) / np.tanh(drive)


def norm(x, g=0.9):
    m = np.max(np.abs(x))
    return x * (g / m) if m > 0 else x


def mix(*parts):
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[:len(p)] += p
    return out


def delay(x, secs, amount=1.0):
    """x shifted later by secs, zero-padded — for layering, not echo."""
    d = int(secs * SR)
    out = np.zeros(len(x) + d)
    out[d:] += x * amount
    return out


def echo(x, delay_s, fb=0.3, n=3):
    d = int(delay_s * SR)
    pad = np.zeros(len(x) + d * n)
    pad[:len(x)] = x
    for i in range(1, n + 1):
        pad[d * i:d * i + len(x)] += x * (fb ** i)
    return pad


def sub_thump(f0, dur, k=6, f_end=0.32):
    """Pitch-dropping sine sub layer — the weight under every impact."""
    return sine(sweep(f0, f0 * f_end, dur, 0.6), dur) * env_exp(dur, k)


def crackle(dur, density=90.0, lo=1200, hi=7000):
    """Sparse burning / tearing-debris impulses."""
    n = int(SR * dur)
    x = np.zeros(n)
    for i in rng.integers(0, max(n - 400, 1), int(density * dur)):
        L = int(rng.integers(60, 380))
        imp = rng.uniform(-1, 1, L) * np.exp(-np.linspace(0, 9, L)) * rng.uniform(0.2, 1.0)
        seg = x[i:i + L]
        seg += imp[:len(seg)]
    return bp_fft(x, lo, hi)


def seamless(x, xfade=0.3):
    """Crossfade the tail into the head so the sample loops without a click.
    Works on mono (n,) and stereo (2, n)."""
    n = x.shape[-1]
    m = int(SR * xfade)
    if m * 2 >= n:
        return x
    L = n - m
    out = np.array(x[..., :L], copy=True)
    w = np.linspace(0, 1, m)
    out[..., :m] = x[..., :m] * w + x[..., L:L + m] * (1 - w)
    return out


def haas(x, l_ms=9.0, r_ms=15.0, spread=0.4):
    """Mono -> stereo by unequal short delays. Music only."""
    dl, dr = int(SR * l_ms / 1000), int(SR * r_ms / 1000)
    n = len(x) + max(dl, dr)
    L, R = np.zeros(n), np.zeros(n)
    L[:len(x)] += x
    R[:len(x)] += x
    L[dl:dl + len(x)] += x * spread
    R[dr:dr + len(x)] += x * spread
    return np.vstack([L, R]) / (1.0 + spread)


print("SFX ->", OUT)

# =========================================================== weapons
# Every gun is transient (what the mechanism does) + body (what leaves the
# barrel) + tail (what the hull does about it). The old versions had body only.

# pulse laser: bright zap, descending formant, short metallic ring-out
f = sweep(2600, 340, 0.20, 0.45)
las_body = saw(f, 0.20) * env_exp(0.20, 6)
las_ring = sine(f * 1.5, 0.20) * env_exp(0.20, 9) * 0.45
las_click = hp_fft(noise(0.018), 3500) * env_exp(0.018, 16) * 0.9
las_air = bp_fft(noise(0.26), 800, 5200) * env_exp(0.26, 9) * 0.30
las = mix(las_click, sat(mix(las_body, las_ring), 2.8), las_air)
write_wav("laser1", norm(reverb(las, 0.20, rt60=0.5, hi=8000)))

# enemy laser: harsher, squarer, a semitone-ish lower so friend/foe read apart
f = sweep(2300, 620, 0.13, 0.5)
el = mix(square(f, 0.13) * env_exp(0.13, 7) * 0.65,
         bp_fft(noise(0.16), 1400, 6500) * env_exp(0.16, 11) * 0.40,
         hp_fft(noise(0.012), 4000) * env_exp(0.012, 18) * 0.7)
write_wav("elaser", norm(reverb(sat(el, 2.0), 0.16, rt60=0.4)))

# plasma: heavy wet glob, resonant, with a slow wobbling tail
f = sweep(360, 62, 0.40, 0.7)
pl = mix(sine(f, 0.40) * env_exp(0.40, 5),
         sine(f * 2.02, 0.40) * env_exp(0.40, 7) * 0.5,
         sine(f * 3.01, 0.40) * env_exp(0.40, 9) * 0.22)
pl = mix(pl, resonate(lp_fft(noise(0.40), 1100), 240, 8, 3.0) * env_exp(0.40, 7) * 0.7)
write_wav("plasma", norm(reverb(sat(pl, 1.8), 0.24, rt60=0.9, hi=4000)))

# autocannon: mechanical bolt, report, brass rattle
cn = mix(lp_fft(noise(0.10), 2800) * env_exp(0.10, 10),
         sub_thump(210, 0.11, 8) * 0.95,
         hp_fft(noise(0.008), 5000) * env_exp(0.008, 20) * 0.6,
         delay(bp_fft(noise(0.09), 2600, 9000) * env_exp(0.09, 13) * 0.22, 0.035))
write_wav("cannon", norm(reverb(sat(cn, 2.4), 0.18, rt60=0.45)))

# heavy cannon: same idea, an octave down and twice as long
hc = mix(lp_fft(noise(0.26), 1500) * env_exp(0.26, 6),
         sub_thump(128, 0.30, 4.5) * 1.35,
         hp_fft(noise(0.012), 3500) * env_exp(0.012, 16) * 0.7,
         resonate(lp_fft(noise(0.26), 900), 150, 10, 2.5) * env_exp(0.26, 7) * 0.5)
write_wav("heavycannon", norm(reverb(sat(hc, 2.0), 0.28, rt60=1.1, hi=3500)))

# coil gun: audible capacitor charge, then a hard electrical crack
chg = sine(sweep(220, 3400, 0.24, 1.8), 0.24) * env_adsr(0.24, 0.03, 0.05) * 0.55
chg += sine(sweep(440, 6800, 0.24, 1.8), 0.24) * env_adsr(0.24, 0.03, 0.05) * 0.18
crk = delay(mix(hp_fft(noise(0.10), 2200) * env_exp(0.10, 13),
                sub_thump(160, 0.12, 9) * 0.8), 0.235)
write_wav("coil", norm(reverb(sat(mix(chg, crk), 2.2), 0.22, rt60=0.7)))

# ion: amplitude- and frequency-modulated buzz
t = t_axis(0.26)
ion = np.sin(2 * np.pi * (700 + 300 * np.sin(2 * np.pi * 31 * t)) * t) * env_exp(0.26, 6)
ion *= 0.75 + 0.25 * np.sin(2 * np.pi * 84 * t)
write_wav("ion", norm(reverb(mix(sat(ion, 1.7),
    bp_fft(noise(0.26), 500, 3000) * env_exp(0.26, 8) * 0.3), 0.2, rt60=0.6)))

# beam / lance: sustained, retriggered while the trigger is held, so they must
# start and end quietly or the restarts click
bm = mix(saw(214, 0.55) * 0.5, saw(219.5, 0.55) * 0.5, sine(428, 0.55) * 0.28,
         bp_fft(noise(0.55), 900, 4200) * 0.16) * env_adsr(0.55, 0.05, 0.14)
write_wav("beam", norm(reverb(lp_fft(sat(bm, 1.5), 2800), 0.2, rt60=0.7), 0.7))
ln = mix(saw(95, 0.7) * 0.55, saw(96.6, 0.7) * 0.55, sine(190, 0.7) * 0.38,
         sine(285, 0.7) * 0.16,
         bp_fft(noise(0.7), 260, 1300) * 0.22) * env_adsr(0.7, 0.06, 0.16)
write_wav("lance", norm(reverb(lp_fft(sat(ln, 1.6), 1700), 0.26, rt60=1.2, hi=2600), 0.75))

# enemy turret: drier and flatter than the player's guns, on purpose
et = mix(lp_fft(noise(0.18), 2100) * env_exp(0.18, 8),
         sub_thump(165, 0.18, 6) * 0.9,
         hp_fft(noise(0.01), 4200) * env_exp(0.01, 18) * 0.5)
write_wav("eturret", norm(reverb(sat(et, 1.9), 0.14, rt60=0.4)))

# =========================================================== missiles / cm
# Launch reads in three beats: igniter crack, pressurised release, motor spool.
DUR_ML = 1.7
ign = hp_fft(noise(0.05), 2000) * env_exp(0.05, 12) * 1.2
release = lp_fft(noise(DUR_ML), 1600) * (np.linspace(0.1, 1.0, int(SR * DUR_ML)) ** 2)
release *= env_adsr(DUR_ML, 0.04, 0.55) * 0.85
motor = bp_fft(noise(DUR_ML), 130, 700) * env_adsr(DUR_ML, 0.10, 0.5)
motor = resonate(motor, 190, 7, 2.2) * 0.9
# receding pitch: the round is leaving, and the ear reads that as launch
dopp = sine(sweep(300, 78, DUR_ML, 0.55), DUR_ML) * env_adsr(DUR_ML, 0.08, 0.5) * 0.4
rumble = lp_fft(noise(DUR_ML), 190) * env_adsr(DUR_ML, 0.15, 0.6) * 0.55
write_wav("missile_launch", norm(reverb(
    sat(mix(ign, release, motor, dopp, rumble), 1.9), 0.26, rt60=1.3, hi=4500)))

# countermeasure flare: pyrotechnic hiss with a bright ignition pop
write_wav("flare", norm(reverb(mix(
    bp_fft(noise(0.5), 1100, 8000) * env_exp(0.5, 5),
    hp_fft(noise(0.02), 3000) * env_exp(0.02, 14) * 0.8,
    sine(sweep(700, 260, 0.14, 0.6), 0.14) * env_exp(0.14, 8) * 0.5), 0.2, rt60=0.7)))

# =========================================================== explosions
def boom(dur, sub_f, cutoff, name, rt60, rumble=1.0, g=0.94, cap=3.0):
    """Shock crack -> fireball body -> sub -> debris crackle -> long tail.

    The bands get separate envelopes: highs die in ~100 ms, mids over the body
    length, the sub rings on underneath. Enveloping the whole thing with one
    curve (the previous version) is what made every size sound the same.
    """
    crack = hp_fft(noise(0.06), 2200) * env_exp(0.06, 11) * 1.25
    body_hi = bp_fft(noise(dur), 900, cutoff * 3.0) * env_exp(dur, 11) * 0.55
    body_mid = bp_fft(noise(dur), 180, cutoff) * env_exp(dur, 4.5)
    sub = sub_thump(sub_f, dur * 1.15, 3.4) * 1.45
    ckl = crackle(dur * 1.6, 130.0) * env_exp(dur * 1.6, 4.5) * 0.55
    tail_d = dur * 2.0 * rumble
    tail = lp_fft(noise(tail_d), 210) * env_adsr(tail_d, dur * 0.25, tail_d * 0.6) * 0.6
    full = mix(crack, sat(mix(body_hi, body_mid, sub), 2.1), ckl, tail)
    write_wav(name, norm(reverb(full, 0.34, rt60=rt60, hi=3200, dur=rt60 * 1.5), g),
              max_dur=cap)

boom(0.85, 105, 1400, "explosion_small", 1.1, 0.8, cap=2.0)
boom(1.5, 78, 1150, "explosion", 1.9, cap=3.2)
boom(2.8, 48, 900, "explosion_big", 3.2, 1.4, cap=5.0)

# =========================================================== hits
# shield: energetic ping over a bright wash, tuned to sit above the gun sounds
write_wav("hit_shield", norm(reverb(mix(
    sine(sweep(1050, 470, 0.20, 0.5), 0.20) * env_exp(0.20, 8),
    sine(sweep(1575, 705, 0.20, 0.5), 0.20) * env_exp(0.20, 11) * 0.35,
    bp_fft(noise(0.22), 800, 3600) * env_exp(0.22, 10) * 0.45), 0.26, rt60=0.8)))

# armour: inharmonic bell modes are what make metal sound like metal
ring = sum(sine(fq, 0.30) * env_exp(0.30, 6 + i * 2.5) * a for i, (fq, a) in
           enumerate([(613, 0.5), (947, 0.35), (1521, 0.25), (2340, 0.16), (3877, 0.09)]))
write_wav("hit_armor", norm(reverb(sat(mix(
    bp_fft(noise(0.12), 1800, 8000) * env_exp(0.12, 12),
    ring, sub_thump(175, 0.18, 7) * 0.7), 2.1), 0.24, rt60=0.9)))

# rock: dull, dry, no ring at all — the contrast with hit_armor is the point
write_wav("hit_rock", norm(reverb(mix(
    lp_fft(noise(0.22), 620) * env_exp(0.22, 8),
    sub_thump(120, 0.2, 9) * 0.6), 0.14, rt60=0.5, hi=1800)))

# hull collision: groaning impact plus stressed metal
write_wav("collision", norm(reverb(sat(mix(
    lp_fft(noise(0.6), 460) * env_exp(0.6, 4.5),
    bp_fft(noise(0.35), 800, 3000) * env_exp(0.35, 7) * 0.55,
    sub_thump(78, 0.7, 3.2) * 1.2,
    resonate(noise(0.5), 320, 14, 4.0) * env_exp(0.5, 8) * 0.3), 1.9), 0.3, rt60=1.4)))

# =========================================================== alarms / UI
def beeps(freqs, blen, gap, name, wave_fn=sine, g=0.8, rev=0.0):
    parts = []
    for fr in freqs:
        parts.append(wave_fn(fr, blen) * env_adsr(blen, 0.005, 0.03))
        parts.append(np.zeros(int(SR * gap)))
    x = np.concatenate(parts)
    if rev > 0.0:
        x = reverb(x, rev, rt60=0.4)
    write_wav(name, norm(x, g))

# lock: two-step rising chirp with a harmonic, so it cuts through combat
fchirp = np.concatenate([np.full(int(SR * 0.09), 760.0), np.full(int(SR * 0.28), 1180.0)])
dur_lk = len(fchirp) / SR
lk = mix(sine(fchirp, dur_lk), sine(fchirp * 2.0, dur_lk) * 0.28,
         sine(fchirp * 3.0, dur_lk) * 0.10)
env_lk = env_adsr(dur_lk, 0.008, 0.05)
n_lk = min(len(lk), len(env_lk))
write_wav("lock_tone", norm(reverb(lk[:n_lk] * env_lk[:n_lk], 0.15, rt60=0.3), 0.72))

# missile warning: urgent tri-tone, deliberately unpleasant
am_seg = []
for fr in (840, 1060, 1320, 840, 1060, 1320):
    am_seg.append(mix(square(fr, 0.072), sine(fr * 2, 0.072) * 0.22,
                      sine(fr * 3, 0.072) * 0.1) * env_adsr(0.072, 0.004, 0.02))
    am_seg.append(np.zeros(int(SR * 0.026)))
write_wav("alarm_missile", norm(sat(np.concatenate(am_seg), 1.7), 0.62))

beeps([300, 300], 0.24, 0.1, "alarm_heat", square, 0.52)
beeps([1250], 0.035, 0.01, "ui_click", sine, 0.5)
beeps([900], 0.025, 0.01, "ui_hover", sine, 0.35)
beeps([420, 300], 0.09, 0.03, "ui_deny", square, 0.42)
beeps([600, 900], 0.07, 0.02, "ui_ready", sine, 0.8, 0.12)
beeps([1500], 0.05, 0.01, "ui_target", sine, 0.8, 0.1)
beeps([2300], 0.03, 0.005, "hitmarker", sine, 0.45)
beeps([620, 830, 1100], 0.09, 0.02, "objective", sine, 0.8, 0.15)

ping = sine(1150, 0.5) * env_exp(0.5, 6)
write_wav("radar_ping", norm(echo(ping, 0.12, 0.4, 2), 0.5))
sq = bp_fft(noise(0.06), 1500, 5000) * env_adsr(0.06, 0.005, 0.02)
write_wav("radio", norm(np.concatenate([sq, np.zeros(int(SR * 0.03)), sq * 0.7]), 0.4))

fan = mix(np.concatenate([sine(523, 0.16), sine(659, 0.16), sine(784, 0.34)]),
          np.concatenate([sine(262, 0.16), sine(330, 0.16), sine(392, 0.34)]) * 0.5,
          np.concatenate([sine(784, 0.16), sine(988, 0.16), sine(1175, 0.34)]) * 0.22)
write_wav("mission_win", norm(reverb(fan * env_adsr(0.66, 0.01, 0.22), 0.3, rt60=1.4), 0.72))
fail = mix(saw(sweep(224, 104, 1.4), 1.4), sine(sweep(112, 52, 1.4), 1.4))
write_wav("mission_fail", norm(reverb(
    lp_fft(fail, 780) * env_adsr(1.4, 0.05, 0.6), 0.3, rt60=1.8, hi=1800), 0.62))

# =========================================================== engine
# 4 s bed, wrapped seamless. Layers: broadband rumble, a resonant duct tone,
# the harmonic stack that gives it a pitch to shift with throttle, and a faint
# turbine whine on top so pitch_scale changes are audible at speed.
ED = 4.0
el = mix(lp_fft(noise(ED), 210) * 0.75,
         bp_fft(noise(ED), 320, 760) * 0.20,
         resonate(lp_fft(noise(ED), 900), 118, 9, 2.0) * 0.28,
         sine(52, ED) * 0.34, sine(104, ED) * 0.19, sine(156, ED) * 0.10,
         saw(26, ED) * 0.13,
         sine(415, ED) * 0.045, sine(830, ED) * 0.022, sine(1245, ED) * 0.010)
te = t_axis(ED)
lfo = (1.0 + 0.07 * np.sin(2 * np.pi * 3.0 * te) + 0.04 * np.sin(2 * np.pi * 7.75 * te)
       + 0.02 * np.sin(2 * np.pi * 0.75 * te))
write_wav("engine_loop", norm(seamless(sat(el * lfo, 1.7), 0.35), 0.58), max_dur=None)

# boost: pressure build, whoosh, receding tail
BD = 1.4
bo = lp_fft(noise(BD), 1000) * env_adsr(BD, 0.14, 0.6)
bo *= 0.5 + 0.5 * np.linspace(0, 1, len(bo)) ** 0.5
write_wav("boost", norm(reverb(sat(mix(
    bo,
    sine(sweep(58, 190, BD, 0.7), BD) * env_adsr(BD, 0.18, 0.5) * 0.55,
    bp_fft(noise(BD), 900, 5000) * env_adsr(BD, 0.1, 0.7) * 0.28), 1.6), 0.24, rt60=1.2), 0.74))

write_wav("thruster", norm(lp_fft(noise(0.34), 850) * env_adsr(0.34, 0.04, 0.14), 0.4))


# =========================================================== 1.2 additions
# Same construction rule as every other sound here: transient (what the
# mechanism does) + body (what leaves it) + tail (what the space does about it).

# --- lightspeed drive -------------------------------------------------------
# Spool: a rising harmonic stack over a broadband charge. The pitch ramp is the
# only cue the pilot has that the ring is nearly ready, so it has to stay
# audible under a full combat mix — hence a harmonic stack, not a single tone.
SD = 1.8
_ramp = np.linspace(0.0, 1.0, int(SR * SD))
sp_h = mix(*[sine(sweep(90 * k, 520 * k, SD, 1.6), SD) * (0.5 / k) for k in (1, 2, 3, 5)])
sp_air = bp_fft(noise(SD), 400, 6000) * _ramp ** 2 * 0.35
sp_tick = crackle(SD, density=26.0, lo=2500, hi=9000) * _ramp ** 3 * 0.5
write_wav("ftl_spool", norm(reverb(sat(mix(sp_h, sp_air, sp_tick), 1.5),
                                   0.26, rt60=1.4), 0.80), max_dur=2.4)

# Breach: the loudest one-shot in the game. Sub impact, ripping downsweep and a
# wide tail, so it reads as something happening to space rather than to a gun.
BR = 1.9
write_wav("ftl_breach", norm(reverb(sat(mix(
    sub_thump(180, BR, k=3, f_end=0.22),
    lp_fft(noise(BR), 3000) * env_adsr(BR, 0.008, 0.9),
    sine(sweep(1800, 60, 0.7, 0.5), 0.7) * env_exp(0.7, 5) * 0.6,
    crackle(0.5, density=140.0, lo=1800, hi=11000) * env_exp(0.5, 7) * 0.5), 1.9),
    0.36, rt60=2.4, hi=3000), 0.95), max_dur=2.6)

# Cruise bed: 4 s, seamless. Two resonant duct tones over filtered rumble with
# slow beating, so it never sits still under a long jump.
CD = 4.0
_tc = t_axis(CD)
cr = mix(lp_fft(noise(CD), 420) * 0.55,
         resonate(noise(CD), 128.0, q=14.0, gain=0.50),
         resonate(noise(CD), 311.0, q=22.0, gain=0.30),
         sine(62.0, CD) * 0.22)
cr = cr * (1.0 + 0.10 * np.sin(2 * np.pi * 0.42 * _tc)
           + 0.06 * np.sin(2 * np.pi * 1.13 * _tc))
write_wav("ftl_cruise", norm(seamless(sat(cr, 1.5), 0.4), 0.55), max_dur=None)

XD = 1.3
write_wav("ftl_exit", norm(reverb(sat(mix(
    lp_fft(noise(XD), 2200) * env_adsr(XD, 0.01, 0.8),
    sine(sweep(420, 70, XD, 0.6), XD) * env_exp(XD, 3.0) * 0.6,
    sub_thump(120, 0.7, k=5)), 1.6), 0.30, rt60=1.6), 0.82), max_dur=2.0)

# --- shield matrix ----------------------------------------------------------
write_wav("shield_down", norm(reverb(sat(mix(
    sine(sweep(900, 120, 0.7, 0.6), 0.7) * env_exp(0.7, 4) * 0.7,
    bp_fft(noise(0.55), 600, 5200) * env_exp(0.55, 6) * 0.5,
    crackle(0.6, density=70.0, lo=900, hi=6000) * env_exp(0.6, 5) * 0.6), 1.7),
    0.30, rt60=1.1), 0.80))

# --- extended arsenal -------------------------------------------------------
# railgun: capacitor snap, then the crack of something leaving at 2.2 km/s
write_wav("railgun", norm(reverb(sat(mix(
    hp_fft(noise(0.02), 3000) * env_exp(0.02, 20),
    sine(sweep(180, 55, 0.35, 0.5), 0.35) * env_exp(0.35, 7) * 0.8,
    bp_fft(noise(0.5), 700, 9000) * env_exp(0.5, 9) * 0.45,
    resonate(noise(0.4), 1400.0, q=18.0, gain=0.35)), 2.3),
    0.24, rt60=0.9, hi=5000), 0.94))

# arc projector: dense crackle over a buzzing carrier
write_wav("arc", norm(reverb(sat(mix(
    crackle(0.30, density=260.0, lo=1500, hi=12000) * env_exp(0.30, 6) * 0.9,
    square(sweep(900, 300, 0.22, 0.5), 0.22) * env_exp(0.22, 9) * 0.35,
    resonate(noise(0.3), 2600.0, q=26.0, gain=0.40)), 2.0),
    0.22, rt60=0.6, hi=9000), 0.86))

# flak: hollow breech thump plus shell rattle
write_wav("flak", norm(reverb(sat(mix(
    sine(sweep(220, 70, 0.26, 0.5), 0.26) * env_exp(0.26, 8) * 0.9,
    lp_fft(noise(0.3), 2600) * env_exp(0.3, 8) * 0.55,
    crackle(0.34, density=110.0, lo=800, hi=5200) * env_exp(0.34, 6) * 0.4), 2.1),
    0.26, rt60=0.8, hi=4000), 0.90))

# phase disruptor: two slightly detuned sweeps beating against each other, the
# cheapest way to make something sound like it is not quite in this space
write_wav("phase", norm(reverb(mix(
    sine(sweep(1500, 480, 0.24, 0.6), 0.24) * env_exp(0.24, 7) * 0.5,
    sine(sweep(1512, 486, 0.24, 0.6), 0.24) * env_exp(0.24, 7) * 0.5,
    hp_fft(noise(0.2), 5000) * env_exp(0.2, 12) * 0.3),
    0.30, rt60=0.9, hi=11000), 0.80))

# scatter repeater: short and dry, because it fires 22 times a second
write_wav("repeater", norm(reverb(sat(mix(
    hp_fft(noise(0.012), 2600) * env_exp(0.012, 18) * 0.9,
    sine(sweep(760, 220, 0.07, 0.5), 0.07) * env_exp(0.07, 12) * 0.6,
    bp_fft(noise(0.09), 900, 6000) * env_exp(0.09, 12) * 0.3), 2.2),
    0.12, rt60=0.3), 0.82))

# singularity lance: a hum that RISES, so holding the trigger sounds like charge
SG = 0.9
sg = mix(sine(sweep(70, 130, SG, 0.8), SG) * 0.6,
         saw(sweep(140, 260, SG, 0.8), SG) * 0.25,
         resonate(noise(SG), 520.0, q=30.0, gain=0.30)) * env_adsr(SG, 0.12, 0.3)
write_wav("singularity", norm(reverb(lp_fft(sat(sg, 1.5), 2400),
                                     0.30, rt60=1.3, hi=3000), 0.80))

# EMP: everything electrical in a 220 m bubble failing at once
write_wav("emp", norm(reverb(sat(mix(
    sine(sweep(2200, 90, 0.45, 0.7), 0.45) * env_exp(0.45, 5) * 0.7,
    crackle(0.7, density=180.0, lo=700, hi=9000) * env_exp(0.7, 4) * 0.7,
    sub_thump(90, 0.6, k=5) * 0.8), 1.8),
    0.34, rt60=1.6, hi=6000), 0.92), max_dur=2.4)


# =========================================================== music
def chord_pad(root_hz, semis, dur, detune=1.007, cutoff=900):
    out = np.zeros(int(SR * dur))
    for s in semis:
        f0 = root_hz * (2 ** (s / 12.0))
        out += saw(f0, dur) * 0.22 + saw(f0 * detune, dur) * 0.22
    return lp_fft(out, cutoff)


def make_menu_music():
    bar = 4.0
    prog = [(110.0, [0, 3, 7, 12]), (87.3, [0, 4, 7, 12]),
            (65.4, [0, 7, 12, 16]), (98.0, [0, 4, 7, 11])]
    pads = [chord_pad(root, ch, bar) * env_adsr(bar, 0.8, 1.2) for root, ch in prog + prog]
    pad = np.concatenate(pads)
    notes = [440, 523.25, 659.25, 880, 659.25, 523.25]
    arp = np.zeros_like(pad)
    step = int(SR * 1.3333)
    for i in range(0, len(pad) - step, step):
        seg = sine(notes[(i // step) % len(notes)], 0.9) * env_exp(0.9, 5) * 0.12
        arp[i:i + len(seg)] += seg
    swell = 0.8 + 0.2 * np.sin(2 * np.pi * np.arange(len(pad)) / len(pad))
    mono = reverb((pad * 0.8 + arp) * swell, 0.35, rt60=2.6, hi=4000, dur=3.5)
    # seamless AFTER haas: the stereo delays add their own tail, and wrapping
    # before them would leave that tail hanging past the loop point
    write_wav("menu", norm(seamless(haas(mono, 11, 19, 0.45), 1.2), 0.58), music=True)


def make_combat_music():
    bpm = 100.0
    beat = 60.0 / bpm
    bars = 16
    n = int(SR * beat * 4 * bars)
    out = np.zeros(n)
    kick = mix(sine(sweep(130, 42, 0.2, 0.5), 0.2) * env_exp(0.2, 7),
               hp_fft(noise(0.006), 2000) * env_exp(0.006, 16) * 0.4)
    snare = mix(bp_fft(noise(0.16), 900, 5200) * env_exp(0.16, 9) * 0.5,
                sine(190, 0.1) * env_exp(0.1, 12) * 0.2)
    hat = hp_fft(noise(0.05), 6500) * env_exp(0.05, 11) * 0.18
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
    riff = [55.0, 55.0, 65.4, 55.0, 73.4, 65.4, 55.0, 49.0]
    for b8 in range(int(bars * 8)):
        i = int(b8 * beat / 2 * SR)
        seg = lp_fft(saw(riff[b8 % 8], beat / 2 * 0.9) *
                     env_adsr(beat / 2 * 0.9, 0.01, 0.08) * 0.42, 780)
        if i + len(seg) < n:
            out[i:i + len(seg)] += seg
    pad_prog = [(110.0, [0, 3, 7]), (103.8, [0, 3, 7]), (110.0, [0, 3, 7]), (116.5, [0, 3, 6])]
    pads = [chord_pad(root, ch, beat * 4, cutoff=650) * env_adsr(beat * 4, 0.4, 0.6) * 0.5
            for root, ch in pad_prog * 4]
    pad = np.concatenate(pads)
    out += pad[:n] if len(pad) > n else np.pad(pad, (0, n - len(pad)))
    arp_notes = [220, 261.6, 329.6, 261.6]
    for b16 in range(int(bars * 16)):
        i = int(b16 * beat / 4 * SR)
        seg = square(arp_notes[b16 % 4] * 2, beat / 4 * 0.7) * env_exp(beat / 4 * 0.7, 6) * 0.05
        if i + len(seg) < n:
            out[i:i + len(seg)] += seg
    mono = reverb(sat(out, 1.3), 0.22, rt60=1.6, hi=5000, dur=2.2)
    write_wav("combat", norm(seamless(haas(mono, 8, 14, 0.35), 0.6), 0.62), music=True)


make_menu_music()
make_combat_music()
print("ALL AUDIO DONE")
