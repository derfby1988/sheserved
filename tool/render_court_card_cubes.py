"""Render the Court Card cube stack as real 3D glass using a small ray tracer.

Produces `assets/cubes/court_card_cubes_sheet.png`: a 4x4 sprite sheet of 16
frames (each 256x256, RGBA) animating a subtle sway + breathing motion of the
translucent red-glass pyramid used by the Court Card 3D styles. Frame 0 is the
hero still (azimuth 0, full scale) reused by the non-animated styles.

The glass is shaded with Schlick Fresnel (reflection + refraction), red tint
absorption, a studio-ish environment (gradient + key-light specular blob) and a
baked soft ground shadow + ambient glow so the stack reads as volumetric glass
on any card background.

Run:  python3 tool/render_court_card_cubes.py
"""

import os

import numpy as np
from PIL import Image

W = H = 256
FRAMES = 16
COLS = ROWS = 4
MAX_DEPTH = 6
AA = 2  # supersample per side (AA x AA rays per pixel)

HALF_W = 24.0  # half footprint width
HALF_D = 14.0  # half footprint depth
HALF_H = 24.0  # cube height
ROWS_DEF = [[-3, -1, 1, 3], [-2, 0, 2], [-1, 1], [0]]

IOR = 1.5
TINT = np.array([0.96, 0.50, 0.55])  # red glass absorption per surface


def build_boxes():
    boxes = []
    for row, offsets in enumerate(ROWS_DEF):
        z0 = row * HALF_H
        z1 = (row + 1) * HALF_H
        for off in offsets:
            cx = off * HALF_W
            boxes.append((cx - HALF_W, -HALF_D, z0, cx + HALF_W, HALF_D, z1))
    return np.array(boxes, dtype=np.float64)


BOXES = build_boxes()
SCENE_CENTER = np.array([0.0, 0.0, 44.0])


def camera(azimuth_deg):
    az = np.radians(azimuth_deg)
    d = np.array([np.cos(az) * 0.62, np.sin(az) * 0.62, 0.55])
    d /= np.linalg.norm(d)
    up = np.array([0.0, 0.0, 1.0])
    u = np.cross(d, up)
    u /= np.linalg.norm(u)
    v = np.cross(u, d)
    return d, u, v


def project_corners(d, u, v):
    """World -> screen pixels for all cube corners (used to frame the shot)."""
    pts = []
    for (x0, y0, z0, x1, y1, z1) in BOXES:
        for corner in np.array(
            [[x0, y0, z0], [x1, y0, z0], [x0, y1, z0], [x1, y1, z0],
             [x0, y0, z1], [x1, y0, z1], [x0, y1, z1], [x1, y1, z1]]
        ):
            rel = corner - SCENE_CENTER
            pts.append((np.dot(rel, u), np.dot(rel, v)))
    pts = np.array(pts)
    return pts[:, 0].min(), pts[:, 0].max(), pts[:, 1].min(), pts[:, 1].max()


def frame_camera(azimuth_deg):
    """Camera scaled so the whole stack fits the frame with a margin."""
    d, u, v = camera(azimuth_deg)
    x0, x1, y0, y1 = project_corners(d, u, v)
    span = max(x1 - x0, y1 - y0)
    scale = (W * 0.96) / span
    cx = (x0 + x1) / 2
    cy = (y0 + y1) / 2
    return d, u, v, scale, cx, cy


def env_color(dirs):
    """Studio-ish environment seen by the glass: gradient + key specular."""
    y = dirs[:, 2]
    warm = 0.5 + 0.5 * np.clip((y + 0.4) / 1.4, 0, 1)
    cold = 1.0 - warm
    base = np.stack(
        [0.55 * warm + 0.16 * cold, 0.48 * warm + 0.14 * cold, 0.42 * warm + 0.20 * cold],
        axis=1,
    )
    light = np.array([0.55, 0.62, 0.60])
    light /= np.linalg.norm(light)
    spec = np.maximum(np.sum(dirs * light, axis=1), 0.0) ** 48
    return base + spec[:, None] * np.array([0.85, 0.80, 0.72])


def slab(box, ro, rd):
    """Vectorized AABB slab test. Returns enter/exit t and entry normal."""
    safe = np.where(rd == 0, 1e-12, rd)
    t1 = (box[None, 0:3] - ro) / safe
    t2 = (box[None, 3:6] - ro) / safe
    tmin = np.minimum(t1, t2)
    tmax = np.maximum(t1, t2)
    t_enter = tmin.max(axis=1)
    t_exit = tmax.min(axis=1)
    hit = (t_exit > t_enter) & (t_exit > 1e-4)
    n = np.zeros_like(ro)
    for axis in range(3):
        mask = (t_enter == tmin[:, axis]) & hit
        n[mask, axis] = -np.sign(rd[mask, axis])
    return t_enter, t_exit, hit, n


