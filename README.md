*English | [Русский](README.ru.md)*

# bend-night-train

**The Night Train on Bend 2** — a research project about the
[Bend 2](https://bend-lang.com/) language: affine dependent types, laws and
proofs, automatic parallelism on CPU and GPU.

The material is a self-contained WebGL demo, «Ночной поезд — из окна» (Night
train — from the window): a procedural track from two sine waves, a consist of
fifteen carriages, a night forest, stars, fog, light from the windows. It lives
in `reference/` and does not change. We rewrote it in Bend 2 not for the picture,
but to test by hand what the language is capable of — and to write that down.

![Night train](assets/frames/night-train-s150.png)

## Headline results

**1. Parallelism hits a ceiling long before the number of cores.**
Rendering a 1024×1024 frame on 32 cores speeds up by **2.7×**, while the total
CPU time grows by **8.2×**. At 32 threads the work goes slower than at 8. The
reason is uneven load: rays are traced in different numbers of steps, and the
scheduler does not park idle cores but spins them. Details and all the numbers:
`docs/benchmarks.md`. (These are CPU-lane numbers; the GPU-enabled
re-measurement is pending — see `docs/benchmarks.md`.)

**2. What is provable is not what it seems.**
The laws gate (`bend PROOF.bend`) passes, but proves **structure**: completeness
of the four-way parallel split, the number of carriages, the number of rays. The
numbers are unprovable in principle: all operations on `F32` are declared as
`law` without a body, so a pixel's colour, the camera position and "the frame
does not depend on the number of threads" cannot even be stated as a law.
Analysis with verbatim errors: `docs/laws.md`.

**3. `!` runs on the device, not on the CPU.**
On this host `!` is not a CPU fallback: the machine has an **RTX 4090 Laptop**
(driver 580.178.04, CUDA 13.0), `tools/bend` sets `CUDA_HOME=/usr` for the
distro CUDA 12 toolkit, `make build` emits `out/night-train.gpu`, and the `!`
call runs on the device even without `--gpu`; `--gpu 4GB` only bounds device
memory. The true CPU baseline is `NT_BANG=0`. CPU and device agree except for
last-bit F32 rounding (≤4/255 on about 0.15% of pixels), so their checksums may
differ. Determinism is measured: 108 runs, three depths, six values of
`--threads`, two call variants — one and the same result.

**4. The language checks a lot, but requires knowing the rules in advance.**
The list of thirteen errors actually caught is in `docs/journal.md`; the
systematic reference, assembled by a separate investigation, is in
`docs/language-notes.md` (1170 lines). The most unusual: mutual recursion is
forbidden, declaration order is part of the program, `match` is not an
expression, and only a parameter can be destructured.

## Quick start

```sh
make proof                  # laws gate: must be "All terms check."
make build                  # native binary via clang
make frame                  # 512x512 frame to out/frame.png
make bench                  # 108 runs, bench/results.csv

./tools/bend src/main.bend   # check and run on the JS backend
```

Useful environment variables — for the finished binary:

```sh
NT_DEPTH=10 NT_S=150 NT_SIDE=4.6 NT_PPM=0 ./out/night-train --threads 8
```

| | |
|---|---|
| `NT_DEPTH` | quadtree depth; frame `2^d × 2^d` |
| `NT_S` | position along the track, metres |
| `NT_SIDE` | camera's lateral offset from the track axis |
| `NT_PPM` | `1` — write `out/frame.ppm`, `0` — only compute |
| `NT_BANG` | `1` — render via `!`, `0` — with an ordinary parallel call |

`tools/bend` is a wrapper: in this environment `$HOME` is read-only, and a bare
`bend` cannot write to `~/.bend`.

The wrapper also **forbids `--publish`**. Bend's hub is a content-addressed store
with no accounts and no deletion: a published package stays public forever. Only
a human can lift the ban, by setting `BEND_ALLOW_PUBLISH=1`; an agent does not
do this.

## What's inside

| | |
|---|---|
| `src/scene.bend` | the world: track, consist, distances, tracing, lighting |
| `src/color.bend` | packing colour into `U32` for `Image` |
| `src/shape.bend` | the pixel-free frame skeleton — the laws are stated on it |
| `src/main.bend` | headless driver: frame, quadtree unfolding, PPM |
| `LAWS.bend` / `PROOF.bend` | laws and proofs, the commit gate |
| `docs/benchmarks.md` | numbers and their analysis |
| `docs/laws.md` | what is provable, what is not, and why |
| `docs/language-notes.md` | language reference, everything verified by running |
| `docs/reference-demo-spec.md` | what the original demo does, down to the constants |
| `docs/journal.md` | chronology: what broke and how it was fixed |
| `docs/base-2.0.5.txt` | dump of `bend base` for version 2.0.5 — API reference |
| `tools/order.py` | topological sort of `def`s: declaration order is mandatory |
| `tools/storyboard.py` | a series of frames along the track → GIF and MP4 |
| `tools/ppm2png.py` | PPM → PNG without libraries |
| `bench/` | benchmark driver and the exact measurer |

## How it is put together

A frame is an `Image` quadtree. Each level is built by one parallel call into
four parts:

```python
a b c f = Scene.frame(e, x, y, cam, cars)
  Scene.frame(e, x1, y, cam, cars)
  Scene.frame(e, x, y1, cam, cars)
  Scene.frame(e, x1, y1, cam, cars)
Qua{a, b, c, f}
```

This is the only place where the work is divided; everything else is pure
functions of coordinates. A pixel is a ray trace: analytic intersections with the
ground, the embankment, the rails and the carriages, round cones instead of fir
trees, a sky with stars and the moon, fog and tonemapping by the original's
formulas.

The ground, the forest and the carriages are reduced to the minimum sufficient
for a recognisable frame: no noise relief, no catenary poles, no villages. These
are deliberate simplifications, not unfinished parts — they are listed at the top
of `src/scene.bend`.

## What is not here

- **GPU speed-up numbers.** The device lane works (see result 3), but no GPU
  timing figures are claimed here: the site's "up to a hundred times on GPU" is
  not verified or asserted.
- **Comparison with hand-written C.** Bend already compiles to C; an honest
  comparison requires a C twin of the renderer.
- **An interactive window.** `App.run` exists in the language, but there is no
  window in this environment; everything is headless, the frame is written to
  PPM.

## License

MIT — see `LICENSE`. The original demo in `reference/` is the work of kvcop and
is distributed under the same terms.
