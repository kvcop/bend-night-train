# glow: the additive billboard pass -- lit windows, the headlight and its beam,
# dust motes, wayside signals, fireflies and the smoke plume.
#
# The reference (night-train-webgl.html 794-870, 1251-1348) records each light
# with addGlow(x, y, z, radius, r, g, b, alpha); glowProg draws it as a disc of
# screen radius k*radius/w, so radius is a world-space sphere radius and alpha
# multiplies the additive colour.  One light is therefore one Rt.Spr of kind 1.
#
# Exact groups:
#   * per-carriage lit windows -- the local point (side*1.75, 3.05, (w-3)*3) is
#     carried by the same M4.rigid model matrix the carriage mesh uses, via
#     Geo.WTri.rigid.v, the port's copy of it.  Same skipped windows, same order.
#   * headlight lamps, the marker lamp and the nine light-cone sprites, all
#     derived from s and head_on alone.
#   * wayside signals (a function of s) and fireflies (s and t) -- no randomness.
#
# Seeded approximations:
#   * dust motes and the smoke plume seed with Math.random in the reference, so
#     they cannot be replayed bit for bit.  They use the demo's own LCG
#     (Shade.Stars.next / Shade.Stars.rnd, the same one the star field uses,
#     seed 7) with the documented seeds 1013 for the motes and 2027 for the
#     smoke.  The same (s, t) always gives the same sprites.  Distribution and
#     motion follow the reference; positions inside that distribution do not.
#     State the demo integrates frame by frame -- the mote `ds` wrap and the
#     smoke `life` cycle -- is integrated analytically from t, because a
#     headless frame has no previous frame.
import Base
import ./geo.bend as Geo
import ./rt.bend as Rt
import ./trk.bend as Trk
import ./carriage.bend as Carriage
import ./ride.bend as Ride
import ./shade.bend as Shade


# ---- small types -----------------------------------------------------
# A mote's per-load constants, and the reset constants of one smoke puff.

type Mote is Data:
  Mote{ds: F32, side: F32, up: F32, r: F32, warm: Bool, drift: F32, seed: F32,
    sid: U32}


type Smo is Data:
  Smo{life0: F32, sid: U32, off0: F32, seed0: F32}


# What one smoke puff draws for the cycle it is in now: a reset side and seed,
# a one-time backward offset, and which of the two states it is in.
type Knob is Data:
  Knob{side: F32, seed: F32, off: F32, first: Bool}


def Glow.mote.seed() -> U32:
  1013


def Glow.smoke.seed() -> U32:
  2027


# ---- rigid placement -------------------------------------------------
# M4.rigid(px, py, pz, yaw, roll, 1, 1, 1), the carriage model matrix, applied
# to a single local point.  The matrix is WTri.rigid's, not a second copy of it:
# Geo.WTri.rigid.v evaluates m00*x + m01*y + m02*z + tx for one vertex.
def Glow.p3.of(v: Geo.WVtx) -> Rt.P3:
  Geo.WVtx{x, y, z, nx, ny, nz, vr, vg, vb, ve} = v
  Rt.P3{x, y, z}


