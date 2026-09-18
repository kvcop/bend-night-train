# How expensive is walking the same short list once per pixel?
#
# The rasteriser wants one triangle list per 8x8 tile, walked by each of the
# tile's 64 pixels.  Bend is affine: the second walk needs a `+`, which is a
# real dup.  This measures that cost directly: P outer ticks, T tiles, each
# step walking an N-triangle list.
import Base

type T is Data:
  T{a: F32, b: F32, c: F32}


def Mk.go(+i: Nat, +acc: List<&2, T>) -> List<&2, T>:
  match i:
    case 0n:
      acc
    case 1n+k:
      Mk.go(k, T{1.0, 2.0, 3.0} <> acc)


def Sum(ts: List<&2, T>, +acc: F32) -> F32:
  match ts:
    case []:
      acc
    case t <> rest:
      T{a, b, c} = t
      Sum(rest, (acc + a + b + c : F32))


def Rep(+i: Nat, +ts: List<&2, T>, +acc: F32) -> F32:
  match i:
    case 0n:
      acc
    case 1n+k:
      Rep(k, ts, (acc + Sum(ts, 0.0) : F32))


def Tiles(+j: Nat, +ts: List<&2, T>, +acc: F32) -> F32:
  match j:
    case 0n:
      acc
    case 1n+k:
      Tiles(k, ts, (acc + Rep(64n, ts, 0.0) : F32))


def main() -> IO(Unit):
  do IO<Unit>:
    +ts = Mk.go(10n, [])
    IO.print(F32.show(Tiles(16384n, ts, 0.0)) ++ "\n")
