"""Procedural, seamlessly tiling PBR textures made with numpy (no Blender needed).

Every generator returns float32 arrays with values in 0..1:
  albedo  (H, W, 3)  sRGB colors
  rough   (H, W)     roughness
  height  (H, W)     used to make the normal map (see normal_map())
Row 0 is the BOTTOM of the image (Blender's pixel order), so +row = +V.

Everything tiles because it's built from periodic pieces: FFT noise is periodic
by construction, and patterns (bricks, boards, ...) use whole numbers of
repeats per tile.
"""

import numpy as np

TAU = 2.0 * np.pi


# --- building blocks ---------------------------------------------------------

def grid(res):
    """u, v coordinates in 0..1 for every pixel (v = row)."""
    v, u = np.mgrid[0:res, 0:res].astype(np.float32) / res
    return u, v


def noise(res, low=2.0, high=None, beta=2.0, aniso=(1.0, 1.0), seed=0):
    """Tiling fractal noise in 0..1.

    low/high: smallest/largest feature frequency, in repeats per tile.
    beta: falloff; higher = smoother, lower = grainier.
    aniso: (ax, ay) > 1 stretches features ALONG that axis (u for ax, v for ay).
    """
    rng = np.random.default_rng(seed)
    fy = np.fft.fftfreq(res)[:, None] * res
    fx = np.fft.rfftfreq(res)[None, :] * res
    f = np.sqrt((fx * aniso[0]) ** 2 + (fy * aniso[1]) ** 2)
    amp = np.power(np.maximum(f, 1e-6), -beta / 2.0)
    amp[f < low] = 0.0
    if high is not None:
        amp *= np.exp(-((f / high) ** 2))
    spectrum = amp * np.exp(1j * rng.uniform(0.0, TAU, amp.shape))
    n = np.fft.irfft2(spectrum, s=(res, res)).astype(np.float32)
    n = (n - n.mean()) / (n.std() + 1e-8)
    return np.clip(0.5 + n / 6.0, 0.0, 1.0)


def cells(res, count, seed=0):
    """Tiling Voronoi. Returns (d1, d2, cell_id): distance to the nearest and
    second-nearest point (in tile units) and the nearest point's index."""
    rng = np.random.default_rng(seed)
    pts = rng.random((count, 2)).astype(np.float32)
    u, v = grid(res)
    d1 = np.full((res, res), 9.0, np.float32)
    d2 = np.full((res, res), 9.0, np.float32)
    ids = np.zeros((res, res), np.int32)
    for i, (px, py) in enumerate(pts):
        dx = np.abs(u - px)
        dx = np.minimum(dx, 1.0 - dx)
        dy = np.abs(v - py)
        dy = np.minimum(dy, 1.0 - dy)
        d = np.sqrt(dx * dx + dy * dy)
        closer = d < d1
        d2 = np.where(closer, d1, np.minimum(d2, d))
        ids = np.where(closer, i, ids)
        d1 = np.where(closer, d, d1)
    return d1, d2, ids


def ramp(t, stops):
    """Maps t (0..1) through color stops [(pos, (r, g, b)), ...]."""
    pos = [s[0] for s in stops]
    out = np.empty(t.shape + (3,), np.float32)
    for c in range(3):
        out[..., c] = np.interp(t, pos, [s[1][c] for s in stops])
    return out


def mix(a, b, t):
    t = t[..., None] if t.ndim == a.ndim - 1 else t
    return a * (1.0 - t) + b * t


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def normal_map(height, strength):
    """Tangent-space normal map (OpenGL / glTF convention, +Y = +V) from a height map.
    strength ~ how deep the full 0..1 height range is, relative to the tile."""
    res = height.shape[0]
    k = strength * res / 64.0
    dx = (np.roll(height, -1, 1) - np.roll(height, 1, 1)) * 0.5 * k
    dy = (np.roll(height, -1, 0) - np.roll(height, 1, 0)) * 0.5 * k
    n = np.dstack([-dx, -dy, np.ones_like(height)])
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    return (n * 0.5 + 0.5).astype(np.float32)


