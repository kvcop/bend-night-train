import Base
import ../../src/ride.bend as Ride

def R.get() -> IO(U32):
  IO.pure(U32, 3)

def R.a() -> IO(Unit):
  do IO<Unit>:
    a : U32 <- R.get()
    b : Nat = U32.to_nat(a)
    +c : F32 = Ride.Ride.lean()
    +t : List<&2, Ride.Rt.P3> = Ride.Ride.win(c)
    IO.print(Nat.show(Nat.add(b, Nat.length(&2, Ride.Rt.P3, t))) ++ " " ++ F32.show(c) ++ "\n")
