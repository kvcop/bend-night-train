# A deliberately false law: the checker must refuse it.
#
# Shape.frame(3n) is a 8x8 frame, i.e. 64 leaves, but the law claims 16.  This
# is the negative test for the proof gate; docs/laws.md shows the exact error.
import Base
import ../../src/shape.bend as Shape

law frame8:
  {Shape.leaves(Shape.frame(3n)) == 16n : Nat}

def frame8():
  {==}
