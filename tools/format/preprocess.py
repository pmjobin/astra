"""Compare preprocessed tokens, mapping only identified assert diagnostic fields.

Assertion expression strings remain exact. Filename mappings must name the actual
source and line mappings must match corresponding raw assert invocation tokens.
No other coordinates or source-observable values are erased.
"""
import ast

from lexical import scan, compare


def compare_preprocessed(before, after, before_source, after_source, old_filename, new_filename):
	compare(before_source, after_source)
	x, y = scan(before), scan(after)
	if len(x) != len(y):
		raise ValueError('preprocessed token count changed')
	def assert_lines(data):
		text = data.decode()
		return [text.count('\n', 0, start) + 1 for token, start, end in scan(data) if token == 'assert']
	line_pairs = set(zip(assert_lines(before_source), assert_lines(after_source)))
	mappings = []
	allowed = set()
	for i, (word, start, end) in enumerate(x):
		if word != '__assert_fail' or i + 8 >= len(x) or x[i+1][0] != '(':
			continue
			# Actual glibc assert expansion: expression, file, line, function.
		if [x[i+j][0] for j in (3, 5, 7)] != [',', ',', ',']:
			continue
		if x[i+2][0] != y[i+2][0]:
			raise ValueError('assert expression diagnostic spelling changed')
		old_file, new_file = x[i+4][0], y[i+4][0]
		old_line, new_line = x[i+6][0], y[i+6][0]
		if old_file == new_file and old_line == new_line:
			continue
		if ast.literal_eval(old_file) != old_filename or ast.literal_eval(new_file) != new_filename:
			raise ValueError('unidentified assertion source path')
		if not old_line.isdecimal() or not new_line.isdecimal() or (int(old_line), int(new_line)) not in line_pairs:
			raise ValueError('assert diagnostic line does not match a source token mapping')
		allowed.update((i+4, i+6))
		mappings.append(dict(before_file=old_filename, after_file=new_filename,
			before_line=int(old_line), after_line=int(new_line), expression=ast.literal_eval(x[i+2][0])))
	for i, (a, b) in enumerate(zip(x, y)):
		if a[0] != b[0] and i not in allowed:
			raise ValueError('unreviewed preprocessed change at token ' + str(i) + ': ' + repr((a[0], b[0])))
	return mappings
