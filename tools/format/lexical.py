"""Conservative positioned tokens for preservation checks; not a semantic parser.

Derived from ENVIC's vala_lexical_guard.py (R98, see format/PROVENANCE.md).
Directives include their continued lines. Unknown punctuation fails closed.
"""
import re

NUMBER = re.compile(r'(?:0[xX][0-9a-fA-F_]+|0[bB][01_]+|(?:[0-9][0-9_]*(?:\.[0-9_]*)?|\.[0-9][0-9_]*)(?:[eEpP][+-]?[0-9_]+)?)[uUlLfFdDmM]*')
WORD = re.compile(r'(?:[^\W\d]|_)[\w]*', re.UNICODE)
OPERATORS = sorted(('>>=', '<<=', '...', '??', '?.', '=>', '->', '::', '++', '--', '==', '!=', '<=', '>=', '&&', '||', '+=', '-=', '*=', '/=', '%=', '&=', '|=', '^=', '<<', '>>', '##'), key=len, reverse=True)


def scan(data, javascript=False):
	text = data.decode('utf-8')
	out = []
	i = 0
	while i < len(text):
		if text[i].isspace():
			i += 1
			continue
		start = i
		if text.startswith('//', i):
			end = text.find('\n', i)
			i = len(text) if end < 0 else end
		elif text.startswith('/*', i):
			end = text.find('*/', i + 2)
			if end < 0:
				raise ValueError('unterminated comment')
			i = end + 2
		elif text.startswith('"""', i):
			end = text.find('"""', i + 3)
			if end < 0:
				raise ValueError('unterminated multiline literal')
			i = end + 3
		elif text[i] in ('"', "'") or (javascript and text[i] == '`') or text.startswith('@"', i):
			if text.startswith('@"', i):
				i += 1
			quote = text[i]
			i += 1
			while i < len(text):
				if text[i] == '\\':
					i += 2
				elif text[i] == quote:
					i += 1
					break
				else:
					i += 1
			else:
				raise ValueError('unterminated quoted literal')
		elif javascript and text[i] == '/' and out and out[-1][0] in ('(', '=', ',', ':', 'return'):
			i += 1
			bracket = False
			while i < len(text):
				if text[i] == '\\':
					i += 2
					continue
				if text[i] == '[':
					bracket = True
				if text[i] == ']':
					bracket = False
				if text[i] == '/' and not bracket:
					i += 1
					while i < len(text) and text[i].isalpha():
						i += 1
					break
				i += 1
			else:
				raise ValueError('unterminated JS regex literal')
		elif text[i] == '#' and not text[text.rfind('\n', 0, i) + 1:i].strip():
			while True:
				end = text.find('\n', i)
				if end < 0:
					i = len(text)
					break
				i = end + 1
				if not text[start:end].endswith('\\'):
					break
		else:
			match = WORD.match(text, i) or NUMBER.match(text, i)
			if match:
				i = match.end()
			else:
				op = next((op for op in OPERATORS if text.startswith(op, i)), None)
				if not op and text[i] not in '{}[]().,;:?~!+-*/%&|^<>=@#$\\':
					raise ValueError('unreviewed lexical character: ' + repr(text[i]))
				i += len(op) if op else 1
		out.append((text[start:i], start, i))
	return out


def compare(before, after):
	a, b = [t[0] for t in scan(before)], [t[0] for t in scan(after)]
	if a != b:
		index = next((i for i, pair in enumerate(zip(a, b)) if pair[0] != pair[1]), min(len(a), len(b)))
		raise ValueError('tokens/comments/literals/directives changed at ' + str(index) + ': ' + repr((a[index:index+2], b[index:index+2])))


def call_interiors(data):
	# A header can define even a lowercase call spelling as a macro. Whitespace
	# within its arguments can be observable through # stringification. Keep
	# every identifier-call/declaration interior, rather than guessing macros.
	tokens = scan(data)
	controls = {'if', 'for', 'while', 'switch', 'sizeof', 'alignof', '_Alignof', '_Generic', 'decltype', 'typeid', 'catch'}
	ranges = []
	end = -1
	for index in range(1, len(tokens)):
		word, start, stop = tokens[index]
		name = tokens[index-1][0]
		if word != '(' or start < end or name in controls or not WORD.fullmatch(name):
			continue
		depth = 1
		for close in tokens[index+1:]:
			depth += int(close[0] == '(') - int(close[0] == ')')
			if depth == 0:
				ranges.append((index, stop, close[1]))
				end = close[2]
				break
		else:
			raise ValueError('unbalanced call/declaration parentheses')
	return ranges


def preserve_call_interiors(before, after):
	compare(before, after)
	a, b = call_interiors(before), call_interiors(after)
	if len(a) != len(b) or [x[0] for x in a] != [x[0] for x in b]:
		raise ValueError('call/declaration boundaries changed')
	old, new = before.decode('utf-8'), after.decode('utf-8')
	for (_, left, right), (_, start, end) in reversed(list(zip(a, b))):
		new = new[:start] + old[left:right] + new[end:]
	result = new.encode('utf-8')
	compare(before, result)
	return result
	return True


def attach_clauses(data):
	text = data.decode()
	stream = scan(data)
	for i in range(len(stream) - 1, 0, -1):
		word, start, _ = stream[i]
		previous, _, end = stream[i - 1]
		if word in ('catch', 'finally', 'else') and previous == '}':
			text = text[:end] + ' ' + text[start:]
	return text.encode()


def expand_accessors(data):
	text = data.decode()
	stream = scan(data)
	edits = []
	for i, (word, start, _) in enumerate(stream[:-1]):
		if word not in ('get', 'set') or stream[i+1][0] != '{':
			continue
		depth, j, semicolons = 1, i + 2, []
		while j < len(stream) and depth:
			part = stream[j][0]
			depth += (part == '{') - (part == '}')
			if part == ';':
				semicolons.append(j)
			j += 1
		if depth:
			raise ValueError('unclosed accessor')
		if len(semicolons) > 1 and '\n' not in text[start:stream[j-1][2]]:
			for k in [i + 1, *semicolons]:
				left, right = stream[k][2], stream[k+1][1]
				edits.append((left, right, '\n'))
	for left, right, value in sorted(set(edits), reverse=True):
		text = text[:left] + value + text[right:]
	return text.encode()
