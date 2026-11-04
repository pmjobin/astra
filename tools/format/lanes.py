"""Small language adapters and independent preservation checks."""
import ast
import io
import json
from pathlib import Path
import re
import subprocess
import tempfile
import tokenize

from lexical import compare, scan, attach_clauses, expand_accessors, preserve_call_interiors


def run(argv, data=None, timeout=30):
	p = subprocess.run(list(map(str, argv)), input=data, capture_output=True, timeout=timeout)
	if p.returncode or b'unknown option' in p.stderr.lower():
		raise ValueError('tool refused input/config: ' + repr(argv) + ': ' + p.stderr.decode(errors='replace')[-2000:])
	return p.stdout


def python_tokens(data):
	return list(tokenize.tokenize(io.BytesIO(data).readline))


def python_guard(before, after):
	def model(data):
		items = [(t.type, '' if t.type in (tokenize.INDENT, tokenize.DEDENT) else t.string)
			for t in python_tokens(data) if t.type not in (tokenize.NL, tokenize.NEWLINE, tokenize.ENDMARKER)]
		return ast.dump(ast.parse(data, type_comments=True), include_attributes=False), items
	if model(before) != model(after):
		raise ValueError('Python AST/block structure/comment/literal identity changed')


def python_format(data):
	# Only leading layout of token-bearing physical lines changes. Multiline
	# tokens, f-string payloads and every intra-line byte stay exact.
	tokens = python_tokens(data)
	lines = data.decode('utf-8').splitlines(keepends=True)
	protected, depths, stack = set(), {}, ['']
	fstrings = []
	for t in tokens:
		if t.type == getattr(tokenize, 'FSTRING_START', -1):
			fstrings.append(t.start[0])
		if fstrings:
			protected.update(range(fstrings[0] + 1, t.end[0] + 1))
		if t.type == getattr(tokenize, 'FSTRING_END', -1):
			fstrings.pop()
		if t.type == tokenize.INDENT:
			stack.append(t.string)
		elif t.type == tokenize.DEDENT:
			stack.pop()
		elif t.type not in (tokenize.NL, tokenize.NEWLINE, tokenize.ENCODING, tokenize.ENDMARKER):
			depths.setdefault(t.start[0], (len(stack) - 1, stack[-1]))
		if t.end[0] > t.start[0]:
			protected.update(range(t.start[0] + 1, t.end[0] + 1))
	for row, (depth, prefix) in depths.items():
		if row in protected or row > len(lines):
			continue
		line = lines[row - 1]
		leading = re.match(r'[ \t]*', line)[0]
		# Continuations get one extra tab; block indentation follows tokenize.
		extra = int(len(leading.expandtabs(8)) > len(prefix.expandtabs(8)))
		lines[row - 1] = '\t' * (depth + extra) + line[len(leading):]
	return ''.join(lines).encode()


def meson_model(data):
	from mesonbuild.mparser import Parser, Lexer
	ignored = {'lineno', 'colno', 'filename', 'end_lineno', 'end_colno', 'whitespaces',
		'pre_whitespaces', 'level', 'ast_id', 'condition_level', 'bytespan'}
	def model(value):
		if isinstance(value, list):
			return [model(x) for x in value]
		if isinstance(value, dict):
			return [(model(k), model(v)) for k, v in value.items()]
		if hasattr(value, '__dict__'):
			return (type(value).__name__, {k: model(v) for k, v in vars(value).items() if k not in ignored})
		return value
	text = data.decode()
	tokens = [(t.tid, text[t.bytespan[0]:t.bytespan[1]]) for t in Lexer(text).lex('unit') if t.tid not in ('eol', 'whitespace')]
	return model(Parser(text, 'unit').parse()), tokens


def meson_guard(before, after):
	if meson_model(before) != meson_model(after):
		raise ValueError('Meson parser/token/comment/literal identity changed')


def meson_format(data):
	from mesonbuild.mparser import Parser, Lexer
	text = data.decode()
	Parser(text, 'unit').parse()
	lines = text.splitlines(keepends=True)
	depth, parens = 0, 0
	first, protected = set(), set()
	for t in Lexer(text).lex('unit'):
		if t.tid in ('eol', 'whitespace'):
			continue
		if t.lineno not in first:
			indent = depth - int(t.tid in ('elif', 'else', 'endif', 'endforeach'))
			indent += int(parens > 0 and t.tid not in ('rparen', 'rbracket', 'rcurl'))
			if t.lineno not in protected:
				lines[t.lineno - 1] = '\t' * max(0, indent) + lines[t.lineno - 1].lstrip(' \t')
			first.add(t.lineno)
		if t.tid in ('if', 'foreach'):
			depth += 1
		elif t.tid in ('endif', 'endforeach'):
			depth -= 1
		parens += int(t.tid in ('lparen', 'lbracket', 'lcurl')) - int(t.tid in ('rparen', 'rbracket', 'rcurl'))
		protected.update(range(t.lineno + 1, t.lineno + text[t.bytespan[0]:t.bytespan[1]].count('\n') + 1))
	return ''.join(lines).encode()


def shell_model(data, tool, name):
	model = json.loads(run([tool, '--filename', name, '--to-json'], data))
	def strip(value):
		if isinstance(value, dict):
			return {k: strip(v) for k, v in value.items() if not (isinstance(v, dict) and set(v) == {'Offset', 'Line', 'Col'})}
		if isinstance(value, list):
			return [strip(v) for v in value]
		return value
	return strip(model)