def Glow.rigid(+yaw: F32, +roll: F32, +px: F32, +py: F32, +pz: F32, +lx: F32,
  +ly: F32, +lz: F32) -> Rt.P3:
  +cy = F32.cos(yaw)
  +sy = F32.sin(yaw)
  +crr = F32.cos(roll)
  +srr = F32.sin(roll)
  +v = Geo.Vx.at(lx, ly, lz, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
  Glow.p3.of(Geo.WTri.rigid.v(v, (cy * crr : F32), (0.0 - cy * srr : F32), sy,
    srr, crr, 0.0, (0.0 - sy * crr : F32), (sy * srr : F32), cy, px, py, pz))


# ---- per-carriage lit windows ----------------------------------------
# for i in 0..CARS-1, for side in [-1, 1], for w in 0..6, skip when
# ((i%3)*7 + w)*7919 % 11 <= 2; the locomotive (i == CARS-1) has no windows.
# Local point (side*1.75, 3.05, (w-3)*3), radius 2.8, alpha 0.14.
# The hash is done in F32 like Carriage.windows: the Nat form unfolds the 7919
# literal at elaboration and overflows the compiler stack.
def Glow.win.put(skip: Bool, +cam: Rt.VCam, p: Rt.P3,
  +acc: List<&2, Rt.Spr>) -> List<&2, Rt.Spr>:
  match skip:
    case True{}:
      acc
    case False{}:
      Rt.P3{x, y, z} = p
      Rt.Spr.at(cam, x, y, z, 2.8, 1.0, 0.67, 0.32, 0.14, 1) <> acc


def Glow.win.row(+n: Nat, +w: U32, +side: F32, +fv: F32, +yaw: F32, +roll: F32,
  +px: F32, +py: F32, +pz: F32, +cam: Rt.VCam, +acc: List<&2, Rt.Spr>)
  -> List<&2, Rt.Spr>:
  match n:
    case 0n:
      acc
    case 1n+k:
      +fw = U32.to_f32(w)
      +skip = F32.is_le(F32.mod(((fv * 7.0 + fw : F32) * 7919.0 : F32), 11.0),
        2.0)
      +lx = (side * 1.75 : F32)
      +lz = ((fw - 3.0) * 3.0 : F32)
      Glow.win.row(k, U32.add(w, 1), side, fv, yaw, roll, px, py, pz, cam,
        Glow.win.put(skip, cam, Glow.rigid(yaw, roll, px, py, pz, lx, 3.05, lz),
          acc))


def Glow.win.side(+n: Nat, +si: U32, +fv: F32, +yaw: F32, +roll: F32, +px: F32,
  +py: F32, +pz: F32, +cam: Rt.VCam, +acc: List<&2, Rt.Spr>)
  -> List<&2, Rt.Spr>:
  match n:
    case 0n:
      acc
    case 1n+k:
      +fs = U32.to_f32(si)
      +side = (fs * 2.0 - 1.0 : F32)
      Glow.win.side(k, U32.add(si, 1), fv, yaw, roll, px, py, pz, cam,
        Glow.win.row(7n, 0, side, fv, yaw, roll, px, py, pz, cam, acc))


def Glow.win.car(loco: Bool, +i: U32, +yaw: F32, +roll: F32, +px: F32, +py: F32,
  +pz: F32, +cam: Rt.VCam, +acc: List<&2, Rt.Spr>) -> List<&2, Rt.Spr>:
  match loco:
    case True{}:
      acc
    case False{}:
      +fv = U32.to_f32(U32.mod(i, 3))
      Glow.win.side(2n, 0, fv, yaw, roll, px, py, pz, cam, acc)


def Glow.win.go(+n: Nat, +i: U32, +s: F32, +cam: Rt.VCam,
  +acc: List<&2, Rt.Spr>) -> List<&2, Rt.Spr>:
  match n:
    case 0n:
      acc
    case 1n+k:
      +cs = Carriage.Carriage.centre(i, s)
      Glow.win.go(k, U32.add(i, 1), s, cam,
        Glow.win.car(U32.is_eq(i, U32.from_nat(
            Nat.sub(Carriage.Carriage.cars_n(), 1n))), i, Trk.Track.yaw(cs),
          Trk.Track.roll(cs), Trk.Track.x(cs), Trk.Track.y(cs), cs, cam, acc))


def Glow.windows(cam: Rt.VCam, +s: F32) -> List<&2, Rt.Spr>:
  List.reverse(&2, Rt.Spr, Glow.win.go(15n, 0, s, cam, []))


# ---- headlight, marker and light cone --------------------------------
# If head_on: yaw = trackYaw(sHead) with sHead = headPos.z; each lamp at
# headPos + (cos yaw, 0, -sin yaw)*k for k in [-1, 1] gets a small (2.2) and a
# wide (7.0) sprite; the marker sits 1.5 above; nine cone sprites step 7.5 m
# along the track from sHead, growing with distance and fading towards i == 11.
def Glow.cone.go(+n: Nat, +i: Nat, +cam: Rt.VCam, +sh: F32,
  +acc: List<&2, Rt.Spr>) -> List<&2, Rt.Spr>:
  match n:
    case 0n:
      acc
    case 1n+k:
      +fi = U32.to_f32(U32.from_nat(i))
      +d = (fi * 7.5 : F32)
      +fs = (sh + d : F32)
      Glow.cone.go(k, Nat.add(i, 1n), cam, sh,
        Rt.Spr.at(cam, Trk.Track.x(fs), (Trk.Track.y(fs) + 1.2 : F32), fs,
          (2.0 + d * 0.30 : F32), 1.0, 0.86, 0.62,
          (0.055 * (1.0 - fi / 11.0 : F32) : F32), 1) <> acc)


def Glow.lamp.pair(+cam: Rt.VCam, +hx: F32, +hy: F32, +hz: F32, +rx: F32,
  +rz: F32, +k: F32, +acc: List<&2, Rt.Spr>) -> List<&2, Rt.Spr>:
  +lx = (hx + rx * k : F32)
  +lz = (hz + rz * k : F32)
  +s1 = Rt.Spr.at(cam, lx, hy, lz, 2.2, 1.0, 0.93, 0.75, 0.95, 1)
  +s2 = Rt.Spr.at(cam, lx, hy, lz, 7.0, 1.0, 0.88, 0.62, 0.32, 1)
  # the head group is reversed once at the end, so the pair is accumulated
  # back-to-front: the wide 7.0 sprite consed first, the small 2.2 sprite last.
  s2 <> (s1 <> acc)


def Glow.head.at(head_on: Bool, hp: Rt.P3, +cam: Rt.VCam)
  -> List<&2, Rt.Spr>:
  match head_on:
    case False{}:
      []
    case True{}:
      Rt.P3{+hx, +hy, +hz} = hp
      +yaw = Trk.Track.yaw(hz)
      +rx = F32.cos(yaw)
      +rz = (0.0 - F32.sin(yaw) : F32)
      +a1 = Glow.lamp.pair(cam, hx, hy, hz, rx, rz, (0.0 - 1.0 : F32), [])
      +a2 = Glow.lamp.pair(cam, hx, hy, hz, rx, rz, 1.0, a1)
      +mk = Rt.Spr.at(cam, hx, (hy + 1.5 : F32), hz, 1.2, 1.0, 0.85, 0.55,
        0.55, 1)
      List.reverse(&2, Rt.Spr, Glow.cone.go(9n, 1n, cam, hz, mk <> a2))


def Glow.headlist(+cam: Rt.VCam, +s: F32, +head_on: Bool)
  -> List<&2, Rt.Spr>:
  Glow.head.at(head_on, Ride.Ride.head.pos(s), cam)


# ---- dust motes ------------------------------------------------------
# 70 motes; the seven per-mote draws are ds, side, up, r, warm, drift, seed
# (reference order), each from the mote's own LCG stream.  The demo decrements
# ds by speed*(0.85 + seed*0.03) every frame and wraps it to +110 below -26;
# that is a linear drift in t, so ds(t) is evaluated from t directly.  A wrap
# resamples side and up in the reference; here those come from a stream indexed
# by the wrap count, so the same t always gives the same sprite.
def Glow.mote.mk(+i: U32) -> Mote:
  +s0 = Shade.Stars.next(U32.add(Glow.mote.seed(), i))
  +s1 = Shade.Stars.next(s0)
  +s2 = Shade.Stars.next(s1)
  +s3 = Shade.Stars.next(s2)
  +s4 = Shade.Stars.next(s3)
  +s5 = Shade.Stars.next(s4)
  +s6 = Shade.Stars.next(s5)
  +s7 = Shade.Stars.next(s6)
  Mote{(Shade.Stars.rnd(s1) * 90.0 - 30.0 : F32),
    ((Shade.Stars.rnd(s2) - 0.5 : F32) * 9.0 : F32),
    (Shade.Stars.rnd(s3) * 5.0 - 1.4 : F32),
    (0.035 + Shade.Stars.rnd(s4) * 0.13 : F32),
    F32.is_lt(Shade.Stars.rnd(s5), 0.28),
    ((Shade.Stars.rnd(s6) - 0.5 : F32) * 1.6 : F32),
    (Shade.Stars.rnd(s7) * 10.0 : F32), s0}


def Glow.mote.at(cam: Rt.VCam, m: Mote, +s: F32, +t: F32,
  +acc: List<&2, Rt.Spr>) -> List<&2, Rt.Spr>:
  Mote{+ds0, +side0, +up0, +r, +warm, +drift, +seed, +sid} = m
  +ve = (24.5 * (0.85 + seed * 0.03 : F32) : F32)
  +p0 = (ds0 + 26.0 : F32)
  +p = (p0 - ve * t : F32)
  +c = F32.floor((p / 110.0 : F32))
  +c0 = F32.floor((p0 / 110.0 : F32))
  +k = (c0 - c : F32)
  +wrapped = F32.is_gt(k, 0.0)
  +q = (p - 110.0 * c : F32)
  +ds = (q - 26.0 : F32)
  +kn = U32.from_nat(F32.to_nat(k))
  +h = Shade.Stars.next(U32.add(sid, U32.mul(kn, 131)))
  +sideR = ((Shade.Stars.rnd(h) - 0.5 : F32) * 9.0 : F32)
  +upR = (Shade.Stars.rnd(Shade.Stars.next(h)) * 5.0 - 1.4 : F32)
  +side = Bool.pick(F32, wrapped, sideR, side0)
  +up = Bool.pick(F32, wrapped, upR, up0)
  +ms = (s + ds : F32)
  +yaw = Trk.Track.yaw(ms)
  +wob = (F32.sin((t * 3.1 + seed * 6.0 : F32)) * drift : F32)
  +lat = (0.0 - 3.1 + side * 0.55 + wob : F32)
  +mx = (Trk.Track.x(ms) + lat * F32.cos(yaw) : F32)
  +mz = (ms - lat * F32.sin(yaw) : F32)
  +my = (Trk.Track.y(ms) + 2.2 + up : F32)
  +near = (1.0 - F32.min(1.0, (F32.abs(ds) / 26.0 : F32)) : F32)
  +rad = Bool.pick(F32, warm, (r * 2.4 : F32), (r * 2.0 : F32))
  +cr = Bool.pick(F32, warm, 1.0, 0.72)
  +cb = Bool.pick(F32, warm, 0.52, 0.95)
  +al = Bool.pick(F32, warm, (0.22 * near : F32), (0.12 * near : F32))
  Rt.Spr.at(cam, mx, my, mz, rad, cr, 0.80, cb, al, 1) <> acc


def Glow.mote.go(+n: Nat, +i: U32, +cam: Rt.VCam, +s: F32, +t: F32,
  +acc: List<&2, Rt.Spr>) -> List<&2, Rt.Spr>:
  match n:
    case 0n:
      acc
    case 1n+k:
      Glow.mote.go(k, U32.add(i, 1), cam, s, t,
        Glow.mote.at(cam, Glow.mote.mk(i), s, t, acc))


def Glow.motes(cam: Rt.VCam, +s: F32, +t: F32) -> List<&2, Rt.Spr>:
  List.reverse(&2, Rt.Spr, Glow.mote.go(70n, 0, cam, s, t, []))


# ---- wayside signals and fireflies -----------------------------------
# Both are pure functions of s (and t for the blink): no history, no randomness,
# so these groups are exact.
def Glow.sig.go(+n: Nat, +i: Nat, +cam: Rt.VCam, +s: F32,
  +acc: List<&2, Rt.Spr>) -> List<&2, Rt.Spr>:
  match n:
    case 0n:
      acc
    case 1n+k:
      +fi = U32.to_f32(U32.from_nat(i))
      +gs = ((F32.floor((s / 176.0 : F32)) - 2.0 + fi : F32) * 176.0 : F32)
      +gx = (Trk.Track.x(gs) - 6.4 : F32)
      +gy = (Trk.Track.y(gs) + 3.8 : F32)
      +a1 = Rt.Spr.at(cam, gx, gy, gs, 0.26, 0.30, 1.0, 0.57, 0.9, 1)
      +a2 = Rt.Spr.at(cam, gx, gy, gs, 1.2, 0.20, 1.0, 0.43, 0.18, 1)
      Glow.sig.go(k, Nat.add(i, 1n), cam, s, a2 <> (a1 <> acc))


def Glow.signals(cam: Rt.VCam, +s: F32) -> List<&2, Rt.Spr>:
  List.reverse(&2, Rt.Spr, Glow.sig.go(8n, 0n, cam, s, []))


def Glow.fly.go(+n: Nat, +i: Nat, +cam: Rt.VCam, +s: F32, +t: F32,
  +acc: List<&2, Rt.Spr>) -> List<&2, Rt.Spr>:
  match n:
    case 0n:
      acc
    case 1n+k:
      +fi = U32.to_f32(U32.from_nat(i))
      +cell = (F32.floor((s / 8.0 : F32)) - 8.0 + fi : F32)
      +gs = (cell * 8.0 : F32)
      +side = (0.0 - 12.0 - F32.sin((cell * 6.3 : F32)) * 5.0 : F32)
      +blink = F32.pow(F32.max(0.0, F32.sin((t * 0.75 + cell * 3.1 : F32))), 3.0)
      +fx = (Trk.Track.x(gs) + side : F32)
      +fy = (Trk.Track.y(gs) + 1.1 + F32.sin(cell) * 0.7 : F32)
      Glow.fly.go(k, Nat.add(i, 1n), cam, s, t,
        Rt.Spr.at(cam, fx, fy, gs, 0.28, 0.73, 0.95, 0.37,
          (blink * 0.26 : F32), 1) <> acc)


def Glow.fireflies(cam: Rt.VCam, +s: F32, +t: F32) -> List<&2, Rt.Spr>:
  List.reverse(&2, Rt.Spr, Glow.fly.go(28n, 0n, cam, s, t, []))


# ---- smoke -----------------------------------------------------------
# 44 puffs.  In the reference life += 0.30*dt and resets to 0 past 1, and a
# reset moves the puff to the then-current head position and resamples side and
# seed.  life(t) is fract(life0 + 0.30*t), so the cycle count is its floor and
# the head position at the reset is the head at s - speed*(life/0.30).  The
# first cycle is the special one: the demo sets pt.s once at load, when it is
# emitS(at t=0) - rnd*60, and it has no reset behind it.
def Glow.smoke.knob(n: Nat, +sid: U32, +off0: F32, +seed0: F32) -> Knob:
  match n:
    case 0n:
      Knob{0.0, seed0, off0, True{}}
    case 1n++k:
      +cyc = U32.from_nat(k)
      +h = Shade.Stars.next(U32.add(sid, U32.mul(cyc, 131)))
      Knob{((Shade.Stars.rnd(h) - 0.5 : F32) * 0.5 : F32),
        Shade.Stars.rnd(Shade.Stars.next(h)), 0.0, False{}}


def Glow.smoke.one(cam: Rt.VCam, kn: Knob, +life: F32, +s: F32, +t: F32,
  +acc: List<&2, Rt.Spr>) -> List<&2, Rt.Spr>:
  Knob{side, seed, off, first} = kn
  +back = Bool.pick(F32, first, t, (life / 0.30 : F32))
  +sres = (s - 24.5 * back : F32)
  +emit = (Ride.Ride.head.centre(sres) - 3.0 : F32)
  +ps0 = (emit - off : F32)
  +ps = (ps0 - life * 46.0 : F32)
  +px = (Trk.Track.x(ps) + side
    + F32.sin((seed * 12.0 + life * 3.0 : F32)) * life * 3.5 : F32)
  +py = (Trk.Track.y(ps) + 4.6 + life * 7.5 : F32)
  +al = F32.max(0.0, (0.30 * (1.0 - life) * F32.min(1.0, life * 6.0) : F32))
  Rt.Spr.at(cam, px, py, ps, (2.0 + life * 11.0 : F32), 0.62, 0.63, 0.70, al,
    1) <> acc


def Glow.smoke.at(cam: Rt.VCam, p: Smo, +s: F32, +t: F32,
  +acc: List<&2, Rt.Spr>) -> List<&2, Rt.Spr>:
  Smo{life0, sid, off0, seed0} = p
  +x = (life0 + 0.30 * t : F32)
  +life = (x - F32.floor(x) : F32)
  +n = F32.to_nat(F32.floor(x))
  Glow.smoke.one(cam, Glow.smoke.knob(n, sid, off0, seed0), life, s, t, acc)


def Glow.smoke.mk(+i: U32) -> Smo:
  +s0 = Shade.Stars.next(U32.add(Glow.smoke.seed(), i))
  +s1 = Shade.Stars.next(s0)
  +s2 = Shade.Stars.next(s1)
  +s3 = Shade.Stars.next(s2)
  Smo{Shade.Stars.rnd(s1), s0, (Shade.Stars.rnd(s2) * 60.0 : F32),
    Shade.Stars.rnd(s3)}


def Glow.smoke.go(+n: Nat, +i: U32, +cam: Rt.VCam, +s: F32, +t: F32,
  +acc: List<&2, Rt.Spr>) -> List<&2, Rt.Spr>:
  match n:
    case 0n:
      acc
    case 1n+k:
      Glow.smoke.go(k, U32.add(i, 1), cam, s, t,
        Glow.smoke.at(cam, Glow.smoke.mk(i), s, t, acc))


def Glow.smoke(cam: Rt.VCam, +s: F32, +t: F32) -> List<&2, Rt.Spr>:
  List.reverse(&2, Rt.Spr, Glow.smoke.go(44n, 0, cam, s, t, []))


# ---- one frame -------------------------------------------------------
# Groups concatenated in the reference's own accumulation order: windows, the
# headlight group, motes, signals, fireflies, smoke.
def Glow.list(+cam: Rt.VCam, +s: F32, +t: F32, +head_on: Bool)
  -> List<&2, Rt.Spr>:
  +win = Glow.windows(cam, s)
  +hed = Glow.headlist(cam, s, head_on)
  +mot = Glow.motes(cam, s, t)
  +sig = Glow.signals(cam, s)
  +fly = Glow.fireflies(cam, s, t)
  +smo = Glow.smoke(cam, s, t)
  List.concat(&2, Rt.Spr, [win, hed, mot, sig, fly, smo])
