# LAWS.bend -- the laws of the night-train renderer.
#
# This file is the human's.  It states what must never break, in a form the
# compiler can check; PROOF.bend is where those claims are discharged.  The
# gate is `bend PROOF.bend`, which must print "All terms check."
#
# Read docs/laws.md for what is deliberately NOT here: F32 is opaque to the
# checker (every F32 operation is a law with no definition), so no law below
# can mention a pixel's colour, a camera position or a track coordinate.
# What can be stated and proven is the structure -- and the structure is
# where this program's parallelism lives.
import Base
import ./src/scene.bend as Scene
import ./src/shape.bend as Shape

# LAW: the consist walks exactly the slots it claims to.  The carriage
# geometry is F32 and out of reach, but an off-by-one in the index sequence
# -- one too many cars, or one too few -- is a checked error here.
law consist_slots:
  for k: Nat
  {List.length(&2, Nat, Scene.slots(k)) == k : Nat}

# LAW: splitting the frame into its four parallel quadrants loses no pixel
# and invents none.  This is the law the scheduler relies on: the four-way
# parallel call is only sound because the join reassembles exactly the
# pixels that were handed out.
law quad_pixels:
  for a: Image
  for b: Image
  for c: Image
  for e: Image
  {Shape.leaves(Qua{a, b, c, e}) == Nat.add(Shape.leaves(a), Nat.add(Shape.leaves(b), Nat.add(Shape.leaves(c), Shape.leaves(e)))) : Nat}

# LAW: an 8x8 frame is exactly 64 rays, cast once each.  Stated at depth 3, a
# size the checker evaluates outright, so a change to the quadtree recursion
# that drops or duplicates a quadrant fails here rather than in a picture.
law frame8:
  {Shape.leaves(Shape.frame(3n)) == 64n : Nat}
