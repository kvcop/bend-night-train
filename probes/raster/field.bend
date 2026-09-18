import Base

type P is Data:
  P{a: F32, b: F32}


def P.use(p: P) -> F32:
  (p.a + p.b : F32)


def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(F32.show(P.use(P{1.0, 2.0})) ++ "\n")
