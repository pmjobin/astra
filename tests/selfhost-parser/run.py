#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Build once per complete identity; execute the syntax component's fixed corpus."""
import argparse
import difflib
import hashlib
import json
import os
from pathlib import Path
import random
import resource
import shutil
import subprocess
import sys
import time

sys.dont_write_bytecode = True
from corpus import cases

ROOT = Path(__file__).resolve().parents[2]
LIBRARIES = ['base/errors', 'base/diagnostics', 'text/utf8-message', 'text/utf8-byte-builder', 'text/scalar-format', 'hosted/text-ops', 'collections/bag', 'collections/vector', 'hosted/files', 'hosted/text']
PROVIDERS = ['args-posix', 'files-posix', 'text-posix', 'text-ops-posix', 'diagnostics-trap']


def sha(path):
	return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--compiler', type=Path, required=True)
	p.add_argument('--build', type=Path, required=True)
	p.add_argument('--runtime', type=Path, required=True)
	p.add_argument('--corpus-base', default='HEAD')
	p.add_argument('--build-only', action='store_true')
	args = p.parse_args()
	resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
	compiler, build, runtime = [x.resolve() for x in (args.compiler, args.build, args.runtime)]
	for path in (build, runtime):
		assert not path.is_relative_to(ROOT), 'out-of-source outputs required'
		path.mkdir(parents=True, exist_ok=True)
	attempt = runtime / ('attempt-' + str(time.time_ns()))
	attempt.mkdir()
	commands = []
	auxiliary = []
	started = time.monotonic()
	env = dict(os.environ, CCACHE_DISABLE='1', PYTHONDONTWRITEBYTECODE='1')
	def capture(argv, data=None, allow_failure=False):
		start = time.monotonic()
		result = subprocess.run(list(map(str, argv)), cwd=build, input=data, capture_output=True, env=env)
		auxiliary.append(dict(argv=list(map(str, argv)), exit=result.returncode, seconds=time.monotonic() - start, stdout_sha256=hashlib.sha256(result.stdout).hexdigest(), input_sha256=None if data is None else hashlib.sha256(data).hexdigest()))
		(attempt / 'preparation.json').write_text(json.dumps(auxiliary, indent=2) + '\n')
		assert allow_failure or result.returncode == 0, result.stderr.decode(errors='replace')
		return result.stdout
	def run(argv, name, expected=0, timeout=600, keep=False):
		argv = list(map(str, argv))
		start = time.monotonic()
		result = subprocess.run(argv, cwd=build, capture_output=True, env=env, timeout=timeout)
		commands.append(dict(name=name, argv=argv, exit=result.returncode, expected=expected, seconds=time.monotonic() - start, stdout_sha256=hashlib.sha256(result.stdout).hexdigest()))
		(attempt / 'commands.json').write_text(json.dumps(commands, indent=2) + '\n')
		(attempt / (name + '.stderr')).write_bytes(result.stderr)
		if keep or result.returncode != expected:
			(attempt / (name + '.stdout')).write_bytes(result.stdout)
		assert result.returncode == expected, (name, result.returncode, result.stderr.decode(errors='replace')[-5000:])
		return result.stdout

		# The corpus is frozen before any candidate execution. Its original entries
		# remain in this attempt even when an independent expectation or parity fails.
	base = run(['git', '-C', ROOT, 'rev-parse', args.corpus_base], 'corpus-base').decode().strip()
	entries = []
	for index, item in enumerate(cases()):
		path = attempt / f'case-{index:04d}.astra'
		path.write_bytes(item['data'])
		entries.append({k: v for k, v in item.items() if k != 'data'} | dict(path=str(path), sha256=sha(path), bytes=path.stat().st_size, family='fixed'))
	tracked = run(['git', '-C', ROOT, 'ls-tree', '-r', '--name-only', base], 'corpus-paths').decode().splitlines()
	real_names = [name for name in tracked if name.endswith('.astra')]
	blobs = capture(['git', '-C', ROOT, 'cat-file', '--batch'], ''.join(base + ':' + name + '\n' for name in real_names).encode())
	position = 0
	for name in real_names:
		end = blobs.index(b'\n', position)
		header = blobs[position:end].split()
		assert header[1] == b'blob'
		length = int(header[2])
		data = blobs[end + 1:end + 1 + length]
		assert blobs[end + 1 + length:end + 2 + length] == b'\n'
		position = end + 2 + length
		path = attempt / f'case-{len(entries):04d}.astra'
		path.write_bytes(data)
		entries.append(dict(name=name, path=str(path), sha256=sha(path), bytes=path.stat().st_size, family='real', positive=None, error=None))
	rng = random.Random(30309)
	byte_cases = [b'int f(){return 1;}\n//' + bytes([byte]) for byte in range(256)]
	byte_cases += [b'int f(){return "' + rng.randbytes(rng.randrange(1, 33)) + b'";}' for _ in range(128)]
	for index, data in enumerate(byte_cases):
		path = attempt / f'bytes-{index:04d}.astra'
		path.write_bytes(data)
		entries.append(dict(name=f'bytes-{index}', path=str(path), sha256=sha(path), bytes=len(data), family='bytes', positive=None, error=None))
	text = 'int f(){var text="é😀";return var;}'
	path = attempt / 'unicode-column.astra'
	path.write_text(text)
	at = path.read_bytes().rindex(b'var')
	entries.append(dict(name='unicode-column', path=str(path), sha256=sha(path), bytes=path.stat().st_size, family='fixed', positive=False, error=(at, at + 3, "'var' is a reserved keyword for inferred local declarations")))
	(attempt / 'corpus.json').write_text(json.dumps(dict(base=base, seed=303, byte_seed=30309, entries=entries), indent=2) + '\n')
	group = []
	for name, text in [('z.astra', 'namespace Z;using A;int z(){return 2;}'), ('a.astra', 'namespace A;class Item{owned Part value;init(owned Part value){this.value=move value;}int get(){return 1;}}int id<T>(T x){return 0;}')]:
		path = attempt / name
		path.write_text(text)
		group.append(str(path))
	aggregation = []
	for name, text in [
		('aggregate-z.astra', 'struct Generic<T>{T value;}class G<T> where T:ExactHeapClass{owned T value;init(owned T value){this.value=move value;}}async runtime Loop throws Fault returns Status;[CImport(name="ForeignThing")]class Foreign{init();int read();}[COMImport(name="View")]interface View;int last(){return 0;}'),
		('aggregate-a.astra', 'struct Plain{int value;}class C{init(){}}enum E{One}const int V=1;int first(){return 0;}'),
	]:
		path = attempt / name
		path.write_text(text)
		aggregation.append(str(path))
	native = attempt / 'native-interface.astra'
	native.write_text('class C{property borrowed Item value{get{}}}interface Contract{int value();}')
	(attempt / 'groups.json').write_text(json.dumps(dict(ordered_multisource=group, aggregate_views=aggregation, native_interface=str(native), files={path: sha(path) for path in [*group, *aggregation, str(native)]}), indent=2) + '\n')

	# Pin executables, their dynamic dependencies, compiler backend/link tools,
	# startup objects, public VAPI files and actual transitive provider headers.
	tool_paths = {compiler}
	for name in (str(compiler), '/usr/bin/gcc', 'cc', 'ccache', 'valac', 'ld', 'as', 'pkg-config', 'llvm-config'):
		located = shutil.which(name)
		if name == 'ccache' and located is None:
			continue
		assert located, 'required tool unavailable: ' + name
		path = Path(located).resolve()
		tool_paths.add(path)
		output = capture(['ldd', path], allow_failure=True).decode()
		for word in output.split():
			if word.startswith('/') and Path(word).is_file():
				tool_paths.add(Path(word).resolve())
	for name in ('cc1', 'collect2'):
		path = Path(capture(['/usr/bin/gcc', '-print-prog-name=' + name]).decode().strip()).resolve()
		if path.is_file(): tool_paths.add(path)
	for name in ('crtbegin.o', 'crtend.o', 'crti.o', 'crtn.o', 'libgcc.a', 'libgcc_s.so', 'libc.so'):
		path = Path(capture(['/usr/bin/gcc', '-print-file-name=' + name]).decode().strip()).resolve()
		if path.is_file(): tool_paths.add(path)
	for directory in (Path('/usr/share/vala/vapi'), *Path('/usr/share').glob('vala-*/vapi')):
		for name in ('glib-2.0.vapi', 'gobject-2.0.vapi'):
			if (directory / name).is_file(): tool_paths.add(directory / name)
	dependencies = {str(x): sha(x) for x in sorted(tool_paths)}
	dependencies['pkg-config-output'] = capture(['pkg-config', '--cflags', '--libs', 'glib-2.0', 'gobject-2.0']).decode()
	(attempt / 'toolchain.json').write_text(json.dumps(dependencies, indent=2) + '\n')
	products = {}
	def product(argv, target, sources, name):
		identity = dict(argv=list(map(str, argv)), sources={str(x): sha(x) for x in sources}, tools=dependencies)
		cache = target.with_suffix('.identity.json')
		previous = json.loads(cache.read_text()) if cache.exists() else None
		if target.exists() and previous and previous['identity'] == identity and previous['sha256'] == sha(target):
			commands.append(dict(name=name, reused=True, identity_sha256=hashlib.sha256(json.dumps(identity, sort_keys=True).encode()).hexdigest(), product_sha256=sha(target)))
		else:
			run(['/usr/bin/time', '-v', *argv], name, timeout=1200)
			assert {str(x): sha(x) for x in sources} == identity['sources'], 'source changed during compilation'
			cache.write_text(json.dumps(dict(identity=identity, sha256=sha(target)), indent=2) + '\n')
		products[target.name] = dict(path=str(target), sha256=sha(target), identity_sha256=sha(cache))

	objects = []
	for name in PROVIDERS:
		source = ROOT / f'lib/runtime/platform/{name}.c'
		depfile = run(['/usr/bin/gcc', '-std=c11', '-M', source], 'headers-' + name).decode().replace('\\\n', ' ')
		headers = [Path(x).resolve() for x in depfile.split(':', 1)[1].split()]
		target = build / (name + '.o')
		product(['/usr/bin/gcc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-c', source, '-o', target], target, headers, 'provider-' + name)
		objects.extend(['--link-object', target])
	oracle_sources = [*sorted((ROOT / 'bootstrap/source').glob('*.vala')), *sorted((ROOT / 'bootstrap/syntax').glob('*.vala')), ROOT / 'tests/selfhost-parser/oracle.vala', ROOT / 'tests/selfhost-parser/ast-oracle.vala']
	oracle = build / 'parser-oracle'
	product(['valac', '--enable-checking', '-X', '-DVALA_STRICT_C', '-o', oracle, *oracle_sources], oracle, oracle_sources, 'oracle-build')
	sources = [*sorted((ROOT / 'compiler/source').glob('*.astra')), *sorted((ROOT / 'compiler/syntax').glob('*.astra')), *[ROOT / f'tests/selfhost-parser/{name}.astra' for name in ('observe', 'controls', 'cursors')], *[ROOT / f'lib/astra/{name}.astra' for name in LIBRARIES]]
	programs = []
	for mode in ('O0', 'O2'):
		program = build / ('astra-syntax-' + mode)
		product([compiler, '-' + mode, *sources, *objects, '-o', program], program, [*sources, *objects[1::2]], 'parser-build-' + mode)
		programs.append(program)
	source_programs = []
	for mode in ('O0', 'O2'):
		program = build / ('source-set-' + mode)
		source_inputs = [*sorted((ROOT / 'compiler/source').glob('*.astra')), ROOT / 'tests/selfhost-foundation/source-set.astra', *[ROOT / f'lib/astra/{name}.astra' for name in LIBRARIES]]
		product([compiler, '-' + mode, *source_inputs, *objects, '-o', program], program, [*source_inputs, *objects[1::2]], 'source-set-build-' + mode)
		source_programs.append(program)
	if args.build_only:
		print(json.dumps(dict(status='BUILT_NOT_QUALIFIED', attempt=str(attempt), products=products), indent=2))
		return

	outcomes = []
	variants = {}
	def compare(argv, label, items=None):
		outputs = [run([program, *argv], label + '-' + program.name, timeout=120) for program in [oracle, *programs]]
		for program, output in zip(programs, outputs[1:]):
			if output != outputs[0]:
				(attempt / (label + '-oracle.stdout')).write_bytes(outputs[0])
				(attempt / (label + '-' + program.name + '.stdout')).write_bytes(output)
				(attempt / (label + '.diff')).write_text(''.join(difflib.unified_diff(outputs[0].decode().splitlines(True), output.decode().splitlines(True), 'Vala', program.name)))
				raise AssertionError('differential mismatch: ' + label)
		if items:
			results = outputs[0].split(b'END\n')[:-1]
			assert len(results) == len(items)
			for item, output in zip(items, results):
				positive = output.startswith(b'OK\n')
				if item['positive'] is not None: assert positive == item['positive'], ('independent acceptance', item['name'])
				if item.get('error'):
					a, z, message = item['error']
					prefix = Path(item['path']).read_bytes()[:a].replace(b'\r\n', b'\n').replace(b'\r', b'\n')
					line = 1 + prefix.count(b'\n')
					column = 1 + len(prefix.split(b'\n')[-1].decode())
					expected = f'ERROR {a} {z} {message.encode().hex()}\ninput:{line}:{column}: error: {message}\n'.encode()
					assert output.startswith(expected), ('independent diagnostic', item['name'])
				for line in output.splitlines():
					if line.startswith(b'N '): variants.setdefault(line.split()[2].decode(), item['name'])
				outcomes.append(dict(name=item['name'], family=item['family'], source_sha256=item['sha256'], positive=positive, observation_sha256=hashlib.sha256(output).hexdigest(), diagnostic=None if positive else output.decode()))
			(attempt / 'outcomes.json').write_text(json.dumps(outcomes, indent=2) + '\n')
		return outputs[0]
	for at in range(0, len(entries), 32):
		chunk = entries[at:at + 32]
		compare([x['path'] for x in chunk], f'corpus-{at:04d}', chunk)
		print('parity', at, len(chunk), flush=True)

		# Independent byte and tree expectations cannot be regenerated from Astra.
	precedence = next(x for x in entries if x['name'] == 'precedence')
	observed = compare([precedence['path']], 'precedence-repeat')
	expected_dump = b'(unit\n\t(function\n\t\t(type "int")\n\t\t(name "f")\n\t\t(parameters)\n\t\t(block\n\t\t\t(return (binary "+" (integer "1") (binary "*" (integer "2") (integer "3"))))\n\t\t)\n\t)\n)\n'
	assert observed.split(b'AST\n')[0] == b'OK\n' + expected_dump
	assert b'N 1 CompilationUnitSyntax 1 0 22 0\n' in observed
	assert b'T literal INTEGER 1 15 16 31 \n' in observed
	for item in (precedence, next(x for x in entries if x['name'] == 'const-keyword')):
		expected_exit = 0 if item['positive'] else 1
		for mode in ('--parse', '--dump-syntax'):
			name = 'cli-' + mode[2:] + '-' + item['name']
			reference = run([compiler, mode, item['path']], name + '-C0', expected=expected_exit, keep=True)
			stderr = (attempt / (name + '-C0.stderr')).read_bytes()
			for program in programs:
				actual = run([program, mode, item['path']], name + '-' + program.name, expected=expected_exit)
				assert actual == reference and (attempt / (name + '-' + program.name + '.stderr')).read_bytes() == stderr
	negative = next(x for x in entries if x['name'] == 'const-keyword')
	for fault in ('kind', 'span', 'order', 'source', 'missing', 'diagnostic', 'message'):
		path = negative['path'] if fault in ('diagnostic', 'message') else precedence['path']
		reference = run([oracle, path], 'fault-reference-' + fault)
		for program in programs:
			mutated = run([program, '--fault-' + fault, path], 'fault-' + fault + '-' + program.name, keep=True)
			assert mutated != reference, 'comparison did not detect ' + fault
			if fault in ('span', 'source'): assert mutated.split(b'AST\n')[0] == reference.split(b'AST\n')[0], 'control must change AST while preserving SyntaxDump'
	for program in programs:
		assert run([program, '--lifetime'], 'lifetime-' + program.name) == b'PARSER_LIFETIME_OK\n'
		assert run([program, '--cursors'], 'cursors-' + program.name) == b'PARSER_CURSOR_OK\n'
		run([program, '--fault-lifetime'], 'lifetime-negative-' + program.name, expected=-4)

	compare(['--program', *group], 'multi-source')
	compare(['--program', *reversed(group)], 'multi-source-reversed')
	compare(['--program', *aggregation], 'aggregate-program')
	for program in programs:
		assert run([program, '--aggregation', *aggregation], 'aggregate-views-' + program.name) == b'PARSER_AGGREGATION_OK\n'
	duplicate_errors = []
	for program in [oracle, *programs]:
		run([program, '--program', group[0], str(Path(group[0]).parent) + '/./z.astra'], 'duplicate-' + program.name, expected=2, keep=True)
		duplicate_errors.append((attempt / ('duplicate-' + program.name + '.stderr')).read_bytes())
	assert all(error == (f"source file '{group[0]}' was supplied more than once\n").encode() for error in duplicate_errors)
	expected_inventory = b'namespace A\nclass Item\nfield Item.value : owned Part\nlifecycle Item.init(owned Part value)\nmethod Item.get() -> int\nfunction id<T>(T x) -> int\nnamespace Z\nusing A\nfunction z() -> int\n'
	for program in programs: assert run([program, '--inventory', *group], 'inventory-' + program.name, keep=True) == expected_inventory
	compare(['--native-interface', native], 'native-interface')
	compare([native], 'ordinary-interface-mode-refusal')

	# Parse the current implementation as a real multi-file source program.
	current = [*sources[:len(sources) - len(LIBRARIES)], *[ROOT / f'lib/astra/{name}.astra' for name in LIBRARIES]]
	current_output = compare(['--program', *current], 'current-component-program')
	c0_dump = run([compiler, '--dump-syntax', *current], 'current-c0-cli', timeout=180)
	assert current_output.split(b'AST\n')[0] == b'OK\n' + c0_dump
	for program in source_programs:
		assert run([program], 'source-identity-' + program.name) == b'SOURCE_SET_OK\n'
		assert run([program, '--duplicate'], 'source-duplicate-' + program.name, expected=2) == b"source file 'a/item' was supplied more than once\n"
		run([program, '--empty'], 'source-empty-' + program.name, expected=-4)
		for count in (512, 2048, 8192, 32768):
			assert run(['/usr/bin/time', '-v', program, '--scale', count], f'source-scale-{count}-' + program.name) == b'SOURCE_SET_SCALE_OK\n'

	memory = bool(shutil.which('valgrind'))
	if memory:
		selected = [x['path'] for x in entries if x['name'] in ('precedence', 'generic-shift', 'failed-probe', 'factory', 'interface', 'parentheses-255', 'parentheses-256', 'blocks-255', 'blocks-256', 'types-255', 'types-256', 'pointer-type-long', 'raw-nul', 'invalid-utf8')]
		for program in programs:
			for label, argv in [('lifetime', ['--lifetime']), ('cursors', ['--cursors']), ('normal-error-deep', selected), ('multi-source', ['--program', *group])]:
				run(['valgrind', '--vgdb=no', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=definite,indirect,possible', '--error-exitcode=99', program, *argv], 'memory-' + label + '-' + program.name, timeout=300)
				log = (attempt / ('memory-' + label + '-' + program.name + '.stderr')).read_text()
				assert 'ERROR SUMMARY: 0 errors' in log and ('All heap blocks were freed' in log or 'definitely lost: 0 bytes' in log)
		for program in source_programs:
			run(['valgrind', '--vgdb=no', '--leak-check=full', '--errors-for-leak-kinds=definite,indirect,possible', '--error-exitcode=99', program, '--duplicate'], 'memory-source-duplicate-' + program.name, expected=2)
	model = json.loads((ROOT / 'compiler/syntax/model.json').read_text())['nodes']
	required = {name for name, node in model.items() if not node['abstract']}
	assert required <= variants.keys(), ('unobserved AST variants', sorted(required - variants.keys()))
	result = dict(status='PASS' if memory else 'PARTIAL', compiler_sha256=sha(compiler), base=base, products=products, cases=len(entries), positive=sum(x['positive'] for x in outcomes), negative=sum(not x['positive'] for x in outcomes), variants=variants, memory=memory, seconds=time.monotonic() - started, process_calls=sum(not command.get('reused', False) for command in commands) + len(auxiliary), scope='GNU x86-64 Linux source/syntax components; no semantic compiler, Stage 1, backend or release qualification')
	(attempt / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
	(runtime / 'latest.json').write_text(json.dumps(dict(attempt=str(attempt), result_sha256=sha(attempt / 'result.json')), indent=2) + '\n')
	print(json.dumps(result, indent=2))


if __name__ == '__main__':
	main()
