# Scene: the night train, as pure functions.
#
# The world is a graph over z.  The centreline is P(z) = (Track.x(z),
# Track.y(z), z) -- the same two sine harmonics the WebGL demo uses, so the
# camera and the geometry cannot drift apart.  Every function here is pure,
# which is exactly why the renderer parallelises: two pixels share nothing.
#
# Deliberate simplifications against the original, all recorded in docs/:
#   * no heightmap: the grass is flat under the bed, the forest stands on it;
#   * no catenary poles, no viaducts, no villages;
#   * pines are round cones, not the demo's layered mesh.
#
# Bend needs `(e : T)` around every arithmetic term: outside an annotation
# `+ - * /` mean Nat, so an unannotated call argument is a type error.  That
# is why this file is denser than the equivalent JS.
import Base
import ./color.bend as Color

# ---- constants -------------------------------------------------------


# ---- camera ----------------------------------------------------------
# The camera hangs beside the consist at window height, offset to the left
# of the centreline, looking down the train as it curves away: the original's
# framing with lean = 1 and yaw = 0.

type Cam is Data:
  Cam{ex: F32, ey: F32, ez: F32, fx: F32, fy: F32, fz: F32, rx: F32, ry: F32,
    rz: F32, ux: F32, uy: F32, uz: F32, cx: F32, cy: F32, sx: F32, sy: F32}




# ---- vectors ---------------------------------------------------------

type V3 is Data:
  V3{x: F32, y: F32, z: F32}




def V3.norm(+v: V3) -> V3:
  V3{+x, +y, +z} = v
  +il = (1.0 / F32.sqrt((x * x + y * y + z * z : F32)) : F32)
  V3{(x * il : F32), (y * il : F32), (z * il : F32)}




def Cam.at(+x: U32, +y: U32, cam: Cam) -> V3:
  Cam{ex, ey, ez, fx, fy, fz, rx, ry, rz, ux, uy, uz, +cx, +cy, sx, sy} = cam
  +px = ((U32.to_f32(x) - cx : F32) / cx * sx : F32)
  +py = ((cy - U32.to_f32(y) : F32) / cy * sy : F32)
  V3.norm(V3{(fx + px * rx + py * ux : F32), (fy + px * ry + py * uy : F32),
    (fz + px * rz + py * uz : F32)})




# The basis is written out in components: a let may not consume a value that
# a later let still needs, and the checker enforces binder order.
def Cam.build(+ex: F32, +ey: F32, +ez: F32, +fx: F32, +fy: F32, +fz: F32)
  -> Cam:
  +fl = (1.0 / F32.sqrt((fx * fx + fy * fy + fz * fz : F32)) : F32)
  +nx = (fx * fl : F32)
  +ny = (fy * fl : F32)
  +nz = (fz * fl : F32)
  +rl = (1.0 / F32.sqrt((fz * fz + fx * fx : F32)) : F32)
  +rx = (fz * rl : F32)
  +rz = ((0.0 - fx : F32) * rl : F32)
  +vx = (ny * rz : F32)
  +vy = (nz * rx - nx * rz : F32)
  +vz = (0.0 - ny * rx : F32)
  +vl = (1.0 / F32.sqrt((vx * vx + vy * vy + vz * vz : F32)) : F32)
  Cam{ex, ey, ez, nx, ny, nz, rx, 0.0, rz, (vx * vl : F32), (vy * vl : F32),
    (vz * vl : F32), 0.0, 0.0, 0.0, 0.0}




def S.fovy() -> F32: 1.12




def Cam.fit(+w: U32, +h: U32, cam: Cam) -> Cam:
  Cam{ex, ey, ez, fx, fy, fz, rx, ry, rz, ux, uy, uz, cx, cy, sx, sy} = cam
  +nw = (U32.to_f32(w) * 0.5 : F32)
  +nh = (U32.to_f32(h) * 0.5 : F32)
  +t = F32.tan((S.fovy() * 0.5 : F32))
  Cam{ex, ey, ez, fx, fy, fz, rx, ry, rz, ux, uy, uz, nw, nh,
    (t * (nw / nh : F32) : F32), t}