def per_cell_random(ids, seed):
    rng = np.random.default_rng(seed)
    table = rng.random(int(ids.max()) + 1).astype(np.float32)
    return table[ids]


# --- materials ----------------------------------------------------------------

def wood(res, seed=0, tint=(1.0, 1.0, 1.0)):
    """Wood grain running along U."""
    u, v = grid(res)
    warp = noise(res, low=1, high=12, beta=2.5, aniso=(6, 1), seed=seed)
    fine = noise(res, low=8, beta=1.6, aniso=(12, 1), seed=seed + 1)
    rings = 0.5 + 0.5 * np.sin(TAU * (v * 9.0 + warp * 2.5))
    rings = np.power(rings, 3.0)
    knots_d, _, _ = cells(res, 3, seed + 2)
    knots = 1.0 - smoothstep(0.0, 0.035, knots_d * np.array([1.0], np.float32))
    h = 0.55 * rings + 0.35 * fine + 0.1 * warp - 0.3 * knots
    albedo = ramp(np.clip(h, 0, 1), [
        (0.0, (0.25, 0.14, 0.07)), (0.45, (0.44, 0.28, 0.15)),
        (0.75, (0.56, 0.38, 0.22)), (1.0, (0.64, 0.46, 0.29))])
    albedo *= np.array(tint, np.float32)
    rough = 0.62 + 0.18 * fine
    return albedo, rough, h