def format_once(lane, data, name, root, tools):
	if lane == 'vala':
		return attach_clauses(run([tools['uncrustify'], '-q', '-c', root/'format/vala.cfg', '-l', 'VALA'], expand_accessors(data)))
	if lane == 'python':
		return python_format(data)
	if lane in ('c', 'cpp', 'javascript'):
		original = data
		if lane != 'javascript':
			data = shield_directives(data)
		result = run([tools['clang-format'], '--style=file:' + str(root/'format/clang-format.yaml'), '--assume-filename=' + name], data)
		if lane != 'javascript':
			result = re.sub(rb'(?m)^[ \t]*// clang-format (?:off|on): ASTRA_DIRECTIVE_GUARD\n', b'', result)
			result = enum_indentation(result)
			result = preserve_call_interiors(original, result)
		return result
	if lane == 'meson':
		return meson_format(data)
	if lane == 'shell':
		return run([tools['shfmt'], '--filename', name, '-i', '0', '-ci'], data)
	if lane == 'astra':
		with tempfile.TemporaryDirectory(prefix='astra-format-') as scratch:
			path = Path(scratch)/'source.astra'
			path.write_bytes(data)
			return run([tools['astrac'], '--format', path])
	raise ValueError('unqualified language lane ' + lane)


def enum_indentation(data):
	# Clang 23 classifies inline enum continuations as alignment only. Retain
	# one tab per lexical indentation level, with spaces for alignment, as in
	# the qualified Clang 22 profile. Visual columns and tokens stay exact.
	text = data.decode('utf-8')
	stack, changes = [], []
	pending = None
	for token, start, end in scan(data):
		line = text.rfind('\n', 0, start) + 1
		prefix = text[line:start]
		if token == 'enum':
			leading = re.match(r'[ \t]*', prefix)[0]
			pending = len(leading.expandtabs(4)) + 4
		elif token == '{':
			stack.append(pending)
			pending = None
		elif token == '}':
			if stack:
				stack.pop()
			pending = None
		elif token in (';', '(', '='):
			pending = None
		elif stack and stack[-1] is not None and prefix and not prefix.strip() and (token[0].isalpha() or token[0] == '_'):
			columns = len(prefix.expandtabs(4))
			indent = stack[-1]
			if columns >= indent:
				replacement = '\t' * (indent // 4) + ' ' * (columns - indent)
				if replacement != prefix:
					changes.append((line, start, replacement))
	for start, end, replacement in reversed(changes):
		text = text[:start] + replacement + text[end:]
	return text.encode('utf-8')


def shield_directives(data):
	if b'ASTRA_DIRECTIVE_GUARD' in data:
		raise ValueError('reserved directive guard marker in source')
	text = data.decode()
	for token, start, end in reversed(scan(data)):
		if token.startswith('#'):
			line_start = text.rfind('\n', 0, start) + 1
			if not token.endswith('\n'):
				raise ValueError('directive requires final newline')
			text = text[:line_start] + '// clang-format off: ASTRA_DIRECTIVE_GUARD\n' + text[line_start:end] + '// clang-format on: ASTRA_DIRECTIVE_GUARD\n' + text[end:]
	return text.encode()


def guard(lane, before, after, name, tools):
	if lane == 'python':
		python_guard(before, after)
	elif lane == 'meson':
		meson_guard(before, after)
	elif lane == 'shell':
		if shell_model(before, tools['shfmt'], name) != shell_model(after, tools['shfmt'], name):
			raise ValueError('shell AST/payload changed')
	elif lane == 'javascript':
		if [t[0] for t in scan(before, True)] != [t[0] for t in scan(after, True)]:
			raise ValueError('JavaScript tokens/regex/template/comment payload changed')
		run([tools['node'], '--check'], after)
	elif lane == 'astra':
		# Only parser-approved braces may disappear. Every other token and
		# every comment/literal/directive remains byte-exact. The independent
		# syntax dump retains normalized lexical scopes for implicit bodies.
		old = [t[0] for t in scan(before)]
		new = [t[0] for t in scan(after)]
		index = 0
		removed = []
		for token in old:
			if index < len(new) and token == new[index]:
				index += 1
			elif token in ('{', '}'):
				removed.append(token)
			else:
				raise ValueError('Astra unapproved token/comment/literal/directive change')
		if index != len(new) or removed.count('{') != removed.count('}'):
			raise ValueError('Astra unbalanced or inserted syntax change')
		with tempfile.TemporaryDirectory(prefix='astra-ast-guard-') as scratch:
			path = Path(scratch)/'source.astra'
			path.write_bytes(before)
			original = run([tools['astrac'], '--dump-syntax', path])
			path.write_bytes(after)
			if original != run([tools['astrac'], '--dump-syntax', path]):
				raise ValueError('Astra normalized AST or lexical scope changed')
	else:
		compare(before, after)


def stable_format(lane, data, name, root, tools):
	first = format_once(lane, data, name, root, tools)
	guard(lane, data, first, name, tools)
	second = format_once(lane, first, name, root, tools)
	guard(lane, first, second, name, tools)
	if lane == 'vala':
		third = format_once(lane, second, name, root, tools)
		guard(lane, second, third, name, tools)
		if third != second:
			raise ValueError('Vala two-pass pipeline is unstable')
		return second
	if first != second:
		raise ValueError('formatter pipeline is unstable')
	return first