def S.a1() -> F32: 58.0



def S.a2() -> F32: 13.0



def S.f1() -> F32: 0.00840



def S.f2() -> F32: 0.02150



def S.p2() -> F32: 1.3




# ---- track -----------------------------------------------------------

def Track.x(+z: F32) -> F32:
  (S.a1() * F32.sin(z * S.f1()) + S.a2() * F32.sin(z * S.f2() + S.p2()) : F32)



def S.b1() -> F32: 3.4



def S.b2() -> F32: 1.6



def S.g1() -> F32: 0.00625



def S.g2() -> F32: 0.015625



def S.q2() -> F32: 0.7




def Track.y(+z: F32) -> F32:
  (S.b1() * F32.sin(z * S.g1()) + S.b2() * F32.sin(z * S.g2() + S.q2()) : F32)




def Track.dx(+z: F32) -> F32:
  (S.a1() * S.f1() * F32.cos(z * S.f1())
    + S.a2() * S.f2() * F32.cos(z * S.f2() + S.p2()) : F32)




def Track.yaw(+z: F32) -> F32:
  F32.atan2(Track.dx(z), 1.0)




def Cam.ride(+s: F32, +side: F32, +hgt: F32, +yaw_off: F32, +pitch: F32) -> Cam:
  +base = Track.yaw(s)
  +cy = F32.cos(base)
  +sy = F32.sin(base)
  +yaw = (base + yaw_off : F32)
  +cp = F32.cos(pitch)
  Cam.build((Track.x(s) - side * cy : F32), (Track.y(s) + hgt : F32),
    (s + side * sy : F32), (F32.sin(yaw) * cp : F32), F32.sin(pitch),
    (F32.cos(yaw) * cp : F32))




# ---- the consist -----------------------------------------------------
# The yaw is baked into cc/ss when the consist is built: the per-step SDF
# must be pure arithmetic, with no sin/cos in the inner loop.

type Car is Data:
  Car{cx: F32, cy: F32, cz: F32, cc: F32, ss: F32, kind: U32}




def Car.far() -> Car:
  Car{0.0, 0.0, 0.0, 1.0, 0.0, 0}




def Car.kind.of(loco: Bool) -> U32:
  match loco:
    case True{}:
      0
    case False{}:
      1



def M.body() -> U32: 3



def M.window() -> U32: 4




def Car.mat.win(win: Bool) -> U32:
  match win:
    case True{}:
      M.window()
    case False{}:
      M.body()



def M.loco() -> U32: 7




def Car.mat.pick(+kind: U32, win: Bool) -> U32:
  match kind:
    case 0:
      M.loco()
    case _:
      Car.mat.win(win)




def window.pattern(+lz: F32, +ly: F32) -> Bool:
  +m = F32.mod((lz + 12.0 : F32), 3.2)
  ((F32.is_lt(F32.abs((m - 1.6 : F32)), 0.40))
    && (F32.is_lt(F32.abs(ly), 1.05) : Bool) : Bool)




def Car.mat(+px: F32, +py: F32, +pz: F32, car: Car) -> U32:
  Car{cx, cy, cz, +cc, +ss, kind} = car
  +lz = ((px - cx : F32) * ss + (pz - cz : F32) * cc : F32)
  Car.mat.pick(kind, window.pattern(lz, (py - cy : F32)))



def S.car_hx() -> F32: 1.45



def S.car_hy() -> F32: 1.50



def S.car_hz() -> F32: 12.0




# ---- distances -------------------------------------------------------

