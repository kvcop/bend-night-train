*English | [Русский](ru/journal.md)*

# Journal

A chronology of the work: what we tried, what broke, how we fixed it. Errors are
quoted verbatim — that is what people search for later. The detailed reference on
the language, gathered by a separate investigation, lives in
`docs/language-notes.md`; here there is only what this project stumbled over.

## 2026-09-18

### Installation and the stand

`curl -fsSL https://bend-lang.com/install.sh | sh` installed Bend 2.0.5. The
launcher writes its state to `~/.bend` (`rep`, `last`, `id`), and this working
environment keeps `$HOME` read-only, so every run printed
`cannot create /home/user/.bend/last`. We made `tools/bend` — a wrapper that
moves `BEND_HOME` inside the working copy and disables telemetry.

Checked straight away: `!` (the GPU call) built with clang 18, although the guide
asks for 19+; no `.gpu` file was created. The cause is a silent CPU-only build
under clang 18, not a missing GPU — the host has an RTX 4090 Laptop. The CUDA
setup and the two easy-to-confuse failure modes are written out in `AGENTS.md`.

### Laws and proofs: the gate works

The first thing we assembled was the minimal `LAWS`/`PROOF` pair from the guide
(`add_zero` on `Nat`). `All terms check.` — and, more importantly, a deliberately
wrong law fails with a clear message:

```
- expected : Nat.add(x, 1n)
- observed : x
```

That is the main reason the language is interesting at all: an error prints
`expected`/`observed` and a location, not "type mismatch".

### The port: what broke and why

We wrote the renderer incrementally, compiling after every step. Below are the
errors in the order they appeared. Almost every one is not a "bug" but a
consequence of a rule you have to know in advance.

**1. Operators without an annotation belong to `Nat`.**
`F32.abs(px - tx : F32)` — error `expected : a term / observed : ':'`. The
annotation must be in parentheses: `F32.abs((px - tx : F32))`. And conversely,
`(a : F32) * b` is also wrong: `*` ends up **outside** the annotation and goes to
`Nat`. The rule: every arithmetic argument of a call and every arithmetic body of
a `def` is wrapped in `( … : T )` as a whole.

**2. `>=` comparisons inside `( … : Bool )`.**
`(ax >= ay : Bool)` is expanded by the compiler into `Bool.is_ge`, which does not
exist: `expected : a defined name / observed : Bool.is_ge`. A comparison on F32
must be named explicitly: `F32.is_ge(ax, ay)`. The `: Bool` parentheses are only
needed for `&&`/`||`.

**3. Destructuring — parameter only.**
Three different errors in a row:

```
- a match cannot scrutinize a computed value: give it its own def
- a match cannot scrutinize a local binder: give it its own def
```

That is, `V3{x, y, z} = call()` and `V3{x, y, z} = local` are forbidden, while
`V3{x, y, z} = parameter` is allowed. The workaround: accessor functions
(`V3.px`, `V3.py`, `V3.pz`) or a separate `def` with the right parameter.

**4. `let` before a `match` on a parameter.**
`+h2 = …` then `match up:` →
`match scrutinees in binder order (this variable is unbound, consumed, or out
of order: reorder the match)`. First `match`, then `let` inside the branch.

**5. Mutual recursion is forbidden, and this breaks the usual refactoring.**
The most expensive finding. We wanted to move the `Bool` dispatch into a
separate `def`:

```python
def march(...):
  march.if(stop, ...)          # not allowed
def march.if(stop, ...):
  march(...)                   # and this is not allowed either
```

`expected : a defined name / observed : Scene.march.if` — definitions must come
**before** use, and the "wrapper ↔ helper" pair forms a cycle. The right way is a
nested `match` in a single `def` that takes the `Bool` **as a parameter**:

```python
def march(+i: Nat, +stop: Bool, …):
  match i:
    case 0n: t
    case 1n+k:
      match stop:
        case True{}: t
        case False{}: … march(k, …)   # itself — allowed
```

The same had to be done when walking a quadtree row (`Px.row`).

**6. A multi-scrutinee `match` requires all combinations.**
`match d img:` with branches `0n Pix{c}` and `1n+e Qua{…}` fails:
`expected : cases for Qua`. All four combinations are needed, or (simpler)
`match`es nested in each other.

