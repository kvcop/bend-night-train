# bench/ — the CPU/GPU timing harness

`bench.sh` times one rendered frame at several depths, call forms, thread
counts and backends, and records wall time, CPU time and the frame checksum.
`measure.py` times a single command with `perf_counter` + `getrusage` and
reports the median of N runs — use it when centisecond `/usr/bin/time`
resolution is too coarse, or to see the CPU/wall ratio that exposes a
spinning scheduler.

Build first; `make build` emits both the CPU binary and, on this host, its
`out/night-train.gpu` device program.

```sh
make build
```

## Columns

`results.csv` and `results-gpu.csv` share one schema:

| column | meaning |
|---|---|
| `depth` | quadtree depth `d`; the frame is `2^d × 2^d` pixels (`NT_DEPTH`) |
| `bang` | source call form (`NT_BANG`): `0` plain parallel call, `1` the `!` call |
| `threads` | value passed to `--threads` |
| `rep` | 1-based repetition within this cell |
| `wall_s` | wall-clock seconds for the run (`/usr/bin/time %e`) |
| `user_s` | child CPU seconds (`/usr/bin/time %U`); the CPU/wall ratio is `user_s / wall_s` |
| `checksum` | the frame digest printed on stdout; the correctness check |
| `backend` | which invocation ran: `cpu` (no `--gpu` flag) or `gpu` (`--gpu 4GB`) |

Every run writes `NT_PPM=0`, so the timed section is the render, not PPM I/O.

## `backend` is the flag, `bang` is where the work runs

On this host the CUDA build gives the `!` call a device lane, and `!` takes
it **even without `--gpu`** — the binary loads (or, if absent, recompiles)
its `<binary>.gpu` companion at startup.  `--gpu 4GB` only bounds the device
memory budget; it does not switch the lane on.  A `bang=0` program ignores
`--gpu` entirely.

So `backend` records the invocation, not the compute location:

- **true CPU baseline** — `bang=0`.
- **device** — `bang=1`, with or without `--gpu`.
- `backend=gpu` forces `bang=1` and adds `--gpu 4GB`; a `bang=0` row under
  `--gpu` would be a CPU run carrying a flag that does nothing.

Evidence for the lane, depth 9 (`measure.py`, this host): `bang=1` reports
`cpu/wall ≈ 1.2×` at any thread count, while `bang=0` at 8 threads reports
`cpu/wall ≈ 6.8×`.  The `!` lane's host CPU time does not grow with
`--threads`, so the rays are not being traced on the CPU.

## Full sweep

```sh
REPS=3 ./bench/bench.sh out/night-train bench/results.csv            # CPU baseline + ! lane
REPS=3 ./bench/bench.sh --backend gpu out/night-train bench/results-gpu.csv
```

Defaults: `DEPTHS="8 9 10"`, `THREADS="1 2 4 8 16 32"`, `BANGS="0 1"`,
`REPS=3`.  Every knob is also a flag; flags override the environment.

## One cell (`depth`, `backend`, `threads`, `reps`)

Re-measure a single cell without the full 108-run sweep:

```sh
# depth 10, 8 threads, 5 reps, device, into its own file
./bench/bench.sh --backend gpu --depth 10 --threads 8 --reps 5 \
  --out bench/results-gpu.csv

# the same number with perf_counter resolution, no CSV
python3 bench/measure.py --backend gpu --env NT_DEPTH=10 --env NT_PPM=0 \
  --reps 5 -- ./out/night-train --threads 8

# the true CPU baseline for that cell
python3 bench/measure.py --env NT_DEPTH=10 --env NT_PPM=0 --env NT_BANG=0 \
  --reps 5 -- ./out/night-train --threads 8
```

`--depth` and `--threads` take one value (single cell) or a quoted list
(sweep).  `--bang 0` / `--bang 1` restrict the call form, `--out FILE`
picks the CSV, and the first two positional arguments remain `binary` and
`csv`, so existing `make bench` invocations keep working.

## Adding a GPU row

1. `make build` — confirm `out/night-train.gpu` exists.  If the build lacked
   CUDA (wrong `clang`, no `nvrtc.h` under `$CUDA_HOME`), the file is absent
   and `--gpu` fails with `this binary found no GPU device`; `tools/bend`
   sets `CUDA_HOME=/usr` on this host.
2. Run a cell with `--backend gpu`, or a full sweep with
   `--backend gpu ... --out bench/results-gpu.csv`.
3. Check the `checksum` column matches the `bang=1` CPU-invocation rows for
   the same depth.  If it does not, the render is not pure and the number is
   not publishable.

## Correctness check

The render is pure, so the checksum must not depend on thread count or on
which lane executes it.  Verified for depths 8, 9 and 10 — CPU invocation
`--threads 1`, CPU invocation `--threads 8`, and `--gpu 4GB --threads 8`,
all with `NT_BANG=1`:

| depth | pixels | `--threads 1` | `--threads 8` | `--gpu 4GB --threads 8` |
|---|---|---|---|---|
| 8 | 65 536 | 3185618221 | 3185618221 | 3185618221 |
| 9 | 262 144 | 2158427939 | 2158427939 | 2158427939 |
| 10 | 1 048 576 | 13924308 | 13924308 | 13924308 |

`bang=0` runs give the same three digests, so the CPU lane agrees too.  The
digest is an order-independent XOR fold, so equal digests prove the same
*set* of pixels, not their positions; placement is checked visually.

## Publishing numbers

Only numbers from a quiet host are publishable.  While other builds or
renders run in parallel, wall time is contended: record such a run in
`bench/out/` (`/bench/out/` is gitignored) with `contended` in the filename,
never in `bench/results*.csv`.