def box(+qx: F32, +qy: F32, +qz: F32) -> F32:
  +mx = F32.max(qx, F32.max(qy, qz))
  +ox = F32.max(qx, 0.0)
  +oy = F32.max(qy, 0.0)
  +oz = F32.max(qz, 0.0)
  (F32.sqrt((ox * ox + oy * oy + oz * oz : F32)) + F32.min(mx, 0.0) : F32)




def Car.sdf(+px: F32, +py: F32, +pz: F32, car: Car) -> F32:
  Car{cx, cy, cz, +cc, +ss, kind} = car
  +dx = (px - cx : F32)
  +dz = (pz - cz : F32)
  +lx = (dx * cc - dz * ss : F32)
  +lz = (dx * ss + dz * cc : F32)
  +q = box((F32.abs(lx) - S.car_hx() + 0.25 : F32),
    (F32.abs((py - cy : F32)) - S.car_hy() + 0.25 : F32),
    (F32.abs(lz) - S.car_hz() + 0.25 : F32))
  (q - 0.25 : F32)




# ---- hashing ---------------------------------------------------------

def Hash.mix(+a: U32, +b: U32) -> U32:
  +h = U32.xor(a, U32.mul(b, 2654435769))
  +h2 = U32.xor(h, U32.shrn(h, 16n))
  U32.mul(U32.xor(h2, U32.shrn(h2, 13n)), 2246822507)




def Hash.f(+a: U32, +b: U32) -> F32:
  (U32.to_f32(Hash.mix(a, b)) * 2.3283064365386963e-10 : F32)



def M.ballast() -> U32: 2




# ---- materials -------------------------------------------------------
# Evaluated once, at the hit point.  The nearest carriage is found here and
# reused for the material, the normal and the window spill, so the consist is
# walked once per pixel instead of once per marching step.

def M.grass() -> U32: 1



def M.pine() -> U32: 5



def M.rail() -> U32: 6




# A pine is a round cone: distance to the axis segment minus the radius
# interpolated along it.  Not an exact cone near the tip, and at night in fog
# the difference does not survive tone mapping.

type Pine is Data:
  Pine{ox: F32, oz: F32, r: F32, h: F32}




def Pine.cell.if(far: Bool, +ox: F32, +oz: F32) -> Pine:
  match far:
    case True{}:
      +h0 = Hash.f(F32.to_u32((ox + 4096.0 : F32)),
        F32.to_u32((oz + 4096.0 : F32)))
      +h1 = Hash.f(F32.to_u32((oz + 4096.0 : F32)),
        F32.to_u32((ox + 4096.0 : F32)))
      Pine{ox, oz, (1.1 + 1.4 * h0 : F32), (7.0 + 8.0 * h1 : F32)}
    case False{}:
      Pine{1000000000.0, 1000000000.0, 0.0, 1.0}




def pine(+px: F32, +py: F32, +pz: F32, p: Pine) -> F32:
  Pine{ox, oz, r, +h} = p
  +q = F32.hypot((px - ox : F32), (pz - oz : F32))
  +t = F32.clamp((py / h : F32), 0.0, 1.0)
  (F32.hypot(q, (py - t * h : F32)) - (r * (1.0 - 0.92 * t) : F32) : F32)




# A cell with no tree holds a pine a billion metres away, which makes the
# min-reduction total: no branch, and no Bool to match on.
def Pine.sdf(+px: F32, +py: F32, +pz: F32, p: Pine, +d: F32) -> F32:
  F32.min(d, pine(px, py, pz, p))



def S.cam_hgt() -> F32: 3.05



def S.cars_n() -> Nat: 15n




def S.cell() -> F32: 9.0



def S.cell_bias() -> F32: 4096.0




def S.cellidx(+x: F32) -> U32:
  F32.to_u32((F32.floor((x / S.cell() : F32)) + S.cell_bias() : F32))



def S.fog_b() -> F32: 0.115



def S.fog_density() -> F32: 0.0026



def S.fog_g() -> F32: 0.068




def S.fog_r() -> F32: 0.055