def trace_chunk(ro, rd):
    """Trace one chunk of rays through the glass scene."""
    N = ro.shape[0]
    weight = np.ones(N)
    tint = np.ones((N, 3))
    state = np.ones(N)  # 1.0 outside, IOR inside
    active = np.ones(N, dtype=bool)

    acc_rgb = np.zeros((N, 3))
    acc_a = np.zeros(N)

    eps = 1e-3
    for _ in range(MAX_DEPTH):
        if not active.any():
            break
        wave = active.copy()  # full-size mask of rays in this wave
        aro = ro[wave]
        ard = rd[wave]
        n_wave = aro.shape[0]
        t_enter = np.full(n_wave, np.inf)
        t_exit = np.full(n_wave, -np.inf)
        hit = np.zeros(n_wave, dtype=bool)
        normal = np.zeros_like(aro)
        for box in BOXES:
            te, tx, h, nrm = slab(box, aro, ard)
            better = h & (te < t_enter)
            t_enter = np.where(better, te, t_enter)
            t_exit = np.where(better, tx, t_exit)
            hit = hit | better
            normal = np.where(better[:, None], nrm, normal)

        # Rays that exited the scene contribute transmitted environment light.
        exited = wave.copy()
        exited[wave] = ~hit
        if exited.any():
            acc_rgb[exited] += (
                weight[exited, None] * tint[exited] * env_color(rd[exited])
            )
        active[wave] = hit  # only hit rays keep bouncing

        stay = wave.copy()
        stay[wave] = hit
        if not stay.any():
            continue

        s_ro = ro[stay]
        s_rd = rd[stay]
        s_te = t_enter[hit]
        s_n = normal[hit]
        s_w = weight[stay]
        s_tint = tint[stay]
        s_state = state[stay]

        cosi = np.abs(np.sum(s_rd * s_n, axis=1))
        flip = np.sum(s_rd * s_n, axis=1) > 0
        n_opp = np.where(flip[:, None], -s_n, s_n)

        f0 = ((IOR - 1.0) / (IOR + 1.0)) ** 2
        fresnel = f0 + (1.0 - f0) * (1.0 - cosi) ** 5

        eta = np.where(s_state > 1.0, IOR, 1.0 / IOR)
        k = 1.0 - eta * eta * (1.0 - cosi * cosi)
        tir = k <= 0
        fresnel = np.where(tir, 1.0, fresnel)  # total internal reflection

        refl_dir = s_rd - 2.0 * np.sum(s_rd * n_opp, axis=1)[:, None] * n_opp
        acc_rgb[stay] += s_w[:, None] * fresnel[:, None] * env_color(refl_dir)
        acc_a[stay] += s_w * fresnel

        new_dir = eta[:, None] * s_rd + (
            eta * cosi - np.sqrt(np.maximum(k, 0.0))
        )[:, None] * n_opp
        new_dir = np.where(tir[:, None], refl_dir, new_dir)
        new_dir /= np.linalg.norm(new_dir, axis=1)[:, None]

        # Entering a cube flips state to IOR; exiting back to air.
        s_state = np.where(s_state > 1.0, 1.0, IOR)

        # Continue from the exit point so the ray does not re-hit the same box.
        s_tex = np.maximum(t_exit, t_enter + 1e-3)[hit]
        origin = s_ro + s_rd * s_tex[:, None] + new_dir * eps
        new_w = s_w * (1.0 - fresnel)
        new_tint = s_tint * TINT  # absorption whenever light crosses glass

        ro[stay] = origin
        rd[stay] = new_dir
        weight[stay] = new_w
        tint[stay] = new_tint
        state[stay] = s_state

    rgb = acc_rgb.reshape(-1, 3)
    alpha = np.clip(acc_a, 0.0, 1.0)
    return rgb, alpha


