#!/usr/bin/env bash
# Benchmark driver for the night-train renderer.
#
# Times one frame at several depths, on the CPU or the GPU backend, with and
# without the `!` GPU-tagged call, at several thread counts, and records wall
# and user time plus the frame checksum.  The checksum is the correctness
# check: it must be the same for every backend, thread count and call form,
# because the render is pure.
#
#   ./bench/bench.sh [binary] [csv]
#   ./bench/bench.sh --backend gpu --depth 9 --threads 8 --reps 5
#
# Backends:
#   cpu  run the binary as built (default), no `--gpu` flag
#   gpu  add `--gpu 4GB` (or --gpu-mem N) to the invocation
#
# The `backend` column records which of those two invocations ran; it is NOT
# where the work ran.  On this host the CUDA build gives the `!` call a device
# lane that it takes even without `--gpu`, while `--gpu` on a bang=0 program
# is inert.  The real CPU/device split is the `bang` column.  See
# bench/README.md.
#
# `--gpu` changes nothing when the source has no `!` call, so the gpu backend
# records `bang=1` rows only.  A bang=0 row under `--gpu` would be a CPU run
# carrying a flag that does nothing -- not a GPU measurement.
#
# Configuration (flags override the env defaults):
#   BACKEND=cpu|gpu   DEPTHS="8 9 10"   THREADS="1 2 4 8 16 32"
#   REPS=3            BANGS="0 1"        GPU_MEM=4GB
#
# `bang` selects the source call form (NT_BANG): 0 = plain parallel call, a
# true CPU baseline; 1 = the `!` call.
#
# A single cell is just one depth and one thread count, e.g. re-measure
# depth 10 with 8 threads on the GPU, five reps, into its own file:
#
#   ./bench/bench.sh --backend gpu --depth 10 --threads 8 --reps 5 \
#     --out bench/results-gpu.csv
#
# Columns: depth,bang,threads,rep,wall_s,user_s,checksum,backend

set -uo pipefail

BIN=${BIN:-out/night-train}
OUT=${OUT:-bench/results.csv}
BACKEND=${BACKEND:-cpu}
REPS=${REPS:-3}
DEPTHS=${DEPTHS:-"8 9 10"}
THREADS=${THREADS:-"1 2 4 8 16 32"}
BANGS=${BANGS:-"0 1"}
GPU_MEM=${GPU_MEM:-4GB}

usage() { sed -n '2,40p' "$0"; }

positional=()
while [ $# -gt 0 ]; do
  case "$1" in
    --backend)   BACKEND=$2; shift 2 ;;
    --backend=*) BACKEND=${1#*=}; shift ;;
    --gpu-mem)   GPU_MEM=$2; shift 2 ;;
    --gpu-mem=*) GPU_MEM=${1#*=}; shift ;;
    --bang)      BANGS=$2; shift 2 ;;
    --bang=*)    BANGS=${1#*=}; shift ;;
    --depth)     DEPTHS=$2; shift 2 ;;
    --depth=*)   DEPTHS=${1#*=}; shift ;;
    --threads)   THREADS=$2; shift 2 ;;
    --threads=*) THREADS=${1#*=}; shift ;;
    --reps)      REPS=$2; shift 2 ;;
    --reps=*)    REPS=${1#*=}; shift ;;
    --out)       OUT=$2; shift 2 ;;
    --out=*)     OUT=${1#*=}; shift ;;
    -h|--help)   usage; exit 0 ;;
    -*)          echo "bench.sh: unknown option $1" >&2; usage >&2; exit 2 ;;
    *)           positional+=("$1"); shift ;;
  esac
done

if [ "${#positional[@]}" -ge 1 ]; then BIN=${positional[0]}; fi
if [ "${#positional[@]}" -ge 2 ]; then OUT=${positional[1]}; fi

case "$BACKEND" in
  cpu) GPU_ARGS=() ;;
  gpu) GPU_ARGS=(--gpu "$GPU_MEM"); BANGS=1 ;;
  *) echo "bench.sh: --backend must be cpu or gpu, got '$BACKEND'" >&2; exit 2 ;;
esac

# `run()` prefixes a relative binary with ./; keep an absolute path as-is.
case "$BIN" in /*) ;; *) BIN="./$BIN" ;; esac

mkdir -p "$(dirname "$OUT")"
echo "depth,bang,threads,rep,wall_s,user_s,checksum,backend" > "$OUT"

run() {
  local d=$1 bang=$2 t=$3 rep=$4
  local tmp
  tmp=$(mktemp)
  NT_DEPTH="$d" NT_PPM=0 NT_BANG="$bang" \
    /usr/bin/time -f "%e %U" -o "$tmp" "$BIN" "${GPU_ARGS[@]+"${GPU_ARGS[@]}"}" \
    --threads "$t" > "$tmp.out" 2>/dev/null
  local chk wall user
  chk=$(tr -d '[:space:]' < "$tmp.out")
  read -r wall user < "$tmp"
  echo "$d,$bang,$t,$rep,$wall,$user,$chk,$BACKEND" >> "$OUT"
  rm -f "$tmp" "$tmp.out"
}

# One warm-up pass so the first measurement is not the one that pays for
# parsing the binary, faulting in the heap, or loading the device module.
warm_depth=${DEPTHS%% *}
NT_DEPTH="$warm_depth" NT_PPM=0 NT_BANG=1 "$BIN" \
  "${GPU_ARGS[@]+"${GPU_ARGS[@]}"}" --threads 4 >/dev/null 2>&1

for d in $DEPTHS; do
  for bang in $BANGS; do
    for t in $THREADS; do
      for rep in $(seq 1 "$REPS"); do
        run "$d" "$bang" "$t" "$rep"
        printf '.' >&2
      done
    done
  done
done
printf '\n' >&2
echo "wrote $OUT ($BACKEND)"