def S.forest_min_lat() -> F32: 11.0




# normalize(0.42, 0.36, 0.83): the demo's moon direction
def S.moon_x() -> F32: 0.4211



def S.moon_y() -> F32: 0.3609



def S.moon_z() -> F32: 0.8322




def S.pitch() -> F32: 26.6




# ---- scalars ---------------------------------------------------------

def S.sign(+x: F32) -> F32:
  F32.clamp((x * 1000000.0 : F32), (0.0 - 1.0 : F32), 1.0)



def S.slope() -> F32: 0.999




# ---- sky -------------------------------------------------------------

def Star.pick(lit: Bool, +h: F32) -> F32:
  match lit:
    case True{}:
      (0.25 + 0.75 * h : F32)
    case False{}:
      0.0




def Track.bed(+z: F32) -> F32:
  (Track.y(z) - 0.9 : F32)




def Track.dy(+z: F32) -> F32:
  (S.b1() * S.g1() * F32.cos(z * S.g1())
    + S.b2() * S.g2() * F32.cos(z * S.g2() + S.q2()) : F32)




def Track.grass(+z: F32) -> F32:
  (Track.y(z) - 1.4 : F32)




# A destructuring let may only scrutinise a parameter or a field: neither a
# call nor a local binder can head a match.  Accessors are the way around
# that, and the compiler inlines them.
def V3.px(v: V3) -> F32:
  match v:
    case V3{x, y, z}:
      x




def V3.py(v: V3) -> F32:
  match v:
    case V3{x, y, z}:
      y




def V3.pz(v: V3) -> F32:
  match v:
    case V3{x, y, z}:
      z




# ---- albedo ----------------------------------------------------------

def ballast(+px: F32, +pz: F32) -> V3:
  +g = Hash.f(U32.add(F32.to_u32((F32.floor((px * 9.0 : F32)) : F32)), 4096),
    U32.add(F32.to_u32((F32.floor((pz * 9.0 : F32)) : F32)), 4096))
  V3{(0.055 + 0.035 * g : F32), (0.050 + 0.030 * g : F32),
    (0.045 + 0.025 * g : F32)}




def albedo(+mat: U32, +px: F32, +py: F32, +pz: F32) -> V3:
  match mat:
    case 2:
      ballast(px, pz)
    case 3:
      V3{0.115, 0.130, 0.150}
    case 4:
      V3{1.000, 0.700, 0.360}
    case 5:
      V3{0.030, 0.055, 0.040}
    case 6:
      V3{0.220, 0.230, 0.245}
    case 7:
      V3{0.070, 0.080, 0.095}
    case _:
      V3{0.028, 0.038, 0.030}




def car(+i: U32, +s: F32) -> Car:
  +rel = (U32.to_f32(i) * S.pitch() - 5.0 * S.pitch() - 14.88 : F32)
  +cz = (s + rel : F32)
  +yaw = Track.yaw(cz)
  Car{Track.x(cz), (Track.y(cz) + 2.6 : F32), cz, F32.cos(yaw), F32.sin(yaw),
    Car.kind.of(U32.is_eq(i, 14))}




def cars.go(+px: F32, +py: F32, +pz: F32, cars: List<&2, Car>, +d: F32)
  -> F32:
  match cars:
    case []:
      d
    case c <> rest:
      cars.go(px, py, pz, rest, F32.min(d, Car.sdf(px, py, pz, c)))




def cars.if(near: Bool, +px: F32, +py: F32, +pz: F32,
  cars: List<&2, Car>, +d: F32) -> F32:
  match near:
    case True{}:
      cars.go(px, py, pz, cars, d)
    case False{}:
      d




def cars.nearest(+px: F32, +py: F32, +pz: F32, +cars: List<&2, Car>,
  +best: Car) -> Car:
  match cars:
    case []:
      best
    case c <> rest:
      +dc = Car.sdf(px, py, pz, c)
      +db = Car.sdf(px, py, pz, best)
      cars.nearest(px, py, pz, rest,
        Bool.pick(Car, F32.is_lt(dc, db), c, best))


