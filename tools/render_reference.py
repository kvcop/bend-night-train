#!/usr/bin/env python3
"""Render the original WebGL night-train demo headlessly at a frozen camera.

The reference demo is an animation: its state advances every rAF and its
particle fields are seeded with ``Math.random``.  Neither is reproducible, so
this tool renders a *patched copy* of ``reference/night-train-webgl.html``
(never the original) with two changes:

  1. a seeded PRNG replaces ``Math.random`` before the demo script runs, so
     every particle, mote and smoke seed is identical on every run; and
  2. a ``window.__nt`` hook is appended inside the demo's IIFE that stops the
     rAF loop, writes the requested camera state, draws a single frame at
     ``dt = 0`` and returns ``canvas.toDataURL('image/png')``.

The result is deterministic: the same arguments produce byte-identical PNGs.

Camera convention
-----------------
The CLI flags map one-to-one onto the reference's own ``state`` fields:

  --s                -> state.s      position along the track (metres); 110
  --lean             -> state.lean   how far the head hangs out of the
                                     window; the demo turns it into the
                                     camera's lateral offset from the
                                     centreline::

                                       sideOffset = -2.15 - lean*2.45

                                     so lean=1 (the demo default) is
                                     ``sideOffset = -4.60`` metres.  The sign
                                     is the demo's: negative is toward the
                                     window side, i.e. the camera sits *left*
                                     of the centreline.
  --yaw              -> state.yaw    head turn off the track tangent, radians
  --pitch            -> state.pitch  head pitch, radians (default -0.02)
  --t                -> state.t      animation clock in seconds (particle
                                     phase only; the camera does not move)
  --motion/--no-motion -> state.motion
                                     sway/bob and sloshing particles; frozen
                                     (off) by default so the camera is a still
  --quality high|low -> state.quality
                                     scene density (tree count, detail step)

The demo's own defaults are ``s=110, lean=1, yaw=0, pitch=-0.02, motion=true``
with ``quality`` auto.  A square frame is used because the demo picks
``fovy = W<H ? 1.20 : 1.12`` and the Bend renderer's ``S.fovy()`` is 1.12.

Usage::

  tools/render_reference.py --out out/ref.png --s 110 --lean 1 --info
  tools/render_reference.py --out out/ref.png --size 512 --quality low
"""

from __future__ import annotations

import argparse
import base64
import json
import pathlib
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
REFERENCE = ROOT / "reference" / "night-train-webgl.html"

# Fixed seed: the render is only reproducible if the particle fields are.
SEED = 0x9E3779B9

# Injected before the demo's own <script>, so the seeding happens before the
# demo builds its motes/smoke arrays.
SEED_SCRIPT = """
<script>
// Seeded PRNG installed before the demo script: every Math.random() call in
// the demo (motes, smoke, reset positions) must be reproducible.
(function(){
  var a = %d >>> 0;
  Math.random = function(){
    a = (a + 0x6D2B79F5) >>> 0;
    var t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
})();
</script>
<script>
""" % SEED

# Appended inside the demo's IIFE, replacing the line that would start the rAF
# loop.  `rafId=0` at the end of frame() is handled by the other replacement.
HOOK = """
window.__nt = {
  render: function(opts){
    opts = opts || {};
    var s = (opts.s === undefined) ? state.s : opts.s;
    var t = (opts.t === undefined) ? 0 : opts.t;
    var lean = (opts.lean === undefined) ? 1 : opts.lean;
    var yaw = (opts.yaw === undefined) ? 0 : opts.yaw;
    var pitch = (opts.pitch === undefined) ? -0.02 : opts.pitch;
    state.quality = (opts.quality === undefined) ? 'high' : opts.quality;
    state.speed = 0; state.motion = !!opts.motion;
    state.s = s; state.t = t;
    state.lean = lean; state.leanTarget = lean;
    state.yaw = yaw; state.yawTarget = yaw;
    state.pitch = pitch; state.pitchTarget = pitch;
    state.autoLook = false; state.headOn = true;
    if (rafId){ cancelAnimationFrame(rafId); rafId = 0; }
    state.last = 1e-9;          // truthy, and now - last = 0 => dt = 0
    frame(1e-9);
    rafId = 0;                  // a frozen frame must not re-arm the loop
    return canvas.toDataURL('image/png');
  },
  info: function(){
    var sideOffset = -2.15 - state.lean * 2.45
                     + (state.motion ? Math.sin(state.t * .31) * .12 : 0);
    return {s: state.s, yaw: state.yaw, pitch: state.pitch, W: W, H: H,
            fovy: (W < H ? 1.20 : 1.12), lean: state.lean,
            sideOffset: sideOffset, t: state.t, motion: state.motion,
            quality: state.quality, cars: CARS, behind: CARS_BEHIND,
            ahead: CARS_AHEAD};
  }
};
"""


