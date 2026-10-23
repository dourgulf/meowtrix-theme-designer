"""Picks the LinkedIn Queens boards with a composition theme out of
shared/test-fixtures/legacy-hints/linkedin_boards.json into
shared/level-design/linkedin_themes.json, the
pattern references shown in the designer's reference window.

Run from tool/theme_designer: python3 tool/extract_references.py

The themes follow docs/LevelDesign.md section 8:
- symmetric: at least 85% of the cell borders (same Region or not) match
  under one mirror or rotation;
- repeated: two or more Regions of 4+ cells with the same shape (same
  orientation);
- backdrop: the largest Region covers at least 40% of the board.
"""

import argparse
import os
import collections
import json
import pathlib

HERE = pathlib.Path(__file__).resolve().parents[1]
ROOT = next((p for p in HERE.parents if (p / 'shared/level-design').is_dir()), None)
if os.environ.get('MEOWTRIX_WORKSPACE'):
    ROOT = pathlib.Path(os.environ['MEOWTRIX_WORKSPACE'])
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('source', nargs='?', type=pathlib.Path,
                    default=ROOT / 'shared/test-fixtures/legacy-hints/linkedin_boards.json' if ROOT else None)
parser.add_argument('--output', type=pathlib.Path,
                    default=ROOT / 'shared/level-design/linkedin_themes.json' if ROOT else HERE / 'references.json')
args = parser.parse_args()
if args.source is None:
    parser.error('Supply a source JSON or set MEOWTRIX_WORKSPACE')
SOURCE, TARGET = args.source, args.output

TRANSFORMS = [
    lambda n, r, c: (r, n - 1 - c),
    lambda n, r, c: (n - 1 - r, c),
    lambda n, r, c: (n - 1 - r, n - 1 - c),
    lambda n, r, c: (c, r),
    lambda n, r, c: (n - 1 - c, n - 1 - r),
    lambda n, r, c: (c, n - 1 - r),
]


def borders(n):
    for r in range(n):
        for c in range(n):
            if c + 1 < n:
                yield (r, c), (r, c + 1)
            if r + 1 < n:
                yield (r, c), (r + 1, c)


def symmetry(grid):
    n = len(grid)
    same = lambda a, b: grid[a[0]][a[1]] == grid[b[0]][b[1]]
    edges = list(borders(n))
    return max(
        sum(same(a, b) == same(f(n, *a), f(n, *b)) for a, b in edges) / len(edges)
        for f in TRANSFORMS
    )


def regions(grid):
    cells = collections.defaultdict(list)
    for r, row in enumerate(grid):
        for c, id in enumerate(row):
            cells[id].append((r, c))
    return cells.values()


def repeats(grid):
    def shape(cells):
        top = min(r for r, _ in cells)
        left = min(c for _, c in cells)
        return tuple(sorted((r - top, c - left) for r, c in cells))

    counts = collections.Counter(shape(c) for c in regions(grid) if len(c) >= 4)
    return max(counts.values(), default=0)


def themes(grid):
    n = len(grid)
    found = []
    if symmetry(grid) >= 0.85:
        found.append('symmetric')
    if repeats(grid) >= 2:
        found.append('repeated')
    if max(len(c) for c in regions(grid)) >= 0.4 * n * n:
        found.append('backdrop')
    return found


def main():
    boards = json.loads(SOURCE.read_text())
    picked = []
    for board in boards:
        found = themes(board['regionIDs'])
        if not found:
            continue
        solution = [0] * board['size']
        for r, c in board['solution']:
            solution[r] = c
        entry = {'id': board['id']}
        if 'date' in board:
            entry['date'] = board['date']
        entry.update(
            size=board['size'],
            themes=found,
            regionIDs=board['regionIDs'],
            solution=solution,
        )
        picked.append(entry)
    TARGET.parent.mkdir(exist_ok=True)
    TARGET.write_text(
        '[\n' + ',\n'.join(json.dumps(e, separators=(',', ':')) for e in picked) + '\n]\n'
    )
    tally = collections.Counter(t for e in picked for t in e['themes'])
    print(f'{len(picked)} of {len(boards)} boards: {dict(tally)}')


if __name__ == '__main__':
    main()