def consist.list(+s: F32, idx: List<&2, Nat>, +acc: List<&2, Car>)
  -> List<&2, Car>:
  match idx:
    case []:
      acc
    case i <> rest:
      consist.list(s, rest, car(U32.from_nat(i), s) <> acc)




# The index sequence the consist is built from.  It is split out from the
# geometry so that LAWS.bend can state -- and PROOF.bend can prove -- that it
# has exactly k slots, which F32 would otherwise make unprovable.
def slots(+k: Nat) -> List<&2, Nat>:
  match k:
    case 0n:
      []
    case 1n+p:
      p <> slots(p)


def consist(+s: F32) -> List<&2, Car>:
  consist.list(s, slots(S.cars_n()), [])




def emissive(+mat: U32) -> F32:
  match mat:
    case 4:
      2.4
    case _:
      0.0




def gloss(+mat: U32) -> F32:
  match mat:
    case 3:
      0.35
    case 6:
      0.90
    case 7:
      0.45
    case _:
      0.05




def mat.ground.hi(above: Bool, +px: F32, +py: F32, +pz: F32) -> U32:
  match above:
    case True{}:
      M.pine()
    case False{}:
      M.grass()




def mat.ground.pick(far: Bool, +px: F32, +py: F32, +pz: F32,
  +alat: F32) -> U32:
  match far:
    case True{}:
      mat.ground.hi(
        F32.is_gt(py, (Track.grass(pz) + 0.12 : F32)), px, py, pz)
    case False{}:
      M.ballast()




def mat.ground(+px: F32, +py: F32, +pz: F32) -> U32:
  mat.ground.pick(
    F32.is_gt(F32.abs((px - Track.x(pz) : F32)), 4.6), px, py, pz,
    F32.abs((px - Track.x(pz) : F32)))




def mat.pick(iscar: Bool, +px: F32, +py: F32, +pz: F32, car: Car) -> U32:
  match iscar:
    case True{}:
      Car.mat(px, py, pz, car)
    case False{}:
      mat.ground(px, py, pz)




def mat(+px: F32, +py: F32, +pz: F32, car: Car, +cd: F32) -> U32:
  mat.pick(F32.is_lt(cd, 0.10), px, py, pz, car)




def normal.car.axis2(ybig: Bool, +lx: F32, +dy: F32, +lz: F32, +cc: F32,
  +ss: F32) -> V3:
  match ybig:
    case True{}:
      V3{0.0, S.sign(dy), 0.0}
    case False{}:
      V3.norm(V3{(S.sign(lz) * ss : F32), 0.0, (S.sign(lz) * cc : F32)})




def normal.car.axis(xbig: Bool, ybig: Bool, +lx: F32, +dy: F32, +lz: F32,
  +cc: F32, +ss: F32) -> V3:
  match xbig:
    case True{}:
      V3.norm(V3{(S.sign(lx) * cc : F32), 0.0, ((0.0 - S.sign(lx) : F32) * ss : F32)})
    case False{}:
      normal.car.axis2(ybig, lx, dy, lz, cc, ss)




# ---- normals ---------------------------------------------------------

def normal.car(+px: F32, +py: F32, +pz: F32, car: Car) -> V3:
  Car{cx, cy, cz, +cc, +ss, kind} = car
  +dx = (px - cx : F32)
  +dy = (py - cy : F32)
  +dz = (pz - cz : F32)
  +lx = (dx * cc - dz * ss : F32)
  +lz = (dx * ss + dz * cc : F32)
  +ax = F32.abs(lx)
  +ay = F32.abs(dy)
  +az = F32.abs(lz)
  # `>=` is sugar for T.is_ge on the annotated type, so a comparison on F32
  # has to name F32 rather than be wrapped in `: Bool`.
  normal.car.axis(F32.is_ge(ax, ay) && F32.is_ge(ax, az),
    F32.is_ge(ay, az), lx, dy, lz, cc, ss)




