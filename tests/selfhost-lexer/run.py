#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Compiler-selectable batch lexer qualification; all products stay outside source."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import random
import shutil
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]
LIBRARIES = ['base/errors', 'base/diagnostics', 'text/utf8-message', 'text/utf8-byte-builder', 'text/scalar-format', 'hosted/text-ops', 'collections/bag', 'collections/vector', 'hosted/files', 'hosted/text']


def sha(path):
	return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--compiler', type=Path, required=True)
	p.add_argument('--build', type=Path, required=True)
	p.add_argument('--runtime', type=Path, required=True)
	args = p.parse_args()
	compiler, build, runtime = [x.resolve() for x in (args.compiler, args.build, args.runtime)]
	for path in (build, runtime):
		assert not path.is_relative_to(ROOT), 'out-of-source outputs required'
		path.mkdir(parents=True, exist_ok=True)
	attempt = runtime / ('attempt-' + str(time.time_ns()))
	attempt.mkdir()
	commands = []
	def run(argv, name, timeout=180):
		start = time.monotonic()
		r = subprocess.run(list(map(str, argv)), cwd=build, capture_output=True, timeout=timeout, env=dict(os.environ, CCACHE_DISABLE='1'))
		commands.append(dict(name=name, argv=list(map(str, argv)), exit=r.returncode, seconds=time.monotonic() - start, stdout_sha256=hashlib.sha256(r.stdout).hexdigest()))
		(attempt / 'commands.json').write_text(json.dumps(commands, indent=2) + '\n')
		(attempt / (name + '.stderr')).write_bytes(r.stderr)
		if r.returncode:
			(attempt / (name + '.stdout')).write_bytes(r.stdout)
			raise AssertionError((name, r.returncode, r.stderr.decode(errors='replace')[:2000]))
		return r.stdout
	def product(argv, target, inputs, name):
		tool = Path(shutil.which(str(argv[0]))).resolve()
		identity = dict(argv=list(map(str, argv)), inputs={str(x): sha(x) for x in [tool, *inputs]})
		cache = target.with_suffix('.identity.json')
		if target.exists() and cache.exists():
			previous = json.loads(cache.read_text())
			if previous['identity'] == identity and previous['product_sha256'] == sha(target):
				commands.append(dict(name=name, reuse=True, identity=identity, product_sha256=sha(target)))
				return
		run(argv, name)
		cache.write_text(json.dumps(dict(identity=identity, product_sha256=sha(target)), indent=2) + '\n')
		# Exact class extraction avoids compiling unrelated parser/factory machinery.
	original_decoder = ROOT / 'bootstrap/syntax/text-syntax.vala'
	text = original_decoder.read_text()
	decoder = build / 'decoder.vala'
	decoder.write_text('using Astra.Source;\nusing Astra.Text;\nnamespace Astra.Syntax {\n' + text[text.index('public class TextLiteralDecoder'):])
	oracle_sources = [ROOT / 'tests/selfhost-lexer/oracle.vala', decoder, *[ROOT / f'bootstrap/source/{n}.vala' for n in ('source-file', 'source-span', 'diagnostic', 'text-bytes')], ROOT / 'bootstrap/syntax/token.vala', ROOT / 'bootstrap/syntax/lexer.vala']
	oracle = build / 'lexer-oracle'
	product(['valac', '--enable-checking', '-X', '-DVALA_STRICT_C', '-o', oracle, *oracle_sources], oracle, [*oracle_sources, original_decoder], 'oracle-build')
	objects = []
	for provider in ('args-posix', 'files-posix', 'text-posix', 'text-ops-posix', 'diagnostics-trap'):
		source = ROOT / f'lib/runtime/platform/{provider}.c'
		target = build / (provider + '.o')
		product(['/usr/bin/gcc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-c', source, '-o', target], target, [source, *sorted((ROOT / 'lib/runtime').rglob('*.h'))], provider)
		objects.extend(['--link-object', target])
	sources = [ROOT / 'compiler/source/source.astra', *sorted((ROOT / 'compiler/syntax').glob('*.astra')), ROOT / 'tests/selfhost-lexer/dump.astra', ROOT / 'tests/selfhost-lexer/lifetime.astra', *[ROOT / f'lib/astra/{n}.astra' for n in LIBRARIES]]
	programs = []
	for mode in ('O0', 'O2'):
		program = build / ('lexer-' + mode)
		product([compiler, '-' + mode, *sources, *objects, '-o', program], program, [*sources, *objects[1::2]], 'build-' + mode)
		programs.append(program)
		assert run([program, '--lifetime'], 'lifetime-' + mode) == b'LIFETIME_OK\n'

	def batch(paths, label):
		outputs = [run([program, *paths], label + '-' + program.name) for program in [oracle, *programs]]
		for index, output in enumerate(outputs[1:]):
			if output != outputs[0]:
				(attempt / (label + '-reference')).write_bytes(outputs[0])
				(attempt / (label + '-actual-' + str(index))).write_bytes(output)
				raise AssertionError('differential mismatch: ' + label)
		return outputs[0].decode().split('FORK\n')[:-1]

		# Independent expectations: these are hand-authored, never oracle-derived.
	cases = []
	def case(data, tokens=None, error=None, comments=()):
		cases.append((data, tokens, error, comments))
	case(b'', [('EOF', 0, 0, b'', b'')])
	case(b'if ifx _9', [('IF', 0, 2, b'if', b''), ('IDENTIFIER', 3, 6, b'ifx', b''), ('IDENTIFIER', 7, 9, b'_9', b''), ('EOF', 9, 9, b'', b'')])
	case(b'1. 1..2 1e-2F 1f', [('INTEGER', 0, 1, b'1', b''), ('DOT', 1, 2, b'.', b''), ('INTEGER', 3, 4, b'1', b''), ('DOT', 4, 5, b'.', b''), ('DOT', 5, 6, b'.', b''), ('INTEGER', 6, 7, b'2', b''), ('FLOAT', 8, 13, b'1e-2F', b''), ('INTEGER', 14, 15, b'1', b''), ('IDENTIFIER', 15, 16, b'f', b''), ('EOF', 16, 16, b'', b'')])
	case(b'"a\\0\\u00e9\\U0001f600"', [('TEXT', 0, 21, b'"a\\0\\u00e9\\U0001f600"', 'a\0é😀'.encode()), ('EOF', 21, 21, b'', b'')])
	case(b'//x\r\n/* y */', [('EOF', 12, 12, b'', b'')], comments=[(0, 3), (5, 12)])
	case(b'1e+', [], (0, 3, 'floating literal exponent requires digits'))
	case(b'/*', [], (0, 2, 'unterminated block comment'))
	case(b'"\\q"', [], (1, 3, 'unknown string escape'))
	case(b'"\\u12x4"', [], (5, 6, 'Unicode escape requires exactly hexadecimal digits'))
	case(b'"\\u12', [], (0, 5, 'incomplete Unicode escape'))
	case(b'"x\n', [], (0, 3, 'physical newline or NUL in string literal'))
	case(b'"x', [], (0, 2, 'unterminated string literal'))
	case(b'@\xff', [], (1, 2, 'invalid UTF-8 encoding'))
	case(b'@\0', [], (1, 2, 'unexpected NUL byte'))
	case('é'.encode(), [], (0, 2, 'non-ASCII character is not supported outside comments'))
	# Maximal munch and renaming/trivia transformations with independent offsets.
	operators = [('<<', 'SHIFT_LEFT'), ('<=', 'LESS_EQUAL'), ('<', 'LESS'), ('>>', 'SHIFT_RIGHT'), ('>=', 'GREATER_EQUAL'), ('>', 'GREATER'), ('&&', 'AMPERSAND_AMPERSAND'), ('&', 'AMPERSAND'), ('||', 'PIPE_PIPE'), ('|', 'PIPE'), ('->', 'ARROW'), ('-', 'MINUS'), ('!=', 'BANG_EQUAL'), ('!', 'BANG'), ('==', 'EQUAL_EQUAL'), ('=', 'EQUAL')]
	for separator in (' ', '\t/*ok*/\r\n'):
		data = b''
		tokens, comments = [], []
		for spelling, kind in [('alpha', 'IDENTIFIER'), *operators, ('renamed_2', 'IDENTIFIER')]:
			start = len(data)
			data += spelling.encode()
			tokens.append((kind, start, len(data), spelling.encode(), b''))
			if '/*' in separator:
				comments.append((len(data) + 1, len(data) + 7))
			data += separator.encode()
		tokens.append(('EOF', len(data), len(data), b'', b''))
		case(data, tokens, comments=comments)
	keywords = 'async await throws throw try catch enum match case struct class this extern export return true false null if else while for foreach with nonnull break all as any dot_wrap mac_wrap dot mac sat_add sat_sub widen_low widen_high pack_wrap pack_sat interleave_low interleave_high slice len splat insert shuffle select borrowed owned const var move release swap continue'.split()
	data = b''
	tokens = []
	for keyword in keywords:
		kind = {'dot': 'DOT_F32', 'mac': 'MAC_F32'}.get(keyword, keyword.upper())
		start = len(data)
		data += keyword.encode()
		tokens.append((kind, start, len(data), keyword.encode(), b''))
		data += b' '
		start = len(data)
		data += (keyword + 'x').encode()
		tokens.append(('IDENTIFIER', start, len(data), (keyword + 'x').encode(), b''))
		data += b' '
	tokens.append(('EOF', len(data), len(data), b'', b''))
	case(data, tokens)
	paths = []
	for i, (data, _, _, _) in enumerate(cases):
		path = attempt / f'hand-{i}.bin'
		path.write_bytes(data)
		paths.append(path)
	outputs = batch(paths, 'hand')
	for i, (_, tokens, error, comments) in enumerate(cases):
		want = ''.join(f'{k} {a} {b} {text.hex()} {payload.hex()} \n' for k, a, b, text, payload in tokens)
		if error:
			a, b, message = error
			want += f'ERROR {a} {b} {message.encode().hex()} \n'
		want += ''.join(f'COMMENT {a} {b} \n' for a, b in comments)
		actual = outputs[i].split('END\n')[0]
		assert actual == want, (i, actual, want)

	rng = random.Random(2402)
	generated = [bytes([b]) for b in range(256)]
	generated += [b'"\\' + escape + b'"' for escape in [b'0', b'n', b'r', b't', b'"', b'\\', b'u0000', b'uD800', b'uDFFF', b'U00110000', b'UFFFFFFFF', b'U0010ffff', b'u007f', b'u0080', b'u07ff', b'u0800', b'u', b'U000', b'\n', b'\r']]
	generated += [b'/*x/*y*/z', b'/*x*', b'/**/', b'//\xc3\xa9\r\nx', b'0x12', b'1e', b'1e-', b'2.3Dfoo', b'1.2.3', b'1E+03', b'\xe2\x00', b'"\xf4\x8f\xbf\xbf"']
	atoms = [b'x', b'ifx', b'123', b'1e+', b'.', b'<<', b' ', b'\r\n', b'/*x*/', b'// x\n', b'"\\0"', b'"\\u1234"', b'"', b'\xff', 'é'.encode()]
	generated += [b''.join(rng.choice(atoms) for _ in range(rng.randrange(1, 25))) for _ in range(160)]
	for i, data in enumerate(generated):
		path = attempt / f'generated-{i}.bin'
		path.write_bytes(data)
		paths.append(path)
	tracked = subprocess.check_output(['git', 'ls-files', '-z', '*.astra'], cwd=ROOT).decode().split('\0')[:-1]
	real = sorted({ROOT / x for x in tracked} | set(sources[:7]))
	real = [x for x in real if x.suffix == '.astra']
	corpus = paths[len(cases):] + real
	for start in range(0, len(corpus), 64):
		batch(corpus[start:start + 64], f'corpus-{start:04d}')
	memory = bool(shutil.which('valgrind'))
	if memory:
		for program in programs:
			for label, inputs in [('lifetime', ['--lifetime']), ('malformed', paths[:len(cases)] + paths[len(cases):len(cases) + 32])]:
				run(['valgrind', '--vgdb=no', '--leak-check=full', '--errors-for-leak-kinds=definite,indirect,possible', '--error-exitcode=99', program, *inputs], 'memory-' + program.name + '-' + label)
	result = dict(status='PASS', recipe_sha256=sha(Path(__file__)), compiler_sha256=sha(compiler), products={x.name: sha(x) for x in [oracle, *programs]}, hand_cases=len(cases), generated_cases=len(generated), real_sources=len(real), memory=memory, corpus={str(x): sha(x) for x in [*paths, *real]}, commands=commands)
	(attempt / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
	(runtime / 'latest.json').write_text(json.dumps(dict(attempt=str(attempt), result_sha256=sha(attempt / 'result.json')), indent=2) + '\n')
	print(json.dumps({k: v for k, v in result.items() if k not in ('corpus', 'commands')}, indent=2))


if __name__ == '__main__':
	main()
