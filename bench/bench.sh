#!/usr/bin/env bash
# Benchmark driver for the night-train renderer.
#
# Times one frame at several depths, with and without the `!` GPU-tagged
# call, at several thread counts, and records wall and user time plus the
# frame checksum.  The checksum is the correctness check: it must be the same
# for every thread count and for both call forms, because the render is pure.
#
#   ./bench/bench.sh [binary] [csv]
#
# Columns: depth,bang,threads,rep,wall_s,user_s,checksum

set -uo pipefail

BIN=${1:-out/night-train}
OUT=${2:-bench/results.csv}
REPS=${REPS:-3}
DEPTHS=${DEPTHS:-"8 9 10"}
THREADS=${THREADS:-"1 2 4 8 16 32"}

mkdir -p "$(dirname "$OUT")"
echo "depth,bang,threads,rep,wall_s,user_s,checksum" > "$OUT"

run() {
  local d=$1 bang=$2 t=$3 rep=$4
  local tmp
  tmp=$(mktemp)
  NT_DEPTH="$d" NT_PPM=0 NT_BANG="$bang" \
    /usr/bin/time -f "%e %U" -o "$tmp" ./"$BIN" --threads "$t" > "$tmp.out" 2>/dev/null
  local chk wall user
  chk=$(tr -d '[:space:]' < "$tmp.out")
  read -r wall user < "$tmp"
  echo "$d,$bang,$t,$rep,$wall,$user,$chk" >> "$OUT"
  rm -f "$tmp" "$tmp.out"
}

# One warm-up pass so the first measurement is not the one that pays for
# parsing the binary and faulting in the heap.
NT_DEPTH=8 NT_PPM=0 NT_BANG=1 ./"$BIN" --threads 4 >/dev/null 2>&1

for d in $DEPTHS; do
  for bang in 0 1; do
    for t in $THREADS; do
      for rep in $(seq 1 "$REPS"); do
        run "$d" "$bang" "$t" "$rep"
        printf '.' >&2
      done
    done
  done
done
printf '\n' >&2
echo "wrote $OUT"
