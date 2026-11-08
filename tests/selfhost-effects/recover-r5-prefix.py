#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Exact unary source witnesses; checked outcomes must actually enter catch."""


def corpus():
	rows = {
		'prefix-bool-success': 'bool inverse(bool value) { return !value; } int main() { if (inverse(false)) { if (!inverse(true)) return 42; } return 3; }\n',
		'prefix-signed-min-success': 'int inverse(int value) { return -value; } int main() { int value = 0 - 2147483647 - 1; if (inverse(value) == value) return 42; return 3; }\n',
		'prefix-u64-success': 'u64 inverse(u64 value) { return ~value; } int main() { if (inverse(18446744073709551573) == 42) return 42; return 3; }\n',
		'prefix-plus-success': 'i16 identity(i16 value) { return +value; } int main() { if (identity(42) == 42) return 42; return 3; }\n',
		'prefix-folded-bool-success': 'int main() { if (!false) { if (!(!true)) return 42; } return 3; }\n',
	}
	for name, type_name, condition, argument in [
		('not', 'bool', '!value', 'false'),
		('double-not', 'bool', '!!value', 'true'),
		('negative', 'int', '-value == 42', '0 - 42'),
		('complement', 'int', '~value == 42', '0 - 43'),
		('u8-complement', 'u8', '~value == 42', '213'),
		('u32-complement', 'u32', '~value == 42', '4294967253'),
		('positive', 'i16', '+value == 42', '42'),
		('nested-negative', 'int', '-(-value) == 42', '42'),
	]:
		rows['prefix-'+name+'-error'] = 'int leaf('+type_name+' value) throws Error { if ('+condition+') { throw new Error("'+name+'"); } return 3; } int main() { try { return leaf('+argument+'); } catch (Error caught) { if (caught.message == "'+name+'") return 42; return 4; } }\n'
	assert len(rows) == len(set(rows.values())) == 13
	return rows
