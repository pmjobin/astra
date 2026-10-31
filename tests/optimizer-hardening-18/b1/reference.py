# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""B1 independent dictionary-snapshot oracle and deterministic journal inputs."""
import random
import struct

SEED = 1666689098
RECORD = struct.Struct('<IBBHii')
RESULT = struct.Struct('<iiiiq')
STATE = struct.Struct('<iiiii')
MAGIC = 0x4a4f5531
LIMIT = 1000000


def reconcile(data):
	if len(data) % RECORD.size or len(data) // RECORD.size > 8193:
		raise ValueError('journal byte extent')
	items = [RECORD.unpack_from(data, offset) for offset in range(0, len(data), RECORD.size)]
	accounts, results = {}, []
	start = 0
	while start < len(items):
		tx, shard = items[start][:2]
		if tx != len(results) or shard >= 4:
			raise ValueError('journal transaction/shard order')
		end = start + 1
		while end < len(items) and items[end][0] == tx:
			if items[end][1] != shard:
				raise ValueError('mixed transaction shards')
			end += 1
		before = dict(accounts)
		code, failed, checksum = 0, -1, 0
		for index, (_, _, op, key, expected, value) in enumerate(items[start:end]):
			version, balance, present = accounts.get((shard, key), (0, 0, False))
			if key >= 32:
				code = 2
			elif expected != version:
				code = 3
			elif op in (0, 1):
				next_value = balance + value if op == 0 else value
				if not -LIMIT <= next_value <= LIMIT:
					code = 4
				else:
					version, balance, present = version + 1, next_value, True
			elif op == 2:
				version, balance, present = version + 1, 0, False
			elif op != 3:
				code = 5
			if code:
				failed = index
				accounts = before
				checksum = 0
				break
			accounts[(shard, key)] = version, balance, present
			checksum += balance * (19 if tx & 1 else 17) + version * 3 + present
		results.append((tx, code, failed, end - start, checksum))
		start = end
	states = [(shard, key, *accounts.get((shard, key), (0, 0, False)))
		for shard in range(4) for key in range(32)]
	output = struct.pack('<II', MAGIC, len(results))
	output += b''.join(RESULT.pack(*row) for row in results)
	output += b''.join(STATE.pack(*row) for row in states)
	return output, {'transactions': len(results), 'committed': sum(row[1] == 0 for row in results),
		'failed': sum(row[1] != 0 for row in results), 'records': len(items), 'results': results, 'states': states}


def generate(count, seed=SEED):
	assert 0 <= count <= 8193
	rng = random.Random(seed)
	current = [[(0, 0, False) for _ in range(32)] for _ in range(4)]
	data, used, tx = bytearray(), 0, 0
	widths = (1, 2, 3, 7, 17, 31)
	while used < count:
		length = min(widths[tx % len(widths)], count - used)
		shard = rng.randrange(4)
		staged = list(current[shard])
		bad = tx % 5 == 4
		fault = (tx // 5) % 4
		previous = rng.randrange(32)
		for index in range(length):
			key = previous if index % 3 else rng.randrange(32)
			previous = key
			version, balance, present = staged[key]
			op = rng.randrange(4)
			value = rng.randint(-63, 63)
			expected = version
			if bad and index == length - 1:
				if fault == 0:
					expected += 17
				elif fault == 1:
					key += 32
				elif fault == 2:
					op, value = 1, LIMIT + 1
				else:
					op = 99
			data.extend(RECORD.pack(tx, shard, op, key, expected, value))
			if key < 32 and expected == version and op in (0, 1, 2, 3):
				if op == 0:
					staged[key] = version + 1, balance + value, True
				elif op == 1:
					staged[key] = version + 1, value, True
				elif op == 2:
					staged[key] = version + 1, 0, False
		if not bad:
			current[shard] = staged
		used += length
		tx += 1
	return bytes(data)


def controls():
	# Hand-worked results; the failed replacement must restore the earlier account.
	items = [(0, 0, 0, 2, 0, 5), (0, 0, 3, 2, 1, 0),
		(1, 0, 1, 2, 1, 7), (1, 0, 0, 2, 99, 3), (2, 0, 3, 2, 1, 0)]
	_, result = reconcile(b''.join(RECORD.pack(*row) for row in items))
	assert result['results'] == [(0, 0, -1, 2, 178), (1, 3, 1, 2, 0), (2, 0, -1, 1, 89)]
	assert result['states'][2] == (0, 2, 1, 5, True)
	# Two updates of one key before a late fault must both roll back.
	items = [(0, 0, 0, 3, 0, 8), (0, 0, 0, 3, 1, 4), (0, 0, 99, 3, 2, 0)]
	_, result = reconcile(b''.join(RECORD.pack(*row) for row in items))
	assert result['results'] == [(0, 5, 2, 3, 0)] and result['states'][3] == (0, 3, 0, 0, False)
	for data in [b'x', RECORD.pack(1, 0, 0, 0, 0, 1), RECORD.pack(0, 4, 0, 0, 0, 1),
		RECORD.pack(0, 0, 0, 0, 0, 1) + RECORD.pack(0, 1, 3, 0, 1, 0)]:
		try:
			reconcile(data)
			raise AssertionError('invalid framing accepted')
		except ValueError:
			pass
	for count in (0, 7, 513, 4093, 8193):
		_, result = reconcile(generate(count))
		assert result['records'] == count
		assert result['failed'] == result['transactions'] // 5
	return 'B1 hand-computed rollback, malformed framing and generator coverage controls pass'


if __name__ == '__main__':
	print(controls())
