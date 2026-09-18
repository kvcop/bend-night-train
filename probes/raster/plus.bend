import Base

type F is Data:
  F{a: F32, b: F32}

def F.use(f: F) -> F32:
  F{+a, +b} = f
  (a + b : F32)

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(F32.show(F.use(F{1.0, 2.0})) ++ "\n")
