"""Compare three-height reconstruction with an independently integrated panel.

No engine, references or external packages needed. Relative errors include
the existing 1.15 * max(sample) safety cap. Heights and radiance match Level 0.
"""
import math

HEIGHT = 3.19
HS = (0.4, 1.65, 2.9)


def panel(r, y, n=48):
    side, d = 5 / 6, max(HEIGHT - y, 0)
    total = 0
    for i in range(n):
        x = r + ((i + 0.5) / n - 0.5) * side
        for j in range(n):
            z = ((j + 0.5) / n - 0.5) * side
            total += max(x, 0) * d / (x*x + z*z + d*d)**2
    return total * 12 * side**2 / n**2


def interpolate(xs, values, x):
    return sum(values[i] * math.prod((x-xs[j])/(xs[i]-xs[j])
               for j in range(3) if i != j) for i in range(3))


def reconstruct(es, y, physical):
    bound = max(es) * 1.15
    if physical and min(es) > 1e-5:
        ds = [HEIGHT - h for h in HS]
        q = interpolate([d*d for d in ds],
                        [math.sqrt(d/e) for d, e in zip(ds, es)],
                        max(HEIGHT-y, 0)**2)
        if q > 1e-4:
            return min(max(HEIGHT-y, 0) / q**2, bound)
    return min(math.exp(interpolate(HS, [math.log(max(e, 1e-4)) for e in es], y)), bound)


if __name__ == "__main__":
    print("distance  mean relative error: logarithmic / physical")
    for r in (0.43, 0.5, 0.75, 1, 2, 4, 8):
        samples = [panel(r, h) for h in HS]
        errors = [[], []]
        for i in range(63):
            y = 0.05 + i * 0.05
            exact = panel(r, y)
            for mode in (0, 1):
                errors[mode].append(abs(reconstruct(samples, y, mode)-exact) / max(exact, 1e-4))
        print(f"{r:8.2f}  " + " / ".join(f"{sum(e)/len(e):.3%}" for e in errors))
