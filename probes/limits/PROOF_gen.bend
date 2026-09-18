# The general frame law (4^d rays) runs out of arithmetic lemmas in Base.
#
# The step needs x + 0 = x and associativity, neither of which Base provides;
# docs/laws.md shows where the proof stops.
import Base
import ../../src/shape.bend as Shape

law frame_pixels:
  for d: Nat
  {Shape.leaves(Shape.frame(d)) == Nat.pow(4n, d) : Nat}

def frame_pixels(d):
  match d:
    case 0n:
      {==}
    case 1n+p:
      %frame_pixels(p) : {Shape.leaves(Shape.frame(p)) == Nat.pow(4n, p) : Nat}
      {==}
