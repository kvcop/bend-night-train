*English | [Русский](ru/laws.md)*

# Laws: what is actually provable in Bend 2

`LAWS.bend` holds the statements, `PROOF.bend` the proofs, `bend PROOF.bend` the
gate. They pass and print `All terms check.` in 0.25–0.34 s.

```sh
./tools/bend PROOF.bend
# All terms check.
```

This text is a report on where the boundary of the provable runs and why. The
boundary turned out not to be where I expected: it runs not between "complex"
and "simple", but between **structure and numbers**.

## 1. What is proved

### `consist_slots` — the consist's index sequence has exactly length k

```python
law consist_slots:
  for k: Nat
  {List.length(&2, Nat, Scene.slots(k)) == k : Nat}
```

The consist is built by walking `Scene.slots(k)`, the list `[k-1, …, 1, 0]`. A
carriage's geometry is F32 and unprovable (see §2), but **an off-by-one in the
carriage count** is checkable. The proof is induction on `k`; the step rests on
the fact that `List.length` of a cons is by definition `1n + length(tail)`:

```python
def Laws.consist_slots(k):
  match k:
    case 0n:
      {==}
    case 1n+p:
      %Laws.consist_slots(p) : {1n+List.length(&2, Nat, Scene.slots(p))
        == 1n+_ : Nat}
      {==}
```

For this law `Scene.consist` had to be split into `Scene.slots` (numbers) and
`Scene.consist.list` (geometry). This is not cosmetic: while the indices and the
sines lived in one function, the statement was inexpressible.

### `quad_pixels` — the four-way parallel split loses nothing

```python
law quad_pixels:
  for a: Image
  for b: Image
  for c: Image
  for e: Image
  {Shape.leaves(Qua{a, b, c, e}) == Nat.add(Shape.leaves(a), …) : Nat}
```

It is proved by reflexivity (`{==}`): this is literally the definition of
`Shape.leaves`. The value is not in the depth but in the fact that the law guards
**the cut point**: `Qua{a,b,c,e}` is exactly the node that the parallel call
`a b c e = frame(...) frame(...) frame(...) frame(...)` builds. If someone swaps
the order or drops a branch during a refactor, the law breaks.

### `frame8` — an 8×8 frame is exactly 64 rays

```python
law frame8:
  {Shape.leaves(Shape.frame(3n)) == 64n : Nat}
```

It is checked by evaluation: the checker unfolds the depth-3 quadtree into 64
leaves and counts them.

### The gate really is closed

Checked with a negative test: if in a copy of `LAWS.bend` you replace
`Shape.frame(3n)` with `Shape.frame(2n)`, the checker rejects it.

```
$ ./tools/bend probes/neg/PROOF_bad.bend
Error:
- expected : 16n
- observed : 64n
Location: LAWS_bad.frame8
```

## 2. What cannot be proved

### F32 is opaque

Let us try the simplest law about floating-point numbers:

```python
law f32_add_zero:
  for x: F32
  {F32.add(x, 0.0) == x : F32}
```

```
$ ./tools/bend probes/limits/PROOF_f32.bend
Error:
- expected : F32.add(x, 0.0)
- observed : x
Context:
- x : F32
```

The reason is visible in `bend base F32`: **all** operations on F32 are declared
as `law`, not `def`:

```
law F32.add:
  for a: F32
  for b: F32
  F32
```

A `law` has no body. The checker knows nothing about them and cannot simplify
anything except literally identical terms. So:

- a pixel's colour;
- the camera position;
- the values of `trackX`/`trackY`;
- "the frame does not depend on the number of threads";
- "brightness within [0,255]"

— all of this is **inexpressible** in current Bend 2. Not "hard to prove", but
impossible even to state as a law. That is precisely why `src/shape.bend`
appeared in `src/`: the laws about the frame are stated on its **skeleton** — the
same recursion with the same parallel call, but with `Pix{0}` instead of colour.
The structure is provable, the pixels are not.

The official demo confirms this too: `demos/app_ray_tracer_3d/LAWS.bend` begins
with the words "The F32 scene is not claimed" — the language's authors ran into
exactly the same wall.

### The general 4^d law runs into arithmetic Base does not have

The natural generalisation of `frame8` is "a depth-`d` frame contains exactly
4^d rays":

```python
law frame_pixels:
  for d: Nat
  {Shape.leaves(Shape.frame(d)) == Nat.pow(4n, d) : Nat}
```

The induction reaches the step and stops:

```
$ ./tools/bend probes/limits/PROOF_gen.bend
Error:
- expected : Nat.add(l, Nat.add(l, Nat.add(l, l)))
- observed : Nat.add(l, Nat.add(l, Nat.add(l, Nat.add(l, 0n))))
```

where `l` is `shape.leaves(shape.frame(p))`. The difference is exactly two
things: `Nat.add(l, 0n)` does not simplify to `l`, and the nesting of the
parentheses differs. That is, two lemmas are missing: `x + 0 = x` and
associativity.

Base does not have them: `bend base Nat` shows the definitions of `add`, `mul`,
`pow`, `double`, but **not a single lemma** about their algebra. The official
answer to this is the `demos/proof_numerics` demo: it redefines `add`/`mul` and
proves `add_comm`, `add_assoc`, `mul_comm`, `mul_dist`. There is no other way:
Bend has no tactics, no rewrite search, every associativity step is written by
hand.

The practical conclusion for law-driven development: **any program that contains
arithmetic first pays for an arithmetic library**. For our renderer this would
mean: prove `x+0=x`, associativity, then generalise `frame8` to `4^d`. The three
laws that exist now do not require that payment — they rest on the structure of
the list and the tree.

## 3. What this means

| | provable | unprovable |
|---|---|---|
| frame shape, number of rays | yes | |
| completeness of the parallel split | yes | |
| number of carriages | yes | |
| colours, lighting, fog | | F32 is opaque |
| camera position and track | | F32 is opaque |
| `4^d` in the general case | | no algebra of Nat in Base |
| determinism across threads | | a consequence of F32 |

The last row is a separate irony. The renderer's determinism is **measured** (see
`docs/benchmarks.md`: 108 runs, the same checksum at any thread count), but **not
proved**: to state it you would need equations over F32 values, and the checker
does not have them.

The result is an honest picture for this project: the laws gate catches errors of
**structure** — a lost quadtree branch, an extra or missing carriage, broken
recursion — and does not catch errors in **numbers**. That is far more than
nothing, but noticeably less than the word "proof" on the cover promises.
