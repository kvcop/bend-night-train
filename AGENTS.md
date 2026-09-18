# AGENTS.md — bend-night-train

Research project: a **Bend 2** language study, built around a translation of the
WebGL demo «Ночной поезд — из окна» into Bend 2. The port is the vehicle; the
deliverable is knowledge about the language.

When using Bend:
- run `bend guide` to learn it
- use `LAWS.bend` to keep important rules
- run `bend PROOF.bend` before committing
- parallelize the code whenever possible

## Ground rules

- **Parallelize by default.** Bend's only concurrency primitive is the parallel
  let (`a b = f(x) g(y)`) and the `!` GPU/CPU-parallel call. Any pure work that
  splits into independent halves must be written as a parallel call. Sequential
  code must be justifiable: divergent control flow, a single reduction, or a
  measurement baseline.
- **Laws before features.** A property that must never break belongs in
  `LAWS.bend` (human-owned, never weakened to make a build pass) and is proven
  in `PROOF.bend`. Never edit a law to accommodate an implementation bug; fix
  the implementation or report the law as unprovable and explain why.
- **`bend PROOF.bend` is the gate.** It must print `All terms check.` before
  anything is committed. A proof left as `?TODO` is a commit blocker unless the
  commit message says which law is open and why.
- **Measure, don't claim.** Every performance statement in `docs/` must have a
  command the reader can re-run and a recorded number produced by it.

## Toolchain

The shell is sandboxed and `$HOME` is read-only, so a bare `bend` fails when it
tries to touch `~/.bend`. Always use the wrapper:

```sh
./tools/bend <file.bend>              # type-check, then run on the JS backend
./tools/bend <file.bend> -o out       # native binary (clang)
./tools/bend <file.bend> -o out.c     # emit C
./tools/bend <file.bend> -o out.js    # emit JS
./tools/bend PROOF.bend               # the laws gate
```

`tools/bend` sets `BEND_HOME` inside the workspace and disables telemetry.

The host has an **RTX 4090 Laptop (16 GB, driver 580.178.04, CUDA 13.0)** --
but the default `workspace-write` sandbox does not pass `/dev/nvidia*` into the
shell, so `nvidia-smi` fails there and `!` runs on the CPU.  Under wider sandbox
access the device is visible.  Before ever claiming there is no GPU, check
`lspci` and `/proc/driver/nvidia/gpus/`: their absence, not `nvidia-smi`, is
what would mean it.

Toolchain: clang 18 (the guide asks for 19+ when `!` is present; 18 still
builds), and `nvcc` 12.0 at `/usr/bin/nvcc` -- note there is **no**
`/usr/local/cuda`, which is where the guide says Linux GPU builds look.

## Never publish

`tools/bend` refuses `--publish`, and so should you.  hub.bend-lang.com has no
accounts, no names and no versions: a package is named by the hash of its
contents and served immutable, so there is nothing to delete it with.  Anything
uploaded stays public for good.  The guard can be lifted with
`BEND_ALLOW_PUBLISH=1`, and **only a human may set it** -- an agent must not,
not even to "test" the publish path.

The general rule behind this one: anything irreversible that leaves this
machine -- publishing, pushing to a registry, sending mail, opening a public
issue -- happens only because the human asked for it, in words, in the current
conversation.  Not because a past summary said the toolchain should be probed.

## Layout

- `src/` — the Bend implementation (`scene.bend`, `render.bend`, `frames.bend`).
- `LAWS.bend`, `PROOF.bend` — the laws gate at the repo root, by convention.
- `bench/` — benchmark drivers and their raw output.
- `docs/` — research output: `journal.md` (chronological), `language-notes.md`
  (verified language behaviour), `reference-demo-spec.md` (what the original
  WebGL demo does), `benchmarks.md` (numbers), `laws.md` (what is provable).
- `reference/` — the original HTML demo, kept verbatim for provenance.
- `tools/` — the `bend` wrapper and small scripts.

## Writing

- User-facing documents (`README.md`, `docs/**`) are **Russian**.
- Code comments, `AGENTS.md`, and commit messages are **English**.
- `docs/journal.md` is append-only: every session adds a dated entry with what
  was tried, what worked, what broke, and the exact command that showed it.

## Commits

- One logical change per commit; `bend PROOF.bend` must pass first.
- Never `--no-verify`.