def normal.ground(+pz: F32) -> V3:
  V3.norm(V3{(0.0 - Track.dy(pz) : F32), 1.0, 0.0})




# The tree in the cell that contains the hit point is the one that was hit
# (or its neighbour), which is close enough for a cone at night: a full fold
# over the candidate cells would need another recursive walk.
def normal.pine.axis(p: Pine, +px: F32, +pz: F32) -> V3:
  Pine{ox, oz, r, h} = p
  V3.norm(V3{(px - ox : F32), 0.8, (pz - oz : F32)})




def pine.cell(+i: U32, +j: U32, +tx: F32, +tdx: F32, +pz: F32) -> Pine:
  +h0 = Hash.f(i, j)
  +h1 = Hash.f(j, i)
  +ox = ((U32.to_f32(i) - S.cell_bias() : F32) * S.cell() + 1.0 + 7.0 * h0 : F32)
  +oz = ((U32.to_f32(j) - S.cell_bias() : F32) * S.cell() + 1.0 + 7.0 * h1 : F32)
  # The centreline is linearised around the marched point: exact to well under
  # a metre over one cell.
  +txx = (tx + tdx * (oz - pz : F32) : F32)
  Pine.cell.if(F32.is_gt(F32.abs((ox - txx : F32)), S.forest_min_lat()), ox, oz)




def normal.pine(+px: F32, +py: F32, +pz: F32) -> V3:
  normal.pine.axis(
    pine.cell(S.cellidx(px), S.cellidx(pz), Track.x(pz), Track.dx(pz),
      pz), px, pz)




def normal(+px: F32, +py: F32, +pz: F32, +mat: U32, car: Car) -> V3:
  match mat:
    case 3:
      normal.car(px, py, pz, car)
    case 4:
      normal.car(px, py, pz, car)
    case 5:
      normal.pine(px, py, pz)
    case _:
      normal.ground(pz)




# ---- shading ---------------------------------------------------------

def shade(+px: F32, +py: F32, +pz: F32, +dist: F32, cam: Cam,
  cars: List<&2, Car>) -> U32:
  Cam{ex, ey, ez, fx, fy, fz, rx, ry, rz, ux, uy, uz, cx, cy, sx, sy} = cam
  +car = cars.nearest(px, py, pz, cars, Car.far())
  +cd = Car.sdf(px, py, pz, car)
  +mat = mat(px, py, pz, car, cd)
  +n = normal(px, py, pz, mat, car)
  +nx = V3.px(n)
  +ny = V3.py(n)
  +nz = V3.pz(n)
  # A destructuring let may only scrutinise a parameter, so the value is read
  # through the accessors rather than bound out of a local let.
  +alb = albedo(mat, px, py, pz)
  +ar = V3.px(alb)
  +ag = V3.py(alb)
  +ab = V3.pz(alb)
  # ambient hemisphere: cold from the sky, almost black off the ground
  +sky = (ny * 0.5 + 0.5 : F32)
  +lr = (0.065 + 0.155 * sky : F32)
  +lg = (0.079 + 0.191 * sky : F32)
  +lb = (0.110 + 0.250 * sky : F32)
  +lam = F32.max(0.0,
    (nx * S.moon_x() + ny * S.moon_y() + nz * S.moon_z() : F32))
  # Blinn-Phong highlight: it is what makes the rails and the roofs read
  +vx = (ex - px : F32)
  +vy = (ey - py : F32)
  +vz = (ez - pz : F32)
  +il = (1.0 / F32.sqrt((vx * vx + vy * vy + vz * vz : F32)) : F32)
  +hx = (S.moon_x() + vx * il : F32)
  +hy = (S.moon_y() + vy * il : F32)
  +hz = (S.moon_z() + vz * il : F32)
  +ih = (1.0 / F32.sqrt((hx * hx + hy * hy + hz * hz : F32)) : F32)
  +nh = F32.max(0.0, ((nx * hx + ny * hy + nz * hz : F32) * ih : F32))
  +spec = (F32.pow(nh, 48.0) * gloss(mat) : F32)
  +moonr = (0.40 * lam * 1.15 + 0.55 * spec : F32)
  +moong = (0.47 * lam * 1.15 + 0.62 * spec : F32)
  +moonb = (0.66 * lam * 1.15 + 0.82 * spec : F32)
  # warm spill from the carriage windows onto the bed and the grass
  +spill = (1.15 / (1.0 + cd * cd * 0.045 : F32) : F32)
  +emis = emissive(mat)
  +cr = (ar * (lr + moonr : F32) + ar * emis + 0.30 * spill : F32)
  +cg = (ag * (lg + moong : F32) + ag * emis + 0.21 * spill : F32)
  +cb = (ab * (lb + moonb : F32) + ab * emis + 0.11 * spill : F32)
  +tr = (cr / (1.0 + cr * 0.38 : F32) : F32)
  +tg = (cg / (1.0 + cg * 0.38 : F32) : F32)
  +tb = (cb / (1.0 + cb * 0.38 : F32) : F32)
  +f = F32.clamp((1.0 - F32.exp((0.0 - F32.square(
    (dist * S.fog_density() : F32)) : F32)) : F32), 0.0, 1.0)
  Color.pack((tr + (S.fog_r() - tr : F32) * f : F32),
    (tg + (S.fog_g() - tg : F32) * f : F32),
    (tb + (S.fog_b() - tb : F32) * f : F32))




