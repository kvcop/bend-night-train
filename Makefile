# The bend wrapper keeps Bend's state inside the workspace: $HOME is
# read-only here, and a bare `bend` fails when it touches ~/.bend.
BEND := ./tools/bend
BIN := out/night-train

.PHONY: all proof check build run frame gpu bench compare clean

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

# The `!` render on the GPU.  A `!` program builds its device program next to
# the binary as out/night-train.gpu (see tools/bend for the CUDA discovery),
# and `--gpu` hands the quadtree to the device.  Same checksum as the CPU run
# at any thread count -- the render is pure.  See docs/benchmarks.md.
gpu: build
	NT_DEPTH=9 NT_PPM=1 $(BIN) --gpu 4GB --threads 8
	python3 tools/ppm2png.py out/frame.ppm out/frame-gpu.png

bench: build
	./bench/bench.sh $(BIN) bench/results.csv

# Compare the two renderers at one frozen camera: the Bend frame, the original
# WebGL demo rendered headlessly, and the numbers between them.
#
# Both cameras are pinned: NT_YAW/NT_PITCH freeze the head, and --lean 1 is the
# same ride lean the renderer computes at t=0.  Override the Bend environment
# with CAM= and the reference flags with REF=; keep NT_DEPTH and SIZE in step,
# they are the same frame in pixels.
CAM ?= NT_DEPTH=10 NT_S=110 NT_SIDE=4.6 NT_PPM=1 NT_YAW=0.0 NT_PITCH=-0.02
REF ?= --s 110 --lean 1 --yaw 0.0 --pitch -0.02
SIZE ?= 1024
CMP_DIR ?= out/compare
compare: build
	mkdir -p $(CMP_DIR)
	$(CAM) $(BIN) --threads 16
	python3 tools/ppm2png.py out/frame.ppm $(CMP_DIR)/bend.png
	python3 tools/render_reference.py --out $(CMP_DIR)/reference.png --size $(SIZE) $(REF)
	python3 tools/compare.py --bend $(CMP_DIR)/bend.png --ref $(CMP_DIR)/reference.png \
	  --outdir $(CMP_DIR) --title "Bend | reference (same camera)"

clean:
	rm -rf out
