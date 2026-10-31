# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""B2 independent BFS oracle; production Astra must use disjoint-set merging."""
from collections import deque
import random
import struct

SEED = 1879950433
INPUT_MAGIC = 0x494d4732
OUTPUT_MAGIC = 0x434d5032
HEADER = struct.Struct('<IIII')
COMPONENT = struct.Struct('<IIIIIIq')
AUDIT = struct.Struct('<IIq')


def reconcile(data):
	if len(data) < HEADER.size: raise ValueError('image header extent')
	magic, width, height, threshold = HEADER.unpack_from(data)
	if magic != INPUT_MAGIC or width > 257 or height > 129 or threshold > 255 or bool(width) != bool(height):
		raise ValueError('image header values')
	if len(data) != HEADER.size + width * height * 3: raise ValueError('image RGB extent')
	mask, scores, audits = [], [], []
	for y in range(height):
		selected, total = 0, 0
		for x in range(width):
			r, g, b = data[HEADER.size + 3 * (y * width + x):HEADER.size + 3 * (y * width + x) + 3]
			score = 2 * r + g + b if y % 4 & 1 else r + 2 * g + b
			in_a = width // 7 <= x < width - width // 5 and height // 6 <= y < height - height // 7
			in_b = width // 3 <= x < width - width // 9 and height // 3 <= y < height - height // 5
			foreground = in_a != in_b and score >= 4 * threshold
			mask.append(foreground); scores.append(score)
			if foreground: selected += 1; total += score
		audits.append((y, selected, total))
	labels, components = [0] * (width * height), []
	for first in range(width * height):
		if not mask[first] or labels[first]: continue
		label = first + 1; labels[first] = label; pending = deque([first])
		area, min_x, min_y, max_x, max_y, total = 0, width, height, 0, 0, 0
		while pending:
			index = pending.popleft(); x, y = index % width, index // width
			area += 1; min_x = min(min_x, x); max_x = max(max_x, x); min_y = min(min_y, y); max_y = max(max_y, y); total += scores[index]
			neighbors = []
			if x: neighbors.append(index - 1)
			if x + 1 < width: neighbors.append(index + 1)
			if y: neighbors.append(index - width)
			if y + 1 < height: neighbors.append(index + width)
			for neighbor in neighbors:
				if mask[neighbor] and not labels[neighbor]: labels[neighbor] = label; pending.append(neighbor)
		components.append((label, area, min_x, min_y, max_x, max_y, total))
	output = HEADER.pack(OUTPUT_MAGIC, width, height, len(components))
	output += b''.join(struct.pack('<I', label) for label in labels)
	output += b''.join(COMPONENT.pack(*row) for row in components)
	output += b''.join(AUDIT.pack(*row) for row in audits)
	return output, dict(width=width, height=height, threshold=threshold, foreground=sum(mask),
		components=components, labels=labels, audits=audits, mask=mask, scores=scores)


def generate(width, height, seed=SEED):
	assert 0 <= width <= 257 and 0 <= height <= 129 and bool(width) == bool(height)
	rng = random.Random(seed); pixels = bytearray()
	threshold = 64 + (seed ^ (width * 17) ^ (height * 31)) % 128
	for y in range(height):
		for x in range(width):
			color = tuple(rng.randrange(256) for _ in range(3))
			if (3 * x + 5 * y + seed) % 19 < 5: color = (8, 16, 24)
			if x % 17 in (0, 1): color = (244, 236, 228)
			pixels.extend(color)
	return HEADER.pack(INPUT_MAGIC, width, height, threshold) + pixels


def controls():
	output, empty = reconcile(HEADER.pack(INPUT_MAGIC, 0, 0, 100))
	assert output == HEADER.pack(OUTPUT_MAGIC, 0, 0, 0) and empty['components'] == []
	_, white = reconcile(HEADER.pack(INPUT_MAGIC, 7, 5, 100) + bytes([255, 255, 255]) * 35)
	assert white['components'] == [(2, 13, 1, 0, 5, 4, 13260), (14, 3, 6, 1, 6, 3, 3060)]
	assert white['audits'] == [(0, 5, 5100), (1, 2, 2040), (2, 2, 2040), (3, 2, 2040), (4, 5, 5100)]
	_, red = reconcile(HEADER.pack(INPUT_MAGIC, 7, 5, 100) + bytes([255, 0, 0]) * 35)
	assert [row[0] for row in red['components']] == [9, 14, 23, 28] and red['foreground'] == 4
	_, dark = reconcile(HEADER.pack(INPUT_MAGIC, 7, 5, 100) + bytes(105))
	assert dark['foreground'] == 0 and not dark['components'] and not any(dark['labels'])
	for data in [b'', HEADER.pack(0, 0, 0, 0), HEADER.pack(INPUT_MAGIC, 0, 1, 0),
		HEADER.pack(INPUT_MAGIC, 258, 1, 0), HEADER.pack(INPUT_MAGIC, 1, 130, 0),
		HEADER.pack(INPUT_MAGIC, 0, 0, 256), HEADER.pack(INPUT_MAGIC, 1, 1, 0),
		HEADER.pack(INPUT_MAGIC, 0, 0, 0) + b'x']:
		try:
			reconcile(data)
			raise AssertionError('invalid image framing accepted')
		except ValueError: pass
	for width, height in [(0, 0), (7, 5), (31, 17), (127, 65), (257, 129)]:
		_, result = reconcile(generate(width, height))
		assert len(result['labels']) == width * height and sum(row[1] for row in result['components']) == result['foreground']
	return 'B2 hand-computed topology/color/empty controls, malformed framing and all fixed sizes pass'


if __name__ == '__main__': print(controls())
