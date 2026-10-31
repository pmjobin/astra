# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""A57–A64 public compilation, independent linking, exact files, DWARF and memory."""
from pathlib import Path
import hashlib
import json
import os
import shlex
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
APPS = ROOT/'examples/ecosystem-abi-8'
LIB = ROOT/'lib/astra'
SOURCES = ['base/errors.astra', 'hosted/text.astra', 'hosted/files.astra', 'text/utf8-message.astra', 'text/utf8-byte-builder.astra', 'text/scalar-format.astra']
WORK_EXPORTS = ['Work8.Sample', 'Work8.combine', 'Work8.scaled_mean', 'Work8.double_value', 'Work8.Ticket', 'Work8.create_ticket', 'Work8.ticket_code']
CASES = {
	57: ('property-observer', 'value=42\nsnapshot=café\nreleased=1\n'),
	58: ('foreign-identity', 'same=1\nretained-value=17\nweak=expired\ndisposed=1\n'),
	59: ('signal-recorder', 'disconnected\nrecorder closed\nevent=3\nnested=-2\nevent=5\nforeign finalized=1\n'),
	60: ('gir-client', 'AstraFixture 1.0 / GObject 2.0\nlabel=GIR café\nvalue=23\n'),
	61: ('module-statistics', 'samples=2\ntotal=42\nmean-hundredths=2100\n'),
	62: ('module-ownership', 'completed=73\ndestructors=1\nallocator=native\n'),
	63: ('plugin-pipeline', 'pipeline closed\nmapped=46\nmapped=50\nticket released=1\nforeign finalized=1\n'),
	64: ('source-analyzer', 'letters=6\ndigits=3\ntabs=1\nlines=2\n'),
}


