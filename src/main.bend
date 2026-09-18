# Main: the headless driver.  Renders one frame into an Image quadtree (the
# parallel part), flattens it row-major, writes a text PPM, and prints a
# checksum so two runs can be compared without diffing megabytes.
import Base
import ./color.bend as Color
import ./scene.bend as Scene

# ---- flattening ------------------------------------------------------
# The quadtree is not in row-major order, so a row is extracted by walking
# the tree: below half-way the top children carry the row, above it the
# bottom ones do.


# ---- writing ---------------------------------------------------------
# File.write hands back the handle beside a Result, so it binds directly;
# only File.open is fallible in the IO.try sense.  The pair is unpacked in
# its own def because a destructuring let is not a statement in a do block.


def Main.env.f32.maybe(m: Maybe<&2, F32>, +dflt: F32) -> IO(F32):
  match m:
    case None{}:
      IO.pure(F32, dflt)
    case Some{v}:
      IO.pure(F32, v)



def Main.env.f32.pick(r: Result<&1, &1, U32 & String, String>, +dflt: F32)
  -> IO(F32):
  match r:
    case Fail{e}:
      IO.pure(F32, dflt)
    case Done{value}:
      Main.env.f32.maybe(F32.read(value), dflt)



def Main.env.f32(name: String, +dflt: F32) -> IO(F32):
  do IO<F32>:
    r : Result<&1, &1, U32 & String, String> <- IO.get_env(name)
    Main.env.f32.pick(r, dflt)



def Main.env.str.pick(r: Result<&1, &1, U32 & String, String>, +dflt: String)
  -> IO(String):
  match r:
    case Fail{e}:
      IO.pure(String, dflt)
    case Done{value}:
      IO.pure(String, value)



def Main.env.str(name: String, +dflt: String) -> IO(String):
  do IO<String>:
    r : Result<&1, &1, U32 & String, String> <- IO.get_env(name)
    Main.env.str.pick(r, dflt)



# `U32.read` hands back a Maybe, and a match may not scrutinise a call, so
# the parse result is matched in a def of its own.
def Main.env.u32.maybe(m: Maybe<&2, U32>, +dflt: U32) -> IO(U32):
  match m:
    case None{}:
      IO.pure(U32, dflt)
    case Some{v}:
      IO.pure(U32, v)



def Main.env.u32.pick(r: Result<&1, &1, U32 & String, String>, +dflt: U32)
  -> IO(U32):
  match r:
    case Fail{e}:
      IO.pure(U32, dflt)
    case Done{value}:
      Main.env.u32.maybe(U32.read(value), dflt)



# ---- configuration ---------------------------------------------------
# Read from the environment so one binary can render any frame at any size:
# recompiling between benchmark runs would put the compiler in the timing.

def Main.env.u32(name: String, +dflt: U32) -> IO(U32):
  do IO<U32>:
    r : Result<&1, &1, U32 & String, String> <- IO.get_env(name)
    Main.env.u32.pick(r, dflt)


