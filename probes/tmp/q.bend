import Base

def P.show(+n: Nat) -> IO(Unit):
  IO.print(Nat.show(n) ++ "\n")

def Q.get() -> IO(U32):
  IO.pure(U32, 3)

def Q.a() -> IO(Unit):
  do IO<Unit>:
    a : U32 <- Q.get()
    +b : Nat = U32.to_nat(a)
    P.show(b)
    P.show(b)