def sky(dir: V3) -> U32:
  V3{+dx, +dy, +dz} = dir
  +t = F32.clamp((dy * 1.6 + 0.25 : F32), 0.0, 1.0)
  +moon = F32.max(0.0,
    (dx * S.moon_x() + dy * S.moon_y() + dz * S.moon_z() : F32))
  +halo = F32.pow(moon, 180.0)
  +disc = F32.pow(moon, 9000.0)
  +sh = Hash.f(
    U32.add(F32.to_u32((F32.floor((dx * 220.0 : F32)) : F32)), 8192),
    U32.add(F32.to_u32((F32.floor((dy * 220.0 : F32)) : F32)), 8192))
  +star = Star.pick(F32.is_gt(sh, 0.9965), sh)
  Color.pack((0.020 + 0.055 * t + 0.85 * halo + 6.0 * disc + star * 1.4 : F32),
    (0.028 + 0.070 * t + 0.88 * halo + 6.0 * disc + star * 1.3 : F32),
    (0.055 + 0.150 * t + 0.98 * halo + 6.0 * disc + star * 1.1 : F32))




# ---- one pixel -------------------------------------------------------

def pixel.hit(miss: Bool, +ex: F32, +ey: F32, +ez: F32, +dx: F32, +dy: F32,
  +dz: F32, +t: F32, dir: V3, cam: Cam, cars: List<&2, Car>) -> U32:
  match miss:
    case True{}:
      sky(dir)
    case False{}:
      shade((ex + t * dx : F32), (ey + t * dy : F32), (ez + t * dz : F32),
        t, cam, cars)




def pines.go(+px: F32, +py: F32, +pz: F32, ps: List<&2, Pine>, +d: F32)
  -> F32:
  match ps:
    case []:
      d
    case p <> rest:
      pines.go(px, py, pz, rest, Pine.sdf(px, py, pz, p, d))




