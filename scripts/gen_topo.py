#!/usr/bin/env python3
"""Generate site/assets/img/topo.svg: faint topographic contour lines for the site background.
Deterministic; rerun after changing HILLS, LEVELS or EPS."""
import math
import sys
from pathlib import Path

W, H = 1600, 1000      # SVG viewBox
NX, NY = 120, 75       # grid cells
LEVELS = 12
EPS = 1.6              # Ramer-Douglas-Peucker tolerance in viewBox px
HILLS = [              # (cx, cy, sigma, height) in unit coordinates
    (0.16, 0.28, 0.15, 1.0), (0.74, 0.20, 0.12, 0.8), (0.62, 0.72, 0.20, 1.1),
    (0.26, 0.84, 0.10, 0.6), (0.92, 0.86, 0.13, 0.7),
]
OUT = Path(__file__).resolve().parent.parent / "site" / "assets" / "img" / "topo.svg"
sys.setrecursionlimit(10000)


def field(u, v):
    z = sum(h * math.exp(-((u - cx) ** 2 + (v - cy) ** 2) / (2 * s * s)) for cx, cy, s, h in HILLS)
    return z + 0.06 * math.sin(7 * u + 1.3) * math.cos(6 * v + 0.4)


GRID = [[field(i / NX, j / NY) for i in range(NX + 1)] for j in range(NY + 1)]


def segments(t):
    sx, sy = W / NX, H / NY
    for j in range(NY):
        for i in range(NX):
            c = [(i * sx, j * sy), ((i + 1) * sx, j * sy), ((i + 1) * sx, (j + 1) * sy), (i * sx, (j + 1) * sy)]
            z = [GRID[j][i], GRID[j][i + 1], GRID[j + 1][i + 1], GRID[j + 1][i]]
            pts = []
            for e in range(4):  # edges: 0 top, 1 right, 2 bottom, 3 left
                a, b = z[e], z[(e + 1) % 4]
                if (a < t) != (b < t):
                    k = (t - a) / (b - a)
                    p, q = c[e], c[(e + 1) % 4]
                    pts.append((p[0] + k * (q[0] - p[0]), p[1] + k * (q[1] - p[1])))
            if len(pts) == 2:
                yield pts[0], pts[1]
            elif len(pts) == 4:  # saddle: corners 0 and 2 joined through the centre, or 1 and 3
                if (sum(z) / 4 < t) == (z[0] < t):
                    yield pts[0], pts[1]
                    yield pts[2], pts[3]
                else:
                    yield pts[3], pts[0]
                    yield pts[1], pts[2]


def chains(segs):
    key = lambda p: (round(p[0], 2), round(p[1], 2))
    adj, pos = {}, {}
    for a, b in segs:
        adj.setdefault(key(a), []).append(b)
        adj.setdefault(key(b), []).append(a)
        pos[key(a)], pos[key(b)] = a, b
    seen, out = set(), []
    for start in [k for k, v in adj.items() if len(v) == 1] + list(adj):
        if start in seen:
            continue
        line, cur = [pos[start]], start
        seen.add(cur)
        while True:
            nxt = next((n for n in adj[cur] if key(n) not in seen), None)
            if nxt is None:
                break
            line.append(nxt)
            cur = key(nxt)
            seen.add(cur)
        if len(line) > 2 and start in {key(n) for n in adj[cur]}:
            line.append(line[0])
        if len(line) > 3:
            out.append(line)
    return out


def rdp(pts, eps):
    if len(pts) < 3:
        return pts
    (x1, y1), (x2, y2) = pts[0], pts[-1]
    dx, dy = x2 - x1, y2 - y1
    n = math.hypot(dx, dy)

    def dist(x, y):  # to the chord, or to the shared endpoint when a closed loop has a zero-length chord
        return abs(dy * (x - x1) - dx * (y - y1)) / n if n > 1e-9 else math.hypot(x - x1, y - y1)

    i, d = max(((k, dist(x, y)) for k, (x, y) in enumerate(pts[1:-1], 1)), key=lambda t: t[1])
    if d <= eps:
        return [pts[0], pts[-1]]
    return rdp(pts[: i + 1], eps)[:-1] + rdp(pts[i:], eps)


lo, hi = min(map(min, GRID)), max(map(max, GRID))
paths = []
for n in range(1, LEVELS + 1):
    t = lo + (hi - lo) * n / (LEVELS + 1)
    for line in chains(list(segments(t))):
        pts = rdp(line, EPS)
        paths.append('<path d="M' + " L".join(f"{x:.0f} {y:.0f}" for x, y in pts) + '"/>')
svg = (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" preserveAspectRatio="xMidYMid slice">'
       '<g fill="none" stroke="#2f6b4f" stroke-opacity="0.16" stroke-width="1.2" '
       'stroke-linejoin="round" stroke-linecap="round">' + "".join(paths) + "</g></svg>\n")
OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_text(svg)
print(f"{OUT}: {len(paths)} paths, {len(svg) / 1024:.1f} KB")