def patch(html: str) -> str:
    """Return the demo HTML with the seeded PRNG and the __nt hook installed."""
    if "<script>" not in html:
        raise SystemExit("reference HTML: no <script> tag found")
    seeded = html.replace("<script>", SEED_SCRIPT, 1)

    # frame() must not re-arm the loop; it used to schedule the next frame.
    if "rafId=requestAnimationFrame(frame);" not in seeded:
        raise SystemExit("reference HTML: frame() re-arm line not found")
    stopped = seeded.replace("rafId=requestAnimationFrame(frame);", "rafId=0;", 1)

    # The auto-start at the end of the IIFE becomes the hook definition.
    start = "window.__train3d = state;\nrafId=requestAnimationFrame(frame);\n})();"
    if start not in stopped:
        raise SystemExit("reference HTML: IIFE start line not found")
    return stopped.replace(start, "window.__train3d = state;" + HOOK + "\n})();", 1)


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", required=True, help="output PNG path")
    ap.add_argument("--s", type=float, default=110.0, help="state.s (track position)")
    ap.add_argument("--lean", type=float, default=1.0, help="state.lean (window lean; 1 => sideOffset -4.60)")
    ap.add_argument("--yaw", type=float, default=0.0, help="state.yaw (head turn, rad)")
    ap.add_argument("--pitch", type=float, default=-0.02, help="state.pitch (head pitch, rad)")
    ap.add_argument("--t", type=float, default=0.0, help="state.t (animation clock, s)")
    ap.add_argument("--size", type=int, default=1024, help="square frame size, px")
    ap.add_argument("--motion", dest="motion", action="store_true", default=False,
                    help="keep sway/bob on (default: frozen, no motion)")
    ap.add_argument("--no-motion", dest="motion", action="store_false",
                    help="freeze sway/bob (default)")
    ap.add_argument("--quality", choices=("high", "low"), default="high",
                    help="scene density")
    ap.add_argument("--info", action="store_true",
                    help="print the frozen camera (s, yaw, pitch, W, H, fovy) as JSON")
    args = ap.parse_args(argv)

    if args.size <= 0:
        ap.error("--size must be positive")

    try:
        from playwright.sync_api import sync_playwright
    except ImportError as exc:  # pragma: no cover - environment guard
        raise SystemExit(f"render_reference: playwright is required: {exc}")

    if not REFERENCE.is_file():
        raise SystemExit(f"render_reference: missing {REFERENCE}")
    patched = patch(REFERENCE.read_text(encoding="utf-8"))

    out = pathlib.Path(args.out).resolve()
    out.parent.mkdir(parents=True, exist_ok=True)

    tmpdir = pathlib.Path(tempfile.mkdtemp(prefix="nt-reference-"))
    html_path = tmpdir / "night-train-webgl.patched.html"
    html_path.write_text(patched, encoding="utf-8")

    opts = {"s": args.s, "lean": args.lean, "yaw": args.yaw,
            "pitch": args.pitch, "t": args.t, "motion": args.motion,
            "quality": args.quality}

    console: list[str] = []
    try:
        with sync_playwright() as pw:
            browser = pw.chromium.launch(args=[
                "--enable-unsafe-swiftshader",
                "--use-gl=angle",
                "--use-angle=swiftshader",
            ])
            try:
                page = browser.new_page(
                    viewport={"width": args.size, "height": args.size},
                    device_scale_factor=1,
                )
                page.on("console", lambda m: console.append(f"{m.type}: {m.text}"))
                page.on("pageerror", lambda e: console.append(f"pageerror: {e}"))
                page.goto(html_path.as_uri())
                page.wait_for_timeout(1500)

                webgl = page.evaluate(
                    "() => { const c = document.getElementById('gl');"
                    " if (!c) return 'no canvas';"
                    " const g = c.getContext('webgl2');"
                    " return g ? 'ok' : 'no webgl2'; }")
                if webgl != "ok":
                    raise SystemExit(
                        "render_reference: WebGL2 is unavailable (%s). "
                        "Full console output:\n  %s"
                        % (webgl, "\n  ".join(console) or "(empty)"))

                if not page.evaluate("() => !!window.__nt"):
                    raise SystemExit(
                        "render_reference: the __nt hook did not install; the demo "
                        "probably failed to start. Full console output:\n  %s"
                        % ("\n  ".join(console) or "(empty)"))

                data_url = page.evaluate("(o) => window.__nt.render(o)", opts)
                info = page.evaluate("() => window.__nt.info()")
            finally:
                browser.close()
    finally:
        html_path.unlink(missing_ok=True)
        tmpdir.rmdir()

    if not isinstance(data_url, str) or "," not in data_url:
        raise SystemExit("render_reference: render returned no PNG data URL")
    raw = base64.b64decode(data_url.split(",", 1)[1])
    out.write_bytes(raw)

    if (info.get("W"), info.get("H")) != (args.size, args.size):
        print("render_reference: warning: frame is %sx%s, expected %sx%s"
              % (info.get("W"), info.get("H"), args.size, args.size),
              file=sys.stderr)
    if args.info:
        print(json.dumps(info, indent=2, sort_keys=True))
    print("%s  %dx%d  %d bytes" % (out, info["W"], info["H"], len(raw)),
          file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