def boards(res, count=6, seed=0, tint=(1.0, 1.0, 1.0)):
    """Horizontal boards (seams along U, `count` boards per tile), grain along U."""
    albedo, rough, h = wood(res, seed, tint)
    u, v = grid(res)
    rng = np.random.default_rng(seed + 7)
    row = np.floor(v * count).astype(np.int32)
    shade = rng.uniform(0.75, 1.1, count).astype(np.float32)[row]
    shift = rng.integers(0, res, count)
    for b in range(count):  # Give each board its own stretch of grain.
        rows = slice(b * res // count, (b + 1) * res // count)
        albedo[rows] = np.roll(albedo[rows], shift[b], axis=1)
        h[rows] = np.roll(h[rows], shift[b], axis=1)
    local = (v * count) % 1.0
    groove = smoothstep(0.0, 0.06, local) * smoothstep(0.0, 0.06, 1.0 - local)
    albedo = albedo * shade[..., None] * (0.35 + 0.65 * groove[..., None])
    return albedo, rough, h * 0.4 + groove * 0.6


def bark(res, seed=0):
    """Rough bark with deep furrows running along V."""
    ridges = noise(res, low=3, high=40, beta=2.2, aniso=(1, 7), seed=seed)
    ridges = 1.0 - np.abs(ridges * 2.0 - 1.0)
    detail = noise(res, low=16, beta=1.4, seed=seed + 1)
    blotch = noise(res, low=2, high=8, beta=3.0, seed=seed + 2)
    h = np.clip(0.7 * np.power(ridges, 1.6) + 0.3 * detail, 0, 1)
    albedo = ramp(h, [(0.0, (0.07, 0.05, 0.04)), (0.5, (0.22, 0.17, 0.13)), (1.0, (0.38, 0.32, 0.26))])
    moss = smoothstep(0.62, 0.8, blotch) * (1.0 - h)
    albedo = mix(albedo, np.broadcast_to(np.array([0.2, 0.27, 0.1], np.float32), albedo.shape), moss * 0.7)
    rough = 0.8 + 0.15 * (1.0 - h)
    return albedo, rough, h


def stone(res, seed=0, base=(0.42, 0.41, 0.39)):
    """Weathered stone / rock with cracks and a bit of lichen."""
    big = noise(res, low=2, high=24, beta=2.6, seed=seed)
    grain = noise(res, low=30, beta=1.2, seed=seed + 1)
    d1, d2, _ = cells(res, 14, seed + 2)
    cracks = 1.0 - smoothstep(0.0, 0.012, d2 - d1)
    lichen_mask = smoothstep(0.66, 0.8, noise(res, low=3, high=20, beta=2.0, seed=seed + 3))
    h = np.clip(0.6 * big + 0.4 * grain - 0.5 * cracks, 0, 1)
    b = np.array(base, np.float32)
    albedo = ramp(h, [(0.0, tuple(b * 0.45)), (0.5, tuple(b)), (1.0, tuple(np.minimum(b * 1.35, 1)))])
    albedo *= (0.9 + 0.2 * grain)[..., None]
    albedo = mix(albedo, np.broadcast_to(np.array([0.55, 0.55, 0.3], np.float32), albedo.shape), lichen_mask * 0.5)
    rough = 0.82 + 0.12 * grain
    return albedo, rough, h


def stone_blocks(res, rows=5, seed=0):
    """Cut stone masonry (ashlar): `rows` courses per tile, irregular block lengths."""
    u, v = grid(res)
    rng = np.random.default_rng(seed)
    row = np.floor(v * rows).astype(np.int32)
    local_v = (v * rows) % 1.0
    block_id = np.zeros((res, res), np.int32)
    edge_u = np.ones((res, res), np.float32)
    for r in range(rows):
        widths = rng.uniform(0.6, 1.4, 4)
        bounds = np.cumsum(widths) / widths.sum()
        offset = rng.random()
        mask = row == r
        uu = (u[mask] + offset) % 1.0
        idx = np.searchsorted(bounds, uu)
        prev = np.where(idx == 0, 0.0, bounds[np.maximum(idx - 1, 0)])
        nxt = bounds[np.minimum(idx, len(bounds) - 1)]
        edge_u[mask] = np.minimum(uu - prev, nxt - uu) * 4.0  # in block-ish units
        block_id[mask] = r * 10 + idx
    edge_v = np.minimum(local_v, 1.0 - local_v)
    edge = np.minimum(edge_u, edge_v)
    mortar = 1.0 - smoothstep(0.02, 0.05, edge)
    tint = per_cell_random(block_id, seed + 5)
    surface = noise(res, low=6, beta=1.8, seed=seed + 1)
    bevel = smoothstep(0.02, 0.12, edge)
    h = np.clip(bevel * (0.75 + 0.25 * surface) * (1.0 - mortar), 0, 1)
    stone_col = ramp(tint, [(0, (0.42, 0.4, 0.37)), (0.5, (0.55, 0.52, 0.47)), (1, (0.62, 0.58, 0.5))])
    stone_col *= (0.85 + 0.3 * surface)[..., None]
    albedo = mix(stone_col, np.broadcast_to(np.array([0.3, 0.29, 0.27], np.float32), stone_col.shape), mortar)
    rough = 0.85 + 0.1 * surface
    return albedo, rough, h


def bricks(res, rows=14, per_row=4, seed=0):
    """Red brick in running bond with light mortar."""
    u, v = grid(res)
    row = np.floor(v * rows).astype(np.int32)
    uu = (u * per_row + 0.5 * (row % 2)) % per_row
    col = np.floor(uu).astype(np.int32)
    lu = uu % 1.0
    lv = (v * rows) % 1.0
    # Brick aspect: mortar should look equally thick both ways.
    aspect = (1.0 / per_row) / (1.0 / rows)
    edge = np.minimum(np.minimum(lu, 1 - lu) * aspect, np.minimum(lv, 1 - lv))
    mortar = 1.0 - smoothstep(0.06, 0.12, edge)
    tint = per_cell_random(row * 64 + col, seed)
    surface = noise(res, low=10, beta=1.5, seed=seed + 1)
    brick = ramp(tint, [(0, (0.36, 0.13, 0.08)), (0.4, (0.5, 0.2, 0.12)), (0.8, (0.58, 0.28, 0.17)), (1, (0.45, 0.3, 0.24))])
    brick *= (0.82 + 0.35 * surface)[..., None]
    mortar_col = np.broadcast_to(np.array([0.62, 0.6, 0.55], np.float32), brick.shape) * (0.85 + 0.3 * surface)[..., None]
    albedo = mix(brick, mortar_col, mortar)
    h = (1 - mortar) * (0.8 + 0.2 * surface) * smoothstep(0.06, 0.2, edge)
    rough = 0.85 + 0.1 * surface
    return albedo, rough, h


def plaster(res, color, seed=0):
    """Painted render / stucco."""
    big = noise(res, low=2, high=10, beta=3.0, seed=seed)
    fine = noise(res, low=40, beta=1.0, seed=seed + 1)
    stains = smoothstep(0.6, 0.85, noise(res, low=2, high=6, beta=2.5, aniso=(1, 3), seed=seed + 2))
    albedo = np.broadcast_to(np.array(color, np.float32), (res, res, 3)) * (0.92 + 0.1 * big + 0.06 * fine)[..., None]
    albedo = albedo * (1.0 - 0.18 * stains[..., None])
    return albedo, 0.88 + 0.08 * fine, 0.6 * fine + 0.4 * big


def roof_tiles(res, rows=8, per_row=6, seed=0):
    """Clay roof tiles. Courses run along U; V goes down the slope."""
    u, v = grid(res)
    row = np.floor(v * rows).astype(np.int32)
    lv = (v * rows) % 1.0
    uu = (u * per_row + 0.5 * (row % 2)) % per_row
    col = np.floor(uu).astype(np.int32)
    lu = uu % 1.0
    curve = np.sin(np.pi * lu)  # Barrel-shaped tile.
    overlap = lv  # Each course rises toward its lower edge, overlapping the next.
    h = 0.55 * curve + 0.45 * overlap
    gap = 1.0 - smoothstep(0.0, 0.05, np.minimum(lu, 1 - lu))
    shadow = 1.0 - smoothstep(0.0, 0.15, lv)
    tint = per_cell_random(row * 64 + col, seed)
    surface = noise(res, low=12, beta=1.4, seed=seed + 1)
    moss = smoothstep(0.65, 0.85, noise(res, low=2, high=10, beta=2.5, seed=seed + 2)) * shadow
    albedo = ramp(tint, [(0, (0.42, 0.14, 0.08)), (0.5, (0.55, 0.2, 0.11)), (1, (0.62, 0.3, 0.18))])
    albedo *= (0.85 + 0.3 * surface)[..., None] * (0.6 + 0.4 * curve)[..., None]
    albedo *= (1.0 - 0.55 * shadow - 0.4 * gap)[..., None]
    albedo = mix(albedo, np.broadcast_to(np.array([0.22, 0.25, 0.1], np.float32), albedo.shape), moss * 0.6)
    return albedo, 0.75 + 0.15 * surface, np.clip(h - 0.5 * gap, 0, 1)


def corrugated(res, ridges=12, seed=0, rust=0.35):
    """Galvanized corrugated metal. Ridges run along V."""
    u, v = grid(res)
    h = 0.5 + 0.5 * np.sin(TAU * u * ridges)
    blotch = noise(res, low=2, high=16, beta=2.2, seed=seed)
    streaks = noise(res, low=4, beta=1.8, aniso=(1, 10), seed=seed + 1)
    rust_mask = smoothstep(0.62, 0.82, streaks * 0.6 + blotch * 0.4) * rust
    metal = ramp(blotch, [(0, (0.45, 0.47, 0.48)), (1, (0.68, 0.7, 0.7))])
    albedo = mix(metal, np.broadcast_to(np.array([0.35, 0.17, 0.07], np.float32), metal.shape), rust_mask)
    rough = 0.35 + 0.25 * blotch + 0.4 * rust_mask
    metal_amount = 1.0 - rust_mask
    return albedo, rough, h, metal_amount


def painted_metal(res, color, seed=0, wear=0.25):
    """Paint over iron, chipped and a little rusty at the worn spots."""
    n = noise(res, low=3, high=40, beta=2.0, seed=seed)
    fine = noise(res, low=30, beta=1.2, seed=seed + 1)
    chips = smoothstep(1.0 - wear * 0.5, 1.0 - wear * 0.3, n)
    paint = np.broadcast_to(np.array(color, np.float32), (res, res, 3)) * (0.9 + 0.15 * fine)[..., None]
    albedo = mix(paint, np.broadcast_to(np.array([0.3, 0.15, 0.07], np.float32), paint.shape), chips)
    rough = 0.45 + 0.35 * chips + 0.1 * fine
    return albedo, rough, (1.0 - chips) * 0.8 + 0.2 * fine


def rubber_tread(res, seed=0):
    """Tyre tread: blocks around U, two rows across V."""
    u, v = grid(res)
    blocks = 0.5 + 0.5 * np.sign(np.sin(TAU * (u * 24 + np.abs(v - 0.5) * 1.5)))
    center = smoothstep(0.03, 0.06, np.abs(v - 0.5))
    h = blocks * center
    fine = noise(res, low=30, beta=1.0, seed=seed)
    albedo = np.broadcast_to(np.array([0.035, 0.035, 0.038], np.float32), (res, res, 3)) * (0.8 + 0.4 * fine)[..., None]
    return albedo, 0.85 + 0.1 * fine, h


def concrete(res, seed=0):
    big = noise(res, low=2, high=12, beta=2.4, seed=seed)
    fine = noise(res, low=40, beta=1.0, seed=seed + 1)
    d1, _, _ = cells(res, 120, seed + 2)
    pits = 1.0 - smoothstep(0.0, 0.006, d1)
    albedo = ramp(big, [(0, (0.42, 0.41, 0.39)), (1, (0.6, 0.59, 0.56))]) * (0.9 + 0.15 * fine)[..., None]
    albedo *= (1.0 - 0.5 * pits)[..., None]
    return albedo, 0.88 + 0.08 * fine, 0.7 * fine + 0.3 * big - 0.5 * pits


def terracotta(res, seed=0):
    big = noise(res, low=2, high=10, beta=2.5, seed=seed)
    fine = noise(res, low=40, beta=1.0, seed=seed + 1)
    albedo = ramp(big, [(0, (0.5, 0.22, 0.12)), (1, (0.68, 0.36, 0.22))]) * (0.9 + 0.15 * fine)[..., None]
    return albedo, 0.85 + 0.1 * fine, fine


def soil(res, seed=0):
    big = noise(res, low=3, high=30, beta=2.0, seed=seed)
    d1, _, ids = cells(res, 220, seed + 1)
    pebbles = 1.0 - smoothstep(0.004, 0.012, d1)
    tint = per_cell_random(ids, seed + 2)
    albedo = ramp(big, [(0, (0.08, 0.05, 0.03)), (1, (0.22, 0.15, 0.09))])
    peb = ramp(tint, [(0, (0.3, 0.27, 0.23)), (1, (0.5, 0.46, 0.4))])
    albedo = mix(albedo, peb, pebbles * (tint > 0.5))
    return albedo, 0.95 - 0.1 * pebbles, 0.5 * big + 0.5 * pebbles


def paper_pages(res, lines=140, seed=0):
    """Edges of a stack of pages: fine lines along U."""
    u, v = grid(res)
    wobble = noise(res, low=2, beta=2.0, aniso=(8, 1), seed=seed)
    h = 0.5 + 0.5 * np.sin(TAU * (v * lines + wobble * 3.0))
    albedo = np.broadcast_to(np.array([0.9, 0.87, 0.78], np.float32), (res, res, 3)) * (0.9 + 0.1 * h)[..., None]
    return albedo, 0.9 + 0.05 * h, h


def weave(res, count=96, seed=0):
    """Cloth weave height (for book covers and clothes)."""
    u, v = grid(res)
    a = np.sin(TAU * u * count) * 0.5 + 0.5
    b = np.sin(TAU * v * count) * 0.5 + 0.5
    checker = (np.floor(u * count) + np.floor(v * count)) % 2
    fuzz = noise(res, low=20, beta=1.0, seed=seed)
    h = np.where(checker > 0, a, b) * 0.7 + 0.3 * fuzz
    return h


def denim(res, seed=0):
    u, v = grid(res)
    twill = 0.5 + 0.5 * np.sin(TAU * (u + v) * 110)
    fade = noise(res, low=2, high=16, beta=2.2, aniso=(1, 4), seed=seed)
    fuzz = noise(res, low=60, beta=0.8, seed=seed + 1)
    albedo = ramp(fade, [(0, (0.06, 0.1, 0.2)), (1, (0.2, 0.28, 0.42))]) * (0.8 + 0.3 * twill * fuzz)[..., None]
    return albedo, 0.9 + 0.05 * fuzz, 0.7 * twill + 0.3 * fuzz


def crinkle(res, seed=0):
    """Crumpled plastic wrapper (height only)."""
    d1, d2, _ = cells(res, 40, seed)
    folds = smoothstep(0.0, 0.03, d2 - d1)
    n = noise(res, low=4, beta=1.8, seed=seed + 1)
    return 0.6 * folds + 0.4 * n


def coin_face(res, seed=0):
    """Height for a coin face: raised rim, beaded ring, worn relief in the middle."""
    u, v = grid(res)
    x, y = u - 0.5, v - 0.5
    r = np.sqrt(x * x + y * y)
    a = np.arctan2(y, x)
    rim = smoothstep(0.43, 0.45, r) * (1.0 - smoothstep(0.49, 0.5, r))
    beads = smoothstep(0.38, 0.39, r) * (1.0 - smoothstep(0.41, 0.42, r)) * (np.sin(a * 60) > 0.2)
    relief = noise(res, low=3, high=14, beta=2.2, seed=seed) * (1.0 - smoothstep(0.3, 0.36, r))
    relief = smoothstep(0.5, 0.62, relief)
    wear = noise(res, low=20, beta=1.2, seed=seed + 1)
    return np.clip(0.9 * rim + 0.6 * beads + 0.55 * relief + 0.08 * wear, 0, 1)


def gold(res, seed=0):
    wear = noise(res, low=6, beta=1.6, seed=seed)
    albedo = ramp(wear, [(0, (0.72, 0.5, 0.18)), (1, (0.95, 0.76, 0.36))])
    return albedo, 0.22 + 0.25 * wear


def galvanized(res, seed=0):
    blotch = noise(res, low=3, high=24, beta=2.0, seed=seed)
    albedo = ramp(blotch, [(0, (0.5, 0.52, 0.53)), (1, (0.75, 0.76, 0.76))])
    return albedo, 0.3 + 0.3 * blotch, blotch


def grass(res, seed=0, blades=26000):
    """Top-down lawn: thousands of short blades over soil, tiling."""
    rng = np.random.default_rng(seed)
    base_n = noise(res, low=2, high=30, beta=2.0, seed=seed)
    albedo = ramp(base_n, [(0, (0.1, 0.12, 0.04)), (1, (0.2, 0.24, 0.08))])
    height = np.zeros((res, res), np.float32) + 0.1 * base_n
    palette = np.array([
        (0.18, 0.32, 0.08), (0.24, 0.4, 0.1), (0.3, 0.45, 0.14),
        (0.36, 0.48, 0.16), (0.42, 0.45, 0.2), (0.2, 0.36, 0.12)], np.float32)
    for _ in range(blades):
        x0, y0 = rng.random(2) * res
        ang = rng.uniform(0, TAU)
        length = rng.uniform(4, 14) * res / 1024
        steps = max(2, int(length))
        col = palette[rng.integers(len(palette))] * rng.uniform(0.8, 1.2)
        tip_h = rng.uniform(0.5, 1.0)
        for s in range(steps):
            t = s / (steps - 1)
            xi = int(x0 + np.cos(ang) * length * t) % res
            yi = int(y0 + np.sin(ang) * length * t) % res
            hh = 0.2 + tip_h * t
            if hh >= height[yi, xi]:
                height[yi, xi] = hh
                albedo[yi, xi] = col * (0.75 + 0.35 * t)
    rough = 0.9 - 0.15 * height
    return np.clip(albedo, 0, 1), rough, height


# --- alpha-masked cutouts (leaves etc.) ----------------------------------------

def _draw_leaf(img, alpha, height, cx, cy, ang, length, width, color, res):
    """Draws one pointed leaf into the RGBA buffers (no wrap: cutouts don't tile)."""
    half = int(length * 0.6) + 2
    x0, x1 = int(max(cx - half, 0)), int(min(cx + half, res))
    y0, y1 = int(max(cy - half, 0)), int(min(cy + half, res))
    if x0 >= x1 or y0 >= y1:
        return
    yy, xx = np.mgrid[y0:y1, x0:x1].astype(np.float32)
    dx, dy = xx - cx, yy - cy
    s = (dx * np.cos(ang) + dy * np.sin(ang)) / length + 0.5   # 0 = base, 1 = tip
    t = (-dx * np.sin(ang) + dy * np.cos(ang)) / width          # across
    profile = np.where((s > 0) & (s < 1), np.power(np.sin(np.pi * np.clip(s, 0, 1)), 0.75) * 0.5, 0.0)
    inside = np.abs(t) < profile
    if not inside.any():
        return
    vein = np.exp(-(t / 0.03) ** 2) * (s > 0.02)
    side_veins = 0.5 + 0.5 * np.sin((s * 14 - np.abs(t) * 10) * TAU / 2)
    cup = 1.0 - (t / np.maximum(profile, 1e-3)) ** 2
    shade = (0.82 + 0.25 * s) * (1.0 - 0.25 * vein) * (0.93 + 0.07 * side_veins)
    col = np.clip(np.array(color, np.float32)[None, None, :] * shade[..., None], 0, 1)
    region = img[y0:y1, x0:x1]
    region[inside] = col[inside]
    alpha[y0:y1, x0:x1][inside] = 1.0
    height[y0:y1, x0:x1][inside] = (0.5 + 0.5 * cup - 0.3 * vein)[inside]


def leaf_twig(res, seed=0, greens=((0.16, 0.32, 0.07), (0.22, 0.4, 0.1), (0.3, 0.45, 0.12))):
    """A twig with ~9 leaves, centered, stem from the bottom edge up. RGBA cutout."""
    rng = np.random.default_rng(seed)
    img = np.zeros((res, res, 3), np.float32)
    alpha = np.zeros((res, res), np.float32)
    height = np.zeros((res, res), np.float32)
    # Stem.
    for y in range(int(res * 0.02), int(res * 0.82)):
        x = res * 0.5 + np.sin(y / res * 3) * res * 0.02
        w = max(1, int(res * 0.008 * (1.2 - y / res)))
        img[y, int(x) - w:int(x) + w] = (0.2, 0.15, 0.07)
        alpha[y, int(x) - w:int(x) + w] = 1.0
    count = 9
    for i in range(count):
        t = 0.15 + 0.62 * i / (count - 1)
        side = -1 if i % 2 else 1
        # Angle measured from straight up; leaves fan out sideways, lower ones more.
        ang = np.pi / 2 - side * rng.uniform(0.85, 1.25) * (1.0 - t * 0.45)
        length = res * rng.uniform(0.27, 0.33) * (1.1 - t * 0.4)
        base_x = res * 0.5 + np.sin(t * 3) * res * 0.02
        cx = base_x + np.cos(ang) * length * 0.5
        cy = res * t + np.sin(ang) * length * 0.5
        col = np.array(greens[rng.integers(len(greens))]) * rng.uniform(0.85, 1.15)
        _draw_leaf(img, alpha, height, cx, cy, ang, length, length * 0.45, col, res)
    _draw_leaf(img, alpha, height, res * 0.5, res * 0.88, np.pi / 2, res * 0.24, res * 0.1, greens[1], res)
    return img, alpha, height


def pine_branch(res, seed=0):
    """Top view of a pine branch: twig along V with needles both sides. RGBA cutout."""
    rng = np.random.default_rng(seed)
    img = np.zeros((res, res, 3), np.float32)
    alpha = np.zeros((res, res), np.float32)
    height = np.zeros((res, res), np.float32)
    for i in range(1400):
        t = rng.random()
        y = res * (0.03 + 0.94 * t)
        side = rng.choice([-1, 1])
        ang = side * rng.uniform(0.6, 1.2) + np.pi / 2 * 0  # angle from the twig
        length = res * rng.uniform(0.12, 0.24) * (1.0 - 0.45 * t)
        col = np.array([0.08, 0.2, 0.08]) * rng.uniform(0.7, 1.5)
        for s in np.linspace(0, 1, int(length)):
            x = int(res * 0.5 + side * np.sin(abs(ang)) * length * s)
            yy = int(y + np.cos(ang) * length * s * 0.6)
            if 0 <= x < res and 0 <= yy < res:
                img[yy, x] = col * (0.8 + 0.4 * s)
                alpha[yy, x] = 1.0
                height[yy, x] = 0.5 + 0.5 * s
    for y in range(int(res * 0.02), int(res * 0.98)):
        img[y, res // 2 - 2:res // 2 + 2] = (0.25, 0.16, 0.08)
        alpha[y, res // 2 - 2:res // 2 + 2] = 1.0
    # Thicken needles a touch so they survive mipmapping.
    a2 = np.maximum(alpha, np.roll(alpha, 1, 1))
    img = np.where((a2 > alpha)[..., None], np.roll(img, 1, 1), img)
    return img, a2, height


def flower(res, seed=0, petal=(0.95, 0.85, 0.2), center=(0.45, 0.25, 0.05)):
    """A daisy-like flower head, RGBA cutout."""
    u, v = grid(res)
    x, y = u - 0.5, v - 0.5
    r = np.sqrt(x * x + y * y)
    a = np.arctan2(y, x)
    petals = 0.3 + 0.17 * np.power(np.abs(np.cos(a * 4)), 0.6)
    alpha = (r < petals).astype(np.float32)
    shade = 0.75 + 0.25 * np.abs(np.cos(a * 4))
    img = np.broadcast_to(np.array(petal, np.float32), (res, res, 3)) * shade[..., None]
    middle = r < 0.1
    img = np.where(middle[..., None], np.array(center, np.float32), img)
    height = np.where(middle, 1.0, 0.5 * shade)
    return img.astype(np.float32), alpha, height.astype(np.float32)


def foliage(res, seed=0):
    """Dense tiling leaf mass, for the opaque core of bushes and tree crowns."""
    rng = np.random.default_rng(seed)
    albedo = np.zeros((res, res, 3), np.float32) + np.array([0.03, 0.07, 0.02], np.float32)
    alpha = np.zeros((res, res), np.float32)
    height = np.zeros((res, res), np.float32)
    big = res * 3
    canvas = np.zeros((big, big, 3), np.float32)
    calpha = np.zeros((big, big), np.float32)
    cheight = np.zeros((big, big), np.float32)
    greens = [(0.12, 0.26, 0.05), (0.18, 0.34, 0.07), (0.24, 0.4, 0.1), (0.1, 0.2, 0.05)]
    for _ in range(700):
        cx, cy = rng.random(2) * res + res
        col = np.array(greens[rng.integers(len(greens))]) * rng.uniform(0.75, 1.2)
        length = res * rng.uniform(0.07, 0.12)
        _draw_leaf(canvas, calpha, cheight, cx, cy, rng.uniform(0, TAU), length, length * 0.45, col, big)
    # Fold the 3x3 canvas back onto one tile so leaves crossing an edge wrap around.
    for oy in range(3):
        for ox in range(3):
            sl = (slice(oy * res, (oy + 1) * res), slice(ox * res, (ox + 1) * res))
            m = calpha[sl] > 0
            albedo[m] = canvas[sl][m]
            height[m] = np.maximum(height[m], cheight[sl][m])
    return albedo, 0.75 + 0.1 * height, height
