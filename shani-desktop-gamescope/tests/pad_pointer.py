# The desktop-mode controller pointer's core (pad-pointer's Driver): pure logic,
# fed raw pad events with a fake clock - no evdev, no uinput, nothing on the host.
import importlib.machinery, importlib.util, os, sys
here = os.path.dirname(os.path.abspath(__file__))
loader = importlib.machinery.SourceFileLoader("pp", os.environ.get("PAD_POINTER") or os.path.join(here, "..", "usr/lib/shani-desktop-gamescope/pad-pointer"))
spec = importlib.util.spec_from_loader("pp", loader); pp = importlib.util.module_from_spec(spec); loader.exec_module(pp)

results = []
def check(name, ok):
    results.append(bool(ok)); print(("PASS " if ok else "FAIL ") + name)

class Clock:
    t = 0.0
    def __call__(self): return self.t

def driver():
    moves, buttons, clock = [], [], Clock()
    return pp.Driver(lambda dx, dy: moves.append((dx, dy)), lambda c, d: buttons.append((c, d)), clock), moves, buttons, clock

def run(d, clock, seconds):
    for _ in range(int(seconds * 60)):
        clock.t += pp.FRAME
        d.tick()

d, moves, _, clock = driver()
d.event("pad", 3, 0x03, 16384); run(d, clock, 1); half = sum(m[0] for m in moves); moves.clear()
d.event("pad", 3, 0x03, 32767); run(d, clock, 1); full = sum(m[0] for m in moves)
check(f"right stick: half way slow ({half}px/s), all the way fast ({full}px/s)", 200 < half < 400 and 1400 < full <= 1500)
d.event("pad", 3, 0x03, 0); moves.clear(); run(d, clock, 0.5)
check("released: still", moves == [] and d.tick() is None)
d.event("pad", 3, 0x04, 3000); run(d, clock, 0.5)
check("a worn stick resting off centre does not drift", moves == [])
d.event("pad", 3, 0x04, -32768); run(d, clock, 0.25)
check("up is negative y", moves and all(dy < 0 and dx == 0 for dx, dy in moves))

d, _, buttons, _ = driver()
d.event("pad", 1, 0x139, 1); d.event("pad", 1, 0x139, 0)
d.event("pad", 1, 0x138, 1); d.event("pad", 1, 0x138, 0)
d.event("pad", 1, 0x13e, 1); d.event("pad", 1, 0x13e, 0)
L, R = pp.BTN_LEFT, pp.BTN_RIGHT
check("RT / LT / right-stick click as buttons", buttons == [(L, True), (L, False), (R, True), (R, False), (L, True), (L, False)])
buttons.clear()
for v in (200, 120, 10): d.event("pad", 3, 0x05, v, (0, 255))
check("an analog RT: down past half, held until let go", buttons == [(L, True), (L, False)])
buttons.clear(); d.event("pad", 3, 0x05, 255, (0, 255), right_stick=False)
check("a DirectInput pad's Z/RZ is its right stick, never a click", buttons == [])

d, moves, buttons, clock = driver()
d.event("pad", 1, 0x139, 1); d.event("pad", 3, 0x03, 32767)
d.pause(True); run(d, clock, 0.5)
check("Steam running: the held button lets go, no motion", buttons == [(L, True), (L, False)] and moves == [])
d.event("pad", 1, 0x139, 0); d.event("pad", 1, 0x139, 1)
check("...and no clicks while paused", buttons == [(L, True), (L, False)])
d.pause(False); d.event("pad", 1, 0x139, 0); run(d, clock, 0.1)
check("Steam gone: it moves again", moves != [])

d, moves, buttons, clock = driver()
d.event(7, 3, 0x03, 32767); d.event(7, 1, 0x138, 1); d.forget(7); run(d, clock, 0.3)
check("an unplugged pad: stops, lets go", moves == [] and buttons == [(R, True), (R, False)])
homes = []
d = pp.Driver(lambda *a: None, lambda *a: None, Clock(), home=lambda: homes.append(1))
d.event("pad", 1, pp.BTN_MODE, 1); d.event("pad", 1, pp.BTN_MODE, 0)
d.pause(True); d.event("pad", 1, pp.BTN_MODE, 1)
check("Guide brings the home up once per press, not while Steam runs", homes == [1])
print(f"RESULT pass={sum(results)} fail={len(results) - sum(results)}")
sys.exit(0 if all(results) else 1)
