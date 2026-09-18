# The bend wrapper keeps Bend's state inside the workspace: $HOME is
# read-only here, and a bare `bend` fails when it touches ~/.bend.
BEND := ./tools/bend
BIN := out/night-train

.PHONY: all proof check build run frame bench clean

all: proof build

# The gate.  Must print "All terms check." before anything is committed.
proof:
	$(BEND) PROOF.bend

# Type-check everything the program imports without running it.
check:
	$(BEND) src/main.bend -o out/night-train.c

build:
	mkdir -p out
	$(BEND) src/main.bend -o $(BIN)

# Depth 9 is 512x512.  16 threads, not 32: past 16 the wall clock stops
# improving and the CPU burn triples.  See docs/benchmarks.md.
run: build
	NT_DEPTH=9 $(BIN) --threads 16

frame: build
	NT_DEPTH=9 NT_PPM=1 $(BIN) --threads 16
	python3 tools/ppm2png.py out/frame.ppm out/frame.png

bench: build
	./bench/bench.sh $(BIN) bench/results.csv

clean:
	rm -rf out
