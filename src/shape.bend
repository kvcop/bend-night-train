# shape: the frame's structure without its pixels.
#
# F32 is opaque to Bend's checker: every F32 operation is a `law` with no
# definition, so no equation about a rendered colour or a camera position can
# be proven.  What is provable is the shape of the quadtree the renderer
# builds -- and that is where the parallel split lives, so the laws about the
# frame are stated here, on the same recursion the renderer uses.
import Base

# The frame's skeleton: the identical parallel decomposition, painting 0
# instead of casting a ray.  Nothing here calls F32.
def frame(+d: Nat) -> Image:
  match d:
    case 0n:
      Pix{0}
    case 1n+e:
      a b = frame(e) frame(e)
      c f = frame(e) frame(e)
      Qua{a, b, c, f}

def leaves(+img: Image) -> Nat:
  match img:
    case Pix{c}:
      1n
    case Qua{tl, tr, bl, br}:
      Nat.add(leaves(tl),
        Nat.add(leaves(tr), Nat.add(leaves(bl),
          leaves(br))))
