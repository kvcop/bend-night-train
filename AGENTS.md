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

This machine has **no GPU and no CUDA**, and clang 18 (the guide asks for 19+
when `!` is present, but `!` builds still succeed here and run on the CPU).

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
