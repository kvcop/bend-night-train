import Base
import ../../src/ride.bend as Ride

def P.show(+n: Nat) -> IO(Unit):
  IO.print(Nat.show(n) ++ "\n")

def P.one(+path: String) -> IO(Unit):
  do IO<Unit>:
    a : U32 <- P.env.u32("ZZ", 3)
    +b = U32.to_nat(a)
    +c = Ride.Ride.lean()
    P.show(b)
    P.show(U32.to_nat(a))

def P.env.u32(name: String, +dflt: U32) -> IO(U32):
  do IO<U32>:
    r : Result<&1, &1, U32 & String, String> <- IO.get_env(name)
    P.pick(r, dflt)

def P.pick(r: Result<&1, &1, U32 & String, String>, +dflt: U32) -> IO(U32):
  match r:
    case Fail{e}:
      IO.pure(U32, dflt)
    case Done{value}:
      IO.pure(U32, dflt)

def main() -> IO(Unit):
  P.one("x")
