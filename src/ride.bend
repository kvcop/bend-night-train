# ride: where the camera sits in the train, and what lights the scene.
#
# Everything here is the demo's own per-frame state, so the two renders agree:
# the camera hangs out of a window on the left of the centreline, the lean
# breathing and the bob are its slow sine terms, and the auto-look aims at a
# point two thirds of the way up the consist.
#
# The demo eases `yawTarget` towards that angle at dt*1.4 and `yaw` towards
# `yawTarget` at dt*7, so a viewer sees the converged value within a third of a
# second.  A headless frame has no previous frame to ease from, so this takes
# the converged value directly; the breathing terms are evaluated at `t`.
import Base
import ./trk.bend as Trk
import ./rt.bend as Rt
import ./shade.bend as Shade
import ./carriage.bend as Carriage


# ---- the camera ------------------------------------------------------
def Ride.lean() -> F32:
  1.0


# The demo freezes the breathing when it thinks the viewer asked for reduced
# motion; `motion` carries that switch, and a frozen frame (motion off) is what
# tools/render_reference.py renders, so it has to be selectable here too.
def Ride.motion.if(+motion: Bool, +a: F32) -> F32:
  Rt.S.if1(motion, a, 0.0)


def Ride.sway(+t: F32, +motion: Bool) -> F32:
  Ride.motion.if(motion,
    (F32.sin((t * 1.9 : F32)) * 0.022 + F32.sin((t * 3.7 : F32)) * 0.008
      : F32))


def Ride.bob(+t: F32, +motion: Bool) -> F32:
  Ride.motion.if(motion,
    (F32.sin((t * 5.3 : F32)) * 0.018 + F32.sin((t * 2.6 : F32)) * 0.016 : F32))


# sideOffset = -2.15 - lean*2.45 + sin(t*0.31)*0.12; VCam.ride takes the same
# offset with the opposite sign (it subtracts it from the centreline).
def Ride.side(+t: F32, +motion: Bool) -> F32:
  (2.15 + Ride.lean() * 2.45
    - Ride.motion.if(motion, F32.sin((t * 0.31 : F32)) * 0.12) : F32)


def Ride.hgt(+t: F32, +motion: Bool) -> F32:
  (3.05 + Ride.bob(t, motion) : F32)


def Ride.pitch(+t: F32, +motion: Bool) -> F32:
  (0.012 + Ride.sway(t, motion) * 0.1 : F32)


# atan2 lands in [-pi, pi] and the track heading is within +-pi/2, so the
# difference leaves [-3pi/2, 3pi/2]: one step each way is a full wrap.
def Ride.want.wrap(+v: F32) -> F32:
  +hi = Rt.S.if1(F32.is_gt(v, 3.141592653589793),
    (v - 6.283185307179586 : F32), v)
  Rt.S.if1(F32.is_lt(hi, (0.0 - 3.141592653589793 : F32)),
    (hi + 6.283185307179586 : F32), hi)


def Ride.want.clamp(+v: F32) -> F32:
  F32.clamp(v, (0.0 - 0.95 : F32), 0.45)


# The aim point: carIndexToS(CARS_BEHIND + round((CARS_AHEAD-1)*0.62)) with
# CARS_AHEAD = 10, so carIndex 11.  Carriage.car_s() subtracts CARS_BEHIND
# itself, so it wants the same 11, not 11 - CARS_BEHIND: passing 6 would put
# the aim five car lengths behind the camera and swing the head across the
# consist.
def Ride.want(+s: F32, +side: F32) -> F32:
  +base = Trk.Track.yaw(s)
  +cb = F32.cos(base)
  +sb = F32.sin(base)
  +camx = (Trk.Track.x(s) - side * cb : F32)
  +camz = (s + side * sb : F32)
  +aims = Carriage.Carriage.car_s(11, s)
  +ay = Trk.Track.yaw(aims)
  +aimx = (Trk.Track.x(aims) + 4.2 * F32.cos(ay) : F32)
  +aimz = (aims - 4.2 * F32.sin(ay) : F32)
  Ride.want.clamp(Ride.want.wrap((F32.atan2((aimx - camx : F32),
    (aimz - camz : F32)) - base : F32)))


def Ride.yaw(+s: F32, +t: F32, +motion: Bool) -> F32:
  (Ride.want(s, Ride.side(t, motion)) + Ride.sway(t, motion) * 0.35 : F32)


# ---- the headlight ---------------------------------------------------
def Ride.head.centre(+s: F32) -> F32:
  Carriage.Carriage.centre(U32.from_nat(Nat.sub(Carriage.Carriage.cars_n(), 1n)),
    s)


def Ride.head.pos(+s: F32) -> Rt.P3:
  +cs = Ride.head.centre(s)
  +yaw = Trk.Track.yaw(cs)
  Rt.P3{(Trk.Track.x(cs) + 9.92 * F32.sin(yaw) : F32),
    (Trk.Track.y(cs) + 1.6 : F32), (cs + 9.92 * F32.cos(yaw) : F32)}


def Ride.head.dir(+s: F32) -> Rt.P3:
  +yaw = Trk.Track.yaw(Ride.head.centre(s))
  +dx = F32.sin(yaw)
  +dy = (0.0 - 0.075 : F32)
  +dz = F32.cos(yaw)
  +l = F32.sqrt((dx * dx + dy * dy + dz * dz : F32))
  Rt.P3{(dx / l : F32), (dy / l : F32), (dz / l : F32)}


# ---- the two uniforms ------------------------------------------------
# Ten warm points, one every two cars, on the camera's side.
def Ride.win.go(+i: Nat, +s: F32, +acc: List<&2, Rt.P3>) -> List<&2, Rt.P3>:
  match i:
    case 0n:
      acc
    case 1n+p:
      +ws = (s - 120.0 + U32.to_f32(U32.from_nat(p)) * 42.0 : F32)
      +yaw = Trk.Track.yaw(ws)
      Ride.win.go(p, s,
        Rt.P3{(Trk.Track.x(ws) - 2.4 * F32.cos(yaw) : F32),
          (Trk.Track.y(ws) + 2.9 : F32),
          (ws + 2.4 * F32.sin(yaw) : F32)} <> acc)


def Ride.win(+s: F32) -> List<&2, Rt.P3>:
  Ride.win.go(10n, s, [])


# The two points are read out of parameters, not out of the calls that built
# them: a match inspects a parameter or a pattern binder, never a computed
# value.
def Ride.lights.at(hp: Rt.P3, hd: Rt.P3, +s: F32) -> Shade.Lights:
  Rt.P3{hx, hy, hz} = hp
  Rt.P3{dx, dy, dz} = hd
  Shade.Lights{hx, hy, hz, dx, dy, dz, Ride.win(s)}


def Ride.lights(+s: F32) -> Shade.Lights:
  Ride.lights.at(Ride.head.pos(s), Ride.head.dir(s), s)