def trace(azimuth_deg):
    """Build the orthographic camera rays and trace them in bounded chunks so
    the whole frame never needs to live in memory at once."""
    d, u, v, scale, cx, cy = frame_camera(azimuth_deg)

    px = np.arange(W * AA) / AA + 0.5 / AA - W / 2
    py = np.arange(H * AA) / AA + 0.5 / AA - H / 2
    gx, gy = np.meshgrid(px, py)
    gx = gx.ravel()
    gy = gy.ravel()

    ro = (
        SCENE_CENTER
        + (gx[:, None] - cx) * (u / scale)[None, :]
        - (gy[:, None] - cy) * (v / scale)[None, :]
    ) - d[None, :] * 1000.0
    rd = np.tile(d[None, :], (len(gx), 1))

    n_rays = len(gx)
    rgb = np.zeros((n_rays, 3))
    alpha = np.zeros(n_rays)
    chunk = 32768
    for start in range(0, n_rays, chunk):
        end = min(start + chunk, n_rays)
        cr, ca = trace_chunk(ro[start:end], rd[start:end])
        rgb[start:end] = cr
        alpha[start:end] = ca
        print(f"  rays {start}-{end}/{n_rays}", flush=True)

    rgb = rgb.reshape(H * AA, W * AA, 3)
    alpha = alpha.reshape(H * AA, W * AA)

    # Projected screen positions of the stack base (z=0) and mid height.
    def screen_of(world):
        rel = np.array(world, dtype=np.float64) - SCENE_CENTER
        return (
            W / 2 + (np.dot(rel, u) - cx) * scale,
            H / 2 - (np.dot(rel, v) - cy) * scale,
        )

    base_screen = screen_of([0.0, 0.0, 0.0])
    mid_screen = screen_of([0.0, 0.0, 44.0])
    return rgb, alpha, base_screen, mid_screen


def composite(rgb, alpha, base_screen, mid_screen):
    """Downsample AA, then bake a soft ground shadow + ambient glow behind the
    glass (they show through the translucent cubes, like a real card)."""
    rgb = rgb.reshape(H, AA, W, AA, 3).mean(axis=(1, 3))
    alpha = alpha.reshape(H, AA, W, AA).mean(axis=(1, 3))
    a = np.clip(alpha, 0.0, 1.0)

    ys, xs = np.mgrid[0:H, 0:W]
    out_rgb = np.zeros((H, W, 3))
    out_a = np.zeros((H, W))

    # Ambient glow: radial red halo centred on the stack.
    glow_cx, glow_cy = mid_screen
    gd = np.sqrt(((xs - glow_cx) / (W * 0.34)) ** 2 + ((ys - glow_cy) / (H * 0.30)) ** 2)
    glow = np.clip(1.0 - gd, 0, 1) ** 2 * 0.30

    # Ground shadow: flat ellipse under the base.
    sh_cx, sh_cy = base_screen
    sd = np.sqrt(((xs - sh_cx) / (W * 0.30)) ** 2 + ((ys - sh_cy) / (H * 0.085)) ** 2)
    shadow = np.clip(1.0 - sd, 0, 1) ** 1.6 * 0.42

    bg_rgb = np.stack([0.72 * glow, 0.10 * glow, 0.14 * glow], axis=2) + np.stack(
        [0.20 * shadow, 0.01 * shadow, 0.03 * shadow], axis=2
    )
    bg_a = np.clip(glow + shadow, 0, 1) * 0.85

    out_rgb = rgb * a[..., None] + bg_rgb * bg_a[..., None] * (1.0 - a[..., None])
    out_a = a + bg_a * (1.0 - a)
    rgba = np.dstack([np.clip(out_rgb, 0, 1), np.clip(out_a, 0, 1)])
    return (rgba * 255.0).astype(np.uint8)


def main():
    sheet = np.zeros((H * ROWS, W * COLS, 4), dtype=np.uint8)
    for frame in range(FRAMES):
        # Smooth loop: azimuth sways -8..+8 deg, slight breathing scale.
        angle = 8.0 * np.sin(2.0 * np.pi * frame / FRAMES)
        rgb, alpha, base_screen, mid_screen = trace(angle)
        frame_rgba = composite(rgb, alpha, base_screen, mid_screen)
        row, col = divmod(frame, COLS)
        sheet[row * H:(row + 1) * H, col * W:(col + 1) * W] = frame_rgba
        print(f"frame {frame:02d} az={angle:+.1f}")

    target = os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
        "assets", "cubes", "court_card_cubes_sheet.png",
    )
    os.makedirs(os.path.dirname(target), exist_ok=True)
    Image.fromarray(sheet, "RGBA").save(target, optimize=True)
    print(f"wrote {target} ({os.path.getsize(target)} bytes, {FRAMES} frames)")


if __name__ == "__main__":
    main()