**7. `match` is not an expression.**
In a `do` block:
`expected : a term (a match heads a def body, not a term)`.
The cure is to move it into a separate `def`.

**8. `do` block: a `let` without an annotation breaks the block silently.**
```python
do IO<Unit>:
  +v = F.c(1, 2)      # the block ends here
  IO.print(...)        # expected 'def', 'type' or 'law', observed 'I'
  IO.print(...)        # and this is already outside the block
```
With `v : U32 = F.c(1, 2)` the same block works. Separately: **tuple
destructuring in `do` is not a statement.** `(f, r) = fr` is parsed as the
block's return value, and the block's tail falls off. The cure is to move the
unpacking into a `def` where the tuple is a parameter.

**9. Name algebra on import.**
`import ./scene.bend as Scene` gives access to the name `Scene.` + the **full**
name of the `def`. That is, `import ./color.bend as Color` and `def Color.pack`
give `Color.Color.pack`, while the short `Color.pack` gives
`expected : a defined name`. We had to drop the inner prefixes: in `color.bend`
it is `pack`, `red`, `green`, and outside it is `Color.pack`.

**10. Argument types of shifts.**
`U32.shln(a: U32, n: Nat)`, `U32.shrn(a: U32, n: Nat)`. The literal `1` is
`U32`, so `U32.shrn(half, 1)` does not compile: you need `1n`.

**11. Declaration order is part of the program.**
After every edit we had to reorder `def`s, so `tools/order.py` appeared: it
builds a reference graph between a file's top-level items and sorts them
topologically, and on a cycle it prints the guilty chain. It was precisely this
that caught `Px.row → Px.row.sel → Px.row`.

**12. Syntax trivia, each costing one compilation.**
- `Qua{tl: a, tr: b, …}` — named fields in a constructor are not supported, only
  positional: `Qua{a, b, c, f}`.
- `def Laws.frame8:` — parentheses needed: `def Laws.frame8():`.
- Equality in a `law` must be on one line: a line break inside `{ … : Nat}` gives
  `expected : a term / observed : ':'`.

**13. Affine use is the most common error.**
`expected : cars / observed : cars (consumed more than once)`. Everything used
twice is marked `+`: parameters (`+cars`), fields in a pattern
(`Car{+cc, +ss, …}`), bindings (`+img : Image = …`). At the same time `+`
requires `Data`: it cannot be put on a function.

### What came out of it

The first frame came out white: `Cam.fit` rewrote the camera but took `cx`/`cy`
(the screen centre) from the **input** camera, where they are zero — division by
zero gave `dir=nan,nan,nan`, and `F32.clamp` of NaN returned 1.0, that is, white.
The second frame came out flipped: the PPM rows were assembled from last to
first, while `++` appends to the end. Both errors were found in a single run,
because the renderer prints a checksum and dumps the PPM — there was something to
look at.

### The day's outcome

- `bend PROOF.bend` → `All terms check.` in 0.25–0.34 s.
- 108 benchmark runs: the same checksum at any thread count and with both call
  variants.
- Speed-up on 32 cores — 2.7×, while total CPU grows 8×. (These are CPU-lane
  numbers from before the device lane was set up; the GPU-enabled re-measurement
  is pending — see `docs/benchmarks.md`.)
- The overall picture on provability is in `docs/laws.md`: the structure is
  checked, the numbers are not.

### Publishing to the hub: how one process mistake got out

The agent writing `docs/language-notes.md`, while investigating the toolchain,
ran `bend tiny.bend --publish`. The file is 79 bytes, `import Base` and
`IO.print("compile me")`, nothing project-related. But it **stayed in the public
hub forever**:
`https://hub.bend-lang.com/0xdc5e239cf0bf288e1735d5852f820f34/tiny.bend`.

It cannot be revoked by the service's design, not by an oversight: "no accounts,
no names, no versions", responses are served with `cache-control: immutable`, and
there is no identity that could authorise deletion. The client has no inverse
operation.

What was done: `tools/bend` now refuses `--publish` (exit code 2) and allows it
only with `BEND_ALLOW_PUBLISH=1`, which a human sets. The rule is written in
`AGENTS.md`.

What was done wrong: a subagent got access to a tool with an irreversible public
action, and there was no guard on it. That it was a harmless hello that flew out
is luck.
