# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Authored reconciliation inputs; expectations come only from oracle.py."""
from oracle import MAXIMUM


def scenarios():
	first, second, high, unknown = (7, 101), (-3, 202), (0, -9), (99, 99)
	stocks = [(first, 20, 4), (second, 12, 7), (high, MAXIMUM, 1)]
	changes = [
		(first, 3, 0, 0), (second, -2, 0, 0), (first, -100, 1, 0),
		(first, 1, 0, 0), (unknown, 0, 0, 0), (first, 4, 1, 1),
		(first, 4, 1, 0), (second, 0, 1, 0), (second, -10, 2, 0),
		(second, -1, 3, 0), (high, 1, 0, 0), (high, -1, 0, 0),
		(high, 1, 1, 0), (first, -7, 2, 0), (first, 0, 3, 1),
		(first, 0, 3, 0), (second, 5, 3, 0), (second, 2, 4, 1),
		(second, 2, 4, 0), (first, MAXIMUM, 4, 0), (unknown, -1, -1, 1),
		(first, -20, 4, 0), (first, 1, 5, 0), (high, 0, 0, 0),
	]
	variants = [('original', stocks, changes)]
	mapping = {first: (-88, 12), second: (41, -22), high: (2, 700), unknown: (-500, 6)}
	variants.append(('renamed-reordered', [(mapping[key], quantity, cost)
		for key, quantity, cost in reversed(stocks)],
		[(mapping[key], delta, revision, reject) for key, delta, revision, reject in changes]))
	variants.append(('different-values', [(first, 50, 9), (second, 10, 0), (high, 1, MAXIMUM)], changes))
	result = []
	for name, initial, commands in variants:
		arguments = [len(initial)]
		for key, quantity, cost in initial:
			arguments.extend([*key, quantity, cost])
		for key, delta, revision, reject in commands:
			arguments.extend([*key, delta, revision, reject])
		result.append((name, list(map(str, arguments))))
	return result