def Main.wrote(f: File, r: Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  match r:
    case Fail{e}:
      IO.print_err("bend-night-train: write failed\n")
    case Done{value}:
      File.close(f)




def Main.save.done(fr: File & Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  (f, r) = fr
  Main.wrote(f, r)




def Main.save(path: String, +data: String) -> IO(Unit):
  do IO<Unit>:
    f : File <- IO.try(File, File.open(path, "w"))
    fr : File & Result<&1, &1, U32 & String, Unit> <- File.write(f, data)
    Main.save.done(fr)



def Px.show(+c: U32) -> String:
  U32.show(Color.red(c)) ++ " " ++ U32.show(Color.green(c)) ++ " "
    ++ U32.show(Color.blue(c)) ++ "\n"




# One row of a 2^d x 2^d image.  `up` says whether the row falls in the top
# half; it has to be a parameter because a match may only scrutinise a
# parameter, and the def has to recurse into itself rather than into a
# helper, because Bend rejects mutual recursion.
def Px.row(+d: Nat, img: Image, +y: U32, up: Bool, +half: U32) -> String:
  match d:
    case 0n:
      match img:
        case Pix{c}:
          Px.show(c)
        case Qua{tl, tr, bl, br}:
          ""
    case 1n+e:
      match img:
        case Pix{c}:
          ""
        case Qua{tl, tr, bl, br}:
          match up:
            case True{}:
              +h2 = U32.shrn(half, 1n)
              +up2 = U32.is_lt(y, h2)
              a b = Px.row(e, tl, y, up2, h2) Px.row(e, tr, y, up2, h2)
              a ++ b
            case False{}:
              +h2 = U32.shrn(half, 1n)
              +yy = (y - half : U32)
              +up2 = U32.is_lt(yy, h2)
              a b = Px.row(e, bl, yy, up2, h2) Px.row(e, br, yy, up2, h2)
              a ++ b




def Px.rows.line(+d: Nat, img: Image, +y: U32) -> String:
  +half = U32.shrn(U32.shln(1, d), 1n)
  Px.row(d, img, y, U32.is_lt(y, half), half)




# Rows are emitted last-to-first with each one prepended, which costs
# O(width) per row; appending forward would copy the whole prefix every time.
def Px.rows(+d: Nat, +img: Image, +i: Nat, +acc: String) -> String:
  match i:
    case 0n:
      Px.rows.line(d, img, 0) ++ acc
    case 1n+p:
      +k = U32.add(U32.from_nat(p), 1)
      Px.rows(d, img, p, Px.rows.line(d, img, k) ++ acc)


def Main.maybe_save(write: Bool, +d: Nat, img: Image, path: String)
  -> IO(Unit):
  match write:
    case True{}:
      +w = U32.shln(1, d)
      Main.save(path, "P3\n" ++ U32.show(w) ++ " " ++ U32.show(w) ++ "\n255\n"
        ++ Px.rows(d, img, Nat.sub(U32.to_nat(w), 1n), ""))
    case False{}:
      IO.pure(Unit, Unit{})




# ---- driver ----------------------------------------------------------

# A match may only scrutinise a parameter and no let may precede it, so
# `bang` leads the parameter list and the setup is repeated in both arms.
def Main.render(+bang: Bool, +d: Nat, +s: F32, +side: F32) -> Image:
  match bang:
    case True{}:
      +w = U32.shln(1, d)
      +cam = Scene.Cam.fit(w, w, Scene.Cam.ride(s, side, 3.05, 0.0, 0.0))
      +cars = Scene.consist(s)
      Scene.frame!(d, 0, 0, cam, cars)
    case False{}:
      +w = U32.shln(1, d)
      +cam = Scene.Cam.fit(w, w, Scene.Cam.ride(s, side, 3.05, 0.0, 0.0))
      +cars = Scene.consist(s)
      Scene.frame(d, 0, 0, cam, cars)




# ---- checksum --------------------------------------------------------
# An order-independent digest of the framebuffer: the XOR fold makes a
# flipped or transposed frame hash the same, so it is a cheap equality test
# for a render against itself, not a fingerprint of the picture.

def Px.checksum(+d: Nat, +img: Image, +acc: U32) -> U32:
  match d:
    case 0n:
      match img:
        case Pix{c}:
          U32.add(U32.mul(acc, 1664525), U32.add(c, 1013904223))
        case Qua{tl, tr, bl, br}:
          0
    case 1n+e:
      match img:
        case Pix{c}:
          0
        case Qua{tl, tr, bl, br}:
          a b = Px.checksum(e, tl, acc) Px.checksum(e, tr, acc)
          c dd = Px.checksum(e, bl, a) Px.checksum(e, br, b)
          U32.xor(c, dd)



def Main.frame(+path: String) -> IO(Unit):
  do IO<Unit>:
    depth : U32 <- Main.env.u32("NT_DEPTH", 8)
    ppm : U32 <- Main.env.u32("NT_PPM", 1)
    side : F32 <- Main.env.f32("NT_SIDE", 4.6)
    s : F32 <- Main.env.f32("NT_S", 0.0)
    bang : U32 <- Main.env.u32("NT_BANG", 1)
    +d : Nat = U32.to_nat(depth)
    +img : Image = Main.render(U32.is_eq(bang, 1), d, s, side)
    IO.print(U32.show(Px.checksum(d, img, 0)) ++ "\n")
    Main.maybe_save(U32.is_eq(ppm, 1), d, img, path)



def main() -> IO(Unit):
  Main.frame("out/frame.ppm")