def pines.if(far: Bool, +px: F32, +py: F32, +pz: F32, +tx: F32,
  +tdx: F32, +d: F32) -> F32:
  match far:
    case True{}:
      +i0 = S.cellidx(px)
      +j0 = S.cellidx(pz)
      +i1 = U32.add(i0, 1)
      +j1 = U32.add(j0, 1)
      a b c e = pine.cell(i0, j0, tx, tdx, pz)
        pine.cell(i1, j0, tx, tdx, pz)
        pine.cell(i0, j1, tx, tdx, pz)
        pine.cell(i1, j1, tx, tdx, pz)
      pines.go(px, py, pz, [a, b, c, e], d)
    case False{}:
      d




# ---- the field -------------------------------------------------------

def sdf(+px: F32, +py: F32, +pz: F32, cars: List<&2, Car>) -> F32:
  +tx = Track.x(pz)
  +ty = Track.y(pz)
  +tdx = Track.dx(pz)
  +alat = F32.abs((px - tx : F32))
  +grass = ((py - Track.grass(pz) : F32) * S.slope() : F32)
  +bed = (box((alat - 3.4 : F32), (py - (ty - 0.9 : F32) : F32), 0.0)
    * S.slope() : F32)
  # two rails on top of the bed, at lat = +-0.72
  +rail = (box((F32.abs((alat - 0.72 : F32)) - 0.075 : F32),
    (py - (ty - 0.74 : F32) : F32), 0.0) * S.slope() : F32)
  +d0 = F32.min(grass, F32.min(bed, rail))
  +d1 = cars.if(F32.is_lt(alat, 8.0), px, py, pz, cars, d0)
  pines.if(F32.is_gt(alat, 9.0), px, py, pz, tx, tdx, d1)




# ---- marching --------------------------------------------------------

def march(+i: Nat, +stop: Bool, +ox: F32, +oy: F32, +oz: F32, +dx: F32,
  +dy: F32, +dz: F32, +t: F32, +cars: List<&2, Car>) -> F32:
  match i:
    case 0n:
      t
    case 1n+k:
      match stop:
        case True{}:
          t
        case False{}:
          +d = sdf((ox + t * dx : F32), (oy + t * dy : F32),
            (oz + t * dz : F32), cars)
          +t2 = (t + d : F32)
          march(k, (F32.is_lt(d, 0.02) || F32.is_gt(t2, 400.0) : Bool), ox,
            oy, oz, dx, dy, dz, t2, cars)




def trace(+ox: F32, +oy: F32, +oz: F32, dir: V3, cars: List<&2, Car>)
  -> F32:
  V3{dx, dy, dz} = dir
  march(80n, False{}, ox, oy, oz, dx, dy, dz, 0.02, cars)




def pixel(+x: U32, +y: U32, +cam: Cam, +cars: List<&2, Car>) -> U32:
  Cam{ex, ey, ez, fx, fy, fz, rx, ry, rz, ux, uy, uz, cx, cy, sx, sy} = cam
  +dir = Cam.at(x, y, cam)
  +dx = V3.px(dir)
  +dy = V3.py(dir)
  +dz = V3.pz(dir)
  +t = trace(ex, ey, ez, dir, cars)
  pixel.hit(F32.is_gt(t, 390.0), ex, ey, ez, dx, dy, dz, t, dir, cam, cars)




# ---- the frame -------------------------------------------------------
# One quadtree, built by a four-way parallel call at every level.  A `!` at
# the call site hands the whole tree to the GPU; without one it spreads over
# the CPU cores.  This is the only place work is split, and it is where every
# speedup in docs/benchmarks.md comes from.

def frame(+d: Nat, +x: U32, +y: U32, +cam: Cam, +cars: List<&2, Car>)
  -> Image:
  match d:
    case 0n:
      Pix{pixel(x, y, cam, cars)}
    case 1n+e:
      +k = U32.shln(1, e)
      +x1 = U32.add(x, k)
      +y1 = U32.add(y, k)
      a b c f = frame(e, x, y, cam, cars)
        frame(e, x1, y, cam, cars)
        frame(e, x, y1, cam, cars)
        frame(e, x1, y1, cam, cars)
      Qua{a, b, c, f}
