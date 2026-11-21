"""Measure the camera framing of the first forest battle against its Steam client capture."""

import argparse
import itertools
import math

from PIL import Image, ImageFilter


CLIENT_SIZE = (1022, 769)
# Hand-picked corners in the original client area, from the three stone arches and crystals.
LANDMARKS = (
    (149, 111), (244, 110), (353, 101), (380, 166), (454, 100), (564, 64),
    (641, 145), (687, 110), (802, 128), (827, 163), (913, 209), (199, 592), (812, 499),
)


def gradients(path, title_bar):
    with Image.open(path) as source:
        width, height = source.size
        client = (width, height - title_bar)
        if client != CLIENT_SIZE:
            raise ValueError(f"{path}: {client} client pixels after cropping {title_bar} rows, expected {CLIENT_SIZE}")
        area = source.crop((0, title_bar, width, height))
        gray = area.convert("L").filter(ImageFilter.GaussianBlur(1.05)).load()
    # Only the rectangles searched around our landmarks need derivatives.
    values = {}
    for cx, cy in LANDMARKS:
        for y in range(cy - 29, cy + 30):
            for x in range(cx - 29, cx + 30):
                values[(x, y)] = complex(gray[x + 1, y] - gray[x - 1, y],
                                         gray[x, y + 1] - gray[x, y - 1])
    return values


def match(original, port, x, y):
    coords = [(x + dx, y + dy) for dx, dy in itertools.product(range(-12, 13, 2), repeat=2)]
    template = [original[coord].conjugate() for coord in coords]
    template_energy = sum(abs(g) ** 2 for g in template)
    scores = []
    for dy in range(-17, 18):
        for dx in range(-17, 18):
            patch = [port[(u + dx, v + dy)] for u, v in coords]
            denom = math.sqrt(template_energy * sum(abs(g) ** 2 for g in patch))
            dot = sum(a * b for a, b in zip(template, patch)).real
            score = dot / denom if denom else -1
            scores.append((score, dx, dy))
    scores.sort(reverse=True)
    best, dx, dy = scores[0]
    second = next(score for score, u, v in scores if abs(dx - u) + abs(dy - v) >= 5)
    if best >= 0.43 and best - second >= 0.018 and max(abs(dx), abs(dy)) < 17:
        return complex(x, y), complex(x + dx, y + dy)
    return None


def fit(points):
    source_center = sum(p for p, _ in points) / len(points)
    target_center = sum(q for _, q in points) / len(points)
    numerator = sum((p - source_center).conjugate() * (q - target_center) for p, q in points)
    slope = numerator / sum(abs(p - source_center) ** 2 for p, _ in points)
    return slope, target_center - slope * source_center


def fit_landmarks(matches):
    best = []
    best_error = float("inf")
    for first, second in itertools.combinations(matches, 2):
        if abs(first[0] - second[0]) < 100:
            continue
        slope, origin = fit([first, second])
        stable = [(p, q) for p, q in matches if abs(slope * p + origin - q) < 2.5]
        error = sum(abs(slope * p + origin - q) for p, q in stable)
        if (len(stable), -error) > (len(best), -best_error):
            best, best_error = stable, error
    if len(best) < 3:
        raise ValueError("Insufficient matching geometry to estimate framing")
    slope, origin = fit(best)
    rms = (sum(abs(slope * p + origin - q) ** 2 for p, q in best) / len(best)) ** 0.5
    return slope, origin, rms, best


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("original", help="original first-battle screenshot")
    parser.add_argument("godot", help="Godot placement or combat screenshot without window borders")
    parser.add_argument("--title-bar", type=int, default=30, help="rows above the original client area")
    args = parser.parse_args()
    try:
        original = gradients(args.original, args.title_bar)
        port = gradients(args.godot, 0)
        matches = [match(original, port, x, y) for x, y in LANDMARKS]
        slope, origin, rms, stable = fit_landmarks([point for point in matches if point])
    except (OSError, ValueError) as error:
        parser.exit(1, f"{error}\n")
    print(f"{len(stable)}/{len(LANDMARKS)} landmarks, scale {abs(slope):.5f}, "
          f"origin shift ({origin.real:.2f}, {origin.imag:.2f}) px, fitted RMS {rms:.2f} px")


if __name__ == "__main__":
    main()
