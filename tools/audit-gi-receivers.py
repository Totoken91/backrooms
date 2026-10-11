"""Audit visible wall receivers against exported axis-aligned scene geometry.

Usage: python tools/audit-gi-receivers.py scene.json dim3
No image/reference is copied into the repository. Nine image-centre probes;
these describe geometry, not area-averaged irradiance ratios.
"""
import json
import math
import sys


def camera_ray(sx, sy, yaw):
    # Godot Player.place uses rotation.y = -yaw: clockwise heading.
    return (sx * math.cos(yaw) + math.sin(yaw), sy,
            sx * math.sin(yaw) - math.cos(yaw))


def intersect(origin, direction, box):
    lows = (box[0], box[4], box[1])
    highs = (box[2], box[5], box[3])
    enter, leave, normal = -math.inf, math.inf, (0, 0, 0)
    for axis in range(3):
        if abs(direction[axis]) < 1e-10:
            if not lows[axis] <= origin[axis] <= highs[axis]:
                return None
            continue
        a = (lows[axis] - origin[axis]) / direction[axis]
        b = (highs[axis] - origin[axis]) / direction[axis]
        near, far = min(a, b), max(a, b)
        if near > enter:
            enter = near
            normal = tuple((-1 if a < b else 1) if i == axis else 0 for i in range(3))
        leave = min(leave, far)
    return (enter, normal) if leave >= max(enter, 0) and enter > 1e-5 else None


def room_gap(boxes, x, z, ceiling):
    spans = [(-10, 0), (ceiling, 100)]
    spans += [(b[4], b[5]) for b in boxes if b[0] <= x < b[2] and b[1] <= z < b[3]]
    merged = []
    for lo, hi in sorted(spans):
        if merged and lo <= merged[-1][1] + 1e-5:
            merged[-1][1] = max(merged[-1][1], hi)
        else:
            merged.append([lo, hi])
    return (merged[0][1], merged[1][0]) if len(merged) > 1 else (100, 100)


def main():
    if sys.argv[1:] == ["--self-test"]:
        assert camera_ray(0, 0, 0) == (0, 0, -1)
        assert abs(camera_ray(0, 0, math.pi/2)[0] - 1) < 1e-9
        assert abs(camera_ray(1, 0, math.pi/2)[2] - 1) < 1e-9
        assert intersect((0, 1, 0), (1, 0, 0), [2, -1, 3, 1, 0, 3.2]) == (2, (-1, 0, 0))
        assert intersect((0, 4, 0), (1, 0, 0), [2, -1, 3, 1, 0, 3.2]) is None
        assert room_gap([[0, 0, 2.5, 2.5, 0, .5]], 1, 1, 3.2) == (.5, 3.2)
        assert room_gap([[0, 0, 2.5, 2.5, 1.3, 3.2]], 1, 1, 3.2) == (0, 1.3)
        assert room_gap([[0, 0, 2.5, 2.5, 0, 3.2]], 1, 1, 3.2) == (100, 100)
        print("PASS: box intersections and room gaps")
        return
    scene = json.load(open(sys.argv[1], encoding="utf-8"))
    x, z, yaw = scene["views"][sys.argv[2]]
    origin = (x, scene["eye"], z)
    boxes = scene["boxes"]
    ceiling = scene["height"]
    ceilings = {(x, z): h for x, z, h in scene.get("ceilings", [])}
    geometry = list(boxes)
    cell = scene["cell"]
    for fx, fz in scene["floors"]:
        for lo, hi in [(-.01, 0), (ceilings.get((fx, fz), ceiling), 100)]:
            geometry.append([fx*cell, fz*cell, (fx+1)*cell, (fz+1)*cell, lo, hi])
    tangent = math.tan(math.radians(scene["fov"]) / 2)
    for row in range(3):
        for col in range(3):
            sx = (2 * (col + .5) / 3 - 1) * tangent * 4 / 3
            sy = (1 - 2 * (row + .5) / 3) * tangent
            direction = camera_ray(sx, sy, yaw)
            hits = [h for b in geometry if (h := intersect(origin, direction, b))]
            if not hits:
                print(row, col, "no exported surface")
                continue
            t, normal = min(hits, key=lambda h: h[0])
            p = tuple(origin[i] + t * direction[i] for i in range(3))
            if normal[1]:
                print(row, col, "horizontal", tuple(round(v, 3) for v in p), normal)
                continue
            at = (p[0] + .13 * normal[0], p[2] + .13 * normal[2])
            # Nearest lightmap receiver; full bilinear reconstruction uses four.
            q = tuple((math.floor(v / .25) + .5) * .25 for v in at)
            gap = room_gap(boxes, *q, ceilings.get((math.floor(q[0] / cell), math.floor(q[1] / cell)), ceiling))
            nx = nz = 0
            for k in range(1, 5):
                r = k * .125
                for dx, dz in [(r, 0), (-r, 0), (0, r), (0, -r)]:
                    g = room_gap(boxes, q[0] + dx, q[1] + dz, ceilings.get((math.floor((q[0] + dx) / cell), math.floor((q[1] + dz) / cell)), ceiling))
                    if g[1] - g[0] < .1:
                        nx -= 1 if dx > 0 else -1 if dx < 0 else 0
                        nz -= 1 if dz > 0 else -1 if dz < 0 else 0
            length = math.hypot(nx, nz)
            estimated = (round(nx/length, 3), round(nz/length, 3)) if length else "four-wall average"
            print(row, col, "wall", tuple(round(v, 3) for v in p), "normal", normal,
                  "gather_y", round(sum(gap)/2, 3), "gather_normal", estimated)


if __name__ == "__main__":
    main()