def main(compiler_path, output_path):
	compiler, output = Path(compiler_path).resolve(), Path(output_path).resolve()
	assert not output.is_relative_to(ROOT)
	output.mkdir(parents=True, exist_ok=True)
	out = Path(tempfile.mkdtemp(prefix='apps-', dir=output))
	rows = []
	sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
	receipt = dict(compiler=str(compiler), compiler_sha256=sha(compiler), checks=rows, products={}, apps={})

	def run(command, expected=0, contains=(), stdout=None, cwd=ROOT):
		command = list(map(str, command))
		start = time.monotonic()
		p = subprocess.run(command, cwd=cwd, capture_output=True, timeout=45 if command[0] == 'llvm-dwarfdump' else 180,
			env=dict(os.environ, CCACHE_DISABLE='1', G_DEBUG='fatal-warnings', DEBUGINFOD_URLS=''))
		text = (p.stdout+p.stderr).decode(errors='replace')
		valid = p.returncode == expected and all(s in text for s in contains) and (stdout is None or p.stdout == stdout)
		rows.append(dict(command=command, cwd=str(cwd), expected_exit=expected, exit=p.returncode, seconds=time.monotonic()-start,
			expected_stdout=None if stdout is None else stdout.decode(), stdout=p.stdout.decode(errors='replace'), stderr=p.stderr.decode(errors='replace'), passed=valid))
		(out/'checks.json').write_text(json.dumps(receipt, indent=2)+'\n')
		assert valid, rows[-1]
		return p.stdout

	flags = shlex.split(run(['pkg-config', '--cflags', 'gobject-2.0']).decode())
	foreign_libs = shlex.split(run(['pkg-config', '--libs', 'gobject-2.0']).decode())
	run(['pkg-config', '--modversion', 'gobject-2.0'])
	# Namespace/profile versions are fixed; provider patch version is recorded,
	# while no exact host patch requirement is imposed on the portable recipe.
	c_sources = [LIB/'platform'/name for name in ['text-posix.c', 'text-ops-posix.c', 'files-posix.c', 'args-posix.c']]+[APPS/'app-support.c']
	foreign_sources = [LIB/'interop'/name for name in ['gobject.c', 'retained.c', 'gobject-signals.c']]+[HERE/'counter.c']

	def compile_c(source, product, sanitizer=None):
		sanitize = [] if sanitizer is None else [f'-fsanitize={sanitizer}', '-fno-sanitize-recover=all', '-fno-omit-frame-pointer']
		run(['/usr/bin/clang', '-std=c11', '-g', '-gdwarf-4', '-O1' if sanitizer else '-O2', '-Wall', '-Wextra', '-Werror', *sanitize,
			'-I'+str(LIB/'interop'), '-I'+str(HERE), *flags, '-c', source, '-o', product])
		return product

	objects = [compile_c(s, out/(s.stem+'.o')) for s in c_sources]
	foreign_objects = [compile_c(s, out/(s.stem+'.o')) for s in foreign_sources]
	gir = out/'gir'
	importer = [sys.executable, ROOT/'tools/gir/import.py', '--profile', HERE/'gir-profile.json', '--gir', '/usr/share/gir-1.0/GObject-2.0.gir', '--gir', HERE/'AstraFixture-1.0.gir']
	run([*importer, '--output', gir])
	run([*importer, '--verify', gir])
	bindings = compile_c(gir/'bindings.c', gir/'bindings.o')

	def provider(namespace, source, exports, level, directory):
		directory.mkdir(exist_ok=True)
		interface, obj = directory/'unit.asti', directory/'unit.o'
		run([compiler, '-g', f'-O{level}', '-c', '--module', namespace, '--emit-interface', interface,
			*[x for name in exports for x in ('--native-export', name)], source, '-o', obj])
		return interface, obj

	providers = {level: provider('Work8', APPS/'work-unit.astra', WORK_EXPORTS, level, out/f'work-O{level}') for level in (0, 2)}
	analyzers = {level: provider('Analyzer8', APPS/'analyzer-unit.astra', ['Analyzer8.classify'], level, out/f'analyzer-O{level}') for level in (0, 2)}
	app_commands = {}
	for app, (name, expected_text) in CASES.items():
		receipt['apps'][str(app)] = dict(name=name, expected_stdout=expected_text, runs=[])
		for level in (0, 2, 1) if app in (59, 64) else (0, 2):
			directory = out/f'A{app}-O{level}'; directory.mkdir()
			source = APPS/f'a{app}-{name}.astra'
			sources = [APPS/'common.astra', *[LIB/s for s in SOURCES], source]
			options, link = [], list(objects)
			if app in (57, 58, 59, 63):
				options += ['--vapi', HERE/'counter.vapi']
				link += foreign_objects
			if app in (57, 58): sources += [APPS/'foreign-text.astra']
			if app in (59, 63):
				options += ['--vapi', HERE/'signals.vapi']
				sources += [APPS/'record-log.astra']
			if app == 60:
				run([*importer, '--verify', gir])
				options += ['--vapi', gir/'bindings.vapi']
				sources += [gir/'bindings.astra']
				link += [*foreign_objects, bindings]
			if app in (61, 62, 63):
				interface, library = providers[2 if level == 2 else 0]
				options += ['--import-module', interface]
				link += [library]
			if app == 64:
				interface, library = analyzers[2 if level == 2 else 0]
				options += ['--import-module', interface]
				link += [library]
			consumer, product = directory/'consumer.o', directory/'program'
			run([compiler, '-g', f'-O{level}', '--entry-object', *options, *sources, '-o', consumer])
			libraries = foreign_libs if app in (57, 58, 59, 60, 63) else []
			run(['/usr/bin/clang', '-no-pie', consumer, *link, *libraries, '-o', product])
			input_args = []
			if app == 64:
				input_file = directory/'input.astra'; input_file.write_bytes(b'abc 12\n\tXYZ9\n')
				input_args = [input_file]
			expected = expected_text.encode()
			run([product, *input_args], stdout=expected, cwd=directory)
			file_name = {60: 'gir-report.txt', 64: 'analysis.txt'}.get(app)
			if file_name:
				assert (directory/file_name).read_bytes() == expected
				receipt['products'][str((directory/file_name).relative_to(out))] = sha(directory/file_name)
			run(['llvm-dwarfdump', '--verify', product], contains=('No errors.',))
			if app == 57:
				decoded = run(['readelf', '--debug-dump=decodedline', product])
				assert b'<Utf8MessageFactory>' not in decoded and b'utf8-message.astra' in decoded
			run(['valgrind', '--default-suppressions=no', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=definite,indirect,possible', '--error-exitcode=99', product, *input_args], stdout=expected, contains=('ERROR SUMMARY: 0 errors',), cwd=directory)
			memory = rows[-1]['stderr']
			assert 'All heap blocks were freed' in memory or all(x in memory for x in ('definitely lost: 0 bytes', 'indirectly lost: 0 bytes', 'possibly lost: 0 bytes'))
			dependencies = run(['readelf', '-d', product])
			assert (b'libgobject' in dependencies) == (app in (57, 58, 59, 60, 63))
			receipt['apps'][str(app)]['runs'].append(dict(level=level, program_sha256=sha(product), consumer_sha256=sha(consumer), memory=memory))
			app_commands[app, level] = (options, sources, link, libraries, input_args, directory)

			# Debug after formatting both modules: new source paths, actual current lines.
	formatted = out/'formatted'; formatted.mkdir()
	for name in ('analyzer-unit.astra', 'a64-source-analyzer.astra'):
		run([compiler, '--format', '-o', formatted/name, APPS/name])
		run([compiler, '--format', '--check', formatted/name])
	interface, library = provider('Analyzer8', formatted/'analyzer-unit.astra', ['Analyzer8.classify'], 0, formatted/'provider')
	for level in (0, 2):
		product = formatted/f'program-O{level}'
		run([compiler, '-g', f'-O{level}', '--entry-object', '--import-module', interface, APPS/'common.astra', *[LIB/s for s in SOURCES], formatted/'a64-source-analyzer.astra', '-o', formatted/'consumer.o'])
		run(['/usr/bin/clang', '-no-pie', formatted/'consumer.o', library, *objects, '-o', product])
		input_file = out/'A64-O0/input.astra'
		run([product, input_file], stdout=CASES[64][1].encode(), cwd=formatted)
		run(['llvm-dwarfdump', '--verify', product], contains=('No errors.',))
		run(['readelf', '--debug-dump=decodedline', product], contains=('analyzer-unit.astra', 'a64-source-analyzer.astra'))
		text = (formatted/'analyzer-unit.astra').read_text().splitlines()
		line = next(i+1 for i, s in enumerate(text) if '\treturn *address;' in s)
		if level == 0:
			run(['gdb', '--nx', '--batch', '-ex', 'set debuginfod enabled off', '-ex', f'break {formatted/"analyzer-unit.astra"}:{line}',
				'-ex', f'run {input_file}', '-ex', 'print byte', '-ex', 'print category', '-ex', 'list', product], contains=('$1 = 97', '$2 = 1', 'return *address;'))
		else:
			consumer_text = (formatted/'a64-source-analyzer.astra').read_text().splitlines()
			consumer_line = next(i+1 for i, s in enumerate(consumer_text) if '\t\tint letters = 0;' in s)
			run(['gdb', '--nx', '--batch', '-ex', 'set debuginfod enabled off', '-ex', f'break {formatted/"a64-source-analyzer.astra"}:{consumer_line}',
				'-ex', f'run {input_file}', '-ex', 'list', product], contains=('Breakpoint 1,', 'a64-source-analyzer.astra:', 'int letters = 0;'))

			# Native Astra objects execute with separately instrumented C boundaries.
			# Astra LLVM instructions and installed GLib are not sanitizer-instrumented.
	for sanitizer in ('address', 'undefined'):
		directory = out/sanitizer; directory.mkdir()
		instrumented = [compile_c(s, directory/(s.stem+'.o'), sanitizer) for s in [*c_sources, *foreign_sources]]
		for app in (62, 63):
			_, _, link, libraries, args, app_dir = app_commands[app, 0]
			library = providers[0][1]
			selected = instrumented[:len(c_sources)] if app == 62 else instrumented
			product = directory/f'A{app}'
			run(['/usr/bin/clang', f'-fsanitize={sanitizer}', '-fno-sanitize-recover=all', '-no-pie', app_dir/'consumer.o', library, *selected, *libraries, '-o', product])
			run([product, *args], stdout=CASES[app][1].encode(), cwd=directory)

	negative = {
		57: ('--vapi', HERE/'counter.vapi', 'int main(){owned Counter x=counter_new(1);return foreign_text_length(x);}'),
		58: ('--vapi', HERE/'counter.vapi', 'owned Counter escape(borrowed Counter x){return move x;} int main(){return 0;}'),
		59: ('--vapi', HERE/'counter.vapi', 'class E{init(){}deinit(){}} f64 bad(borrowed E e,f64 n){return n;} int main(){var e=new E();var h=closure_bind(move e,bad);return retained_register(h,0);}'),
		60: ('--vapi', gir/'bindings.vapi', 'int main(){owned AstraFixtureCounter object=AstraFixtureCounter_new(1);owned GirUtf8 text=AstraFixtureCounter_label_copy(object);return AstraFixtureCounter_read(text);}'),
		61: ('--import-module', providers[0][0], 'int main(){return Work8.scaled_mean(42);}'),
		62: ('--import-module', providers[0][0], 'owned Work8.Ticket escape(borrowed Work8.Ticket t){return move t;} int main(){return 0;}'),
		63: ('--import-module', providers[0][0], 'class E{init(){}deinit(){}} int f(borrowed E e,int n){return n;} int main(){var e=new E();var h=closure_bind(move e,f);release h;return retained_dispatch(h,1);}'),
		64: (None, None, 'class Node{init(){}deinit(){}} owned Node escape(borrowed Node node){return move node;} int main(){return 0;}'),
	}
	diagnostics = {57: "expects type 'ForeignUtf8'", 58: 'must be an owned nominal handle',
		59: 'retained callback requires', 60: "expects type 'AstraFixtureCounter'", 61: 'struct boundary requires',
		62: 'object ownership transfer requires', 63: 'use of released owned value', 64: 'object ownership transfer requires'}
	for app, (option, value, text) in negative.items():
		source = out/f'A{app}-unsafe.astra'; source.write_text(text+'\n')
		run([compiler, '--check', *([] if option is None else [option, value]), source], expected=1, contains=('error:', str(source), diagnostics[app]))
		# A62 stale ownership receipt refuses before emission and restores exactly.
	interface = providers[0][0]; baseline = interface.read_bytes()
	assert b':heap' in baseline
	interface.write_bytes(baseline.replace(b':heap', b':lexical', 1))
	run([compiler, '--check', '--import-module', interface, APPS/'a62-module-ownership.astra', APPS/'common.astra', *[LIB/s for s in SOURCES]], expected=1, contains=('native module:',))
	interface.write_bytes(baseline)
	run([compiler, '--check', '--import-module', interface, APPS/'a62-module-ownership.astra', APPS/'common.astra', *[LIB/s for s in SOURCES]])
	receipt['sources'] = {str(p): sha(p) for p in [*APPS.glob('*.astra'), *c_sources, *foreign_sources, HERE/'counter.h', HERE/'counter.vapi', HERE/'signals.vapi', HERE/'AstraFixture-1.0.gir', HERE/'gir-profile.json', Path('/usr/share/gir-1.0/GObject-2.0.gir'), ROOT/'tools/gir/import.py', Path(__file__).resolve(), *[LIB/s for s in SOURCES]]}
	receipt['products'].update({str(p.relative_to(out)): sha(p) for p in [*out.rglob('*.o'), *out.rglob('*.asti'), *out.rglob('program*')]})
	(out/'checks.json').write_text(json.dumps(receipt, indent=2)+'\n')
	print(f'PASS: A57–A64 O0/O2, O1 spots, exact output/files, memory, independent units, GIR, signals, formatter/GDB, refusals; evidence {out}')


if __name__ == '__main__':
	main(*sys.argv[1:])
