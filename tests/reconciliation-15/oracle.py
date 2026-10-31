# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independent integer model for the previously frozen reconciliation protocol."""
import re
import sys

MINIMUM = -(2 ** 31)
MAXIMUM = 2 ** 31 - 1


class InvalidInput(ValueError):
	pass


def integer(text):
	if not re.fullmatch(r'-?[0-9]+', text):
		raise InvalidInput('signed decimal required')
	value = int(text)
	if not MINIMUM <= value <= MAXIMUM:
		raise InvalidInput('signed 32-bit range')
	return value


def parse(arguments):
	values = [integer(text) for text in arguments]
	if not values or values[0] < 0:
		raise InvalidInput('stock count')
	boundary = 1 + 4 * values[0]
	if boundary > len(values) or (len(values) - boundary) % 5:
		raise InvalidInput('complete stock/change groups required')
	stocks = []
	keys = set()
	for offset in range(1, boundary, 4):
		warehouse, sku, quantity, cost = values[offset:offset + 4]
		key = warehouse, sku
		if key in keys or quantity < 0 or cost < 0 or quantity * cost > MAXIMUM:
			raise InvalidInput('initial inventory')
		keys.add(key)
		stocks.append((key, quantity, cost))
	changes = []
	for offset in range(boundary, len(values), 5):
		warehouse, sku, delta, revision, reject = values[offset:offset + 5]
		if reject not in (0, 1):
			raise InvalidInput('audit flag')
		changes.append(((warehouse, sku), delta, revision, reject))
	return stocks, changes


def render(arguments):
	stocks, changes = parse(arguments)
	state = {key: [quantity, cost, 0] for key, quantity, cost in stocks}
	accepted = attempts = 0
	rows = [('astra-reconcile', 1)]
	for index, (key, delta, expected, reject) in enumerate(changes, 1):
		if key not in state:
			outcome, quantity, revision, value = 'unknown', -1, -1, -1
		else:
			quantity, cost, revision = state[key]
			proposed = quantity + delta
			if expected != revision:
				outcome = 'stale'
			elif proposed < 0:
				outcome = 'overdraw'
			elif proposed > MAXIMUM or revision == MAXIMUM or proposed * cost > MAXIMUM:
				outcome = 'overflow'
			else:
				attempts += 1
				if reject:
					outcome = 'audit-error'
				else:
					outcome = 'accepted'
					accepted += 1
					quantity, revision = proposed, revision + 1
					state[key] = [quantity, cost, revision]
			value = quantity * cost
		rows.append(('decision', index, *key, delta, expected, outcome,
			quantity, revision, value, accepted, attempts))
	for key, (quantity, cost, revision) in sorted(state.items()):
		rows.append(('stock', *key, quantity, cost, revision, quantity * cost))
	rows.append(('summary', len(changes), accepted, attempts))
	return ''.join('\t'.join(map(str, row)) + '\n' for row in rows).encode('ascii')


if __name__ == '__main__':
	try:
		sys.stdout.buffer.write(render(sys.argv[1:]))
	except InvalidInput:
		sys.exit(2)
