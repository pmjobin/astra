# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Driver failure policy, dependency boundaries, installation and relocated consumption."""
from pathlib import Path
import json
import re
import shutil
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True
from qualify import ROOT, BASE, EQUALITY, MATH, FIX, process, run, write_json


def examples(compiler, library, support, source, out, cwd):
	base = [library / ('base/' + name + '.astra') for name in ['order', 'classify', 'contracts', 'clamp']]
	equality, math = library / 'hosted/equality.astra', library / 'hosted/math.vapi'
	configurations = {
		'pure': ([source / 'pure.astra', base[0], base[1]], []),
		'contracts': ([source / 'contracts.astra', *base], ['--link-object', support / 'failure-trap.o']),
		'diagnostics': ([source / 'diagnostics.astra', equality], ['--link-object', support / 'failure-hosted.o']),
		'math': ([source / 'math.astra'], ['--vapi', math, '--link-library', 'm']),
		'buffer': ([*sorted((source / 'buffer').glob('*.astra')), *base, equality], ['--vapi', math, '--link-object', support / 'failure-hosted.o', '--link-library=m']),
	}
	commands = []
	for name, (sources, options) in configurations.items():
		args = [compiler, *sources, *options, '-o', out / name]
		run(args, cwd=cwd); run([out / name], '', cwd=cwd)
		commands.append(list(map(str, args)))
	args = [compiler, source / 'mismatch.astra', equality, '--link-object', support / 'failure-hosted.o', '-o', out / 'mismatch']
	run(args, cwd=cwd); p = process([out / 'mismatch'], cwd)
	assert p.returncode < 0 and p.stdout == '' and p.stderr == 'astra base: equality f64 code=204 expected=1.5 actual=1.25 expected_bits=0x3ff8000000000000 actual_bits=0x3ff4000000000000\n'
	commands.append(list(map(str, args)))
	return commands


def driver(compiler, out, support):
	source = out / 'main.astra'; source.write_text('int main(){return 0;}\n')
	output = out / 'existing'; output.write_text('preserve me\n')
	records = []
	def failure(name, args, status, needle):
		p = process([compiler, *args])
		assert p.returncode == status and needle in p.stderr and p.stdout == '', (name, p)
		assert output.read_text() == 'preserve me\n' and not list(out.glob('.astra-exec-*')), name
		records.append(dict(name=name, status=p.returncode, stderr=p.stderr))
	for name in ['', '-m', '/tmp/m', '../m', './m', 'a/b', 'a\\b', 'a b', 'a\tm', 'a\rm', 'a\nm', 'a\x01m', '-Wl,x', ':libm.so', 'm;false', '$(false)', '`false`', 'é', 'stdc++']:
		for form in [0, 1]:
			option = ['--link-library', name] if form == 0 else ['--link-library=' + name]
			failure('invalid-' + repr(name) + '-' + str(form), [source, *option, '-o', output], 2, 'bare name')
	failure('missing', [source, '--link-library'], 2, 'bare name')
	failure('missing-before-option', [source, '--link-library', '-o', output], 2, 'bare name')
	failure('no-source', ['--link-library=m'], 2, 'no action')
	failure('help', ['--help', '--link-library=m'], 2, 'cannot be combined')
	for stage in ['--parse', '--check', *['--dump-' + s for s in ['syntax', 'semantics', 'core', 'instances', 'cfg', 'ssa', 'nabi', 'cabi', 'llvm']]]:
		failure(stage, [stage, source, '--link-library=astra_baselib_does_not_exist'], 2, 'require executable compilation')
	failure('missing-library', ['--link-library=astra_baselib_does_not_exist', source, '-o', output], 1, 'host linker')
	fatal = out / 'fatal.astra'; fatal.write_text('int main(){assert(false);return 0;}\n')
	failure('missing-provider', [fatal, BASE[2], '-o', output], 1, 'astra_base_fail')
	failure('duplicate-provider', [fatal, BASE[2], '--link-object', support / 'failure-trap.o', '--link-object', support / 'failure-hosted.o', '-o', output], 1, 'multiple definition')
	math = out / 'math.astra'; math.write_text('int main(){var x=sqrt_f64(2.0d);if(x>1.0d){return 0;}return 1;}\n')
	failure('missing-explicit-libm', [math, '--vapi', MATH, '-o', output], 1, 'sqrt')
	for options in [['--link-library', 'm', math, '--vapi', MATH], [math, '--link-library=m', '--vapi', MATH, '--link-library', 'm']]:
		run([compiler, *options, '-o', out / 'math-linked']); run([out / 'math-linked'], '')
	write_json(out / 'driver.json', records)
	return records


def symbols(compiler, out, support):
	rows = []
	no_library = out / 'no-library.astra'; no_library.write_text('int main(){return 0;}\n')
	configurations = {
		'none': ([no_library], None, None),
		'pure': ([ROOT / 'examples/base/pure.astra', BASE[0], BASE[1]], None, None),
		'contracts-trap': ([ROOT / 'examples/base/contracts.astra', *BASE], support / 'failure-trap.o', None),
		'contracts-hosted': ([ROOT / 'examples/base/contracts.astra', *BASE], support / 'failure-hosted.o', None),
		'math': ([ROOT / 'examples/base/math.astra'], None, MATH),
		'buffer': ([*sorted((ROOT / 'examples/base/buffer').glob('*.astra')), *BASE, EQUALITY], support / 'failure-hosted.o', MATH),
	}
	start = out / 'start.o'; run(['cc', '-c', FIX / 'start.S', '-o', start])
	for name, (sources, provider, api) in configurations.items():
		stem = out / ('symbols-' + name)
		options = ['--vapi', api] if api else []
		ir = run([compiler, '--dump-llvm', *sources, *options])
		ssa = run([compiler, '--dump-ssa', *sources, *options])
		main = re.search(r'\(function #(\d+) "main" -> int', ssa)[1]
		ir += f'\ndefine i32 @main() {{\n\t%result = call fastcc i32 @astra.fn.{main}()\n\tret i32 %result\n}}\n'
		stem.with_suffix('.ll').write_text(ir)
		run(['llc', '-O0', '-filetype=obj', '-relocation-model=pic', stem.with_suffix('.ll'), '-o', stem.with_suffix('.o')])
		undefined = run(['nm', '-u', stem.with_suffix('.o')])
		if name in ['none', 'pure']:
			assert undefined == '', (name, undefined)
		if name.startswith('contracts-'):
			assert {line.split()[-1] for line in undefined.splitlines()} == {'astra_base_fail'}
		if name == 'buffer':
			assert 'calloc' in undefined and 'free' in undefined
		run(['cc', stem.with_suffix('.o'), *([provider] if provider else []), *(['-lm'] if api else []), '-o', stem])
		run([stem], '')
		linked = run(['nm', '-u', stem]); dependencies = run(['ldd', stem])
		assert not any(word in dependencies.lower() for word in ['glib', 'gobject', 'llvm', 'astra']), (name, dependencies)
		if name in ['none', 'pure', 'contracts-trap']:
			assert not re.search(r'calloc|malloc|free|fprintf|stderr|libm\.', undefined + linked + dependencies)
			free = out / ('freestanding-' + name)
			run(['cc', '-nostdlib', '-static', '-Wl,-e,_start', start, stem.with_suffix('.o'), *([provider] if provider else []), '-o', free])
			assert run(['nm', '-u', free]) == ''
			assert 'NEEDED' not in run(['readelf', '-d', free])
			run([free], '')
		stem.with_suffix('.undefined').write_text(undefined); stem.with_suffix('.linked-undefined').write_text(linked); stem.with_suffix('.ldd').write_text(dependencies)
		rows.append(dict(name=name, object_undefined=undefined.splitlines(), linked_undefined=linked.splitlines(), dependencies=dependencies.splitlines()))
	assert run(['nm', '-u', support / 'failure-trap.o']) == ''
	trap_machine = run(['objdump', '-dr', support / 'failure-trap.o']); (out / 'trap.machine').write_text(trap_machine)
	assert 'ud2' in trap_machine and not re.search(r'\b(?:abort|call|ret)\b', trap_machine)
	# Execute a genuinely failing contract in the CRT/libc-free image too.
	fatal = out / 'fatal.astra'
	ir = run([compiler, '--dump-llvm', fatal, BASE[2]])
	ssa = run([compiler, '--dump-ssa', fatal, BASE[2]])
	main = re.search(r'\(function #(\d+) "main" -> int', ssa)[1]
	ir += f'\ndefine i32 @main() {{\n\t%r = call fastcc i32 @astra.fn.{main}()\n\tret i32 %r\n}}\n'
	(out / 'freestanding-fatal.ll').write_text(ir)
	run(['llc', '-filetype=obj', out / 'freestanding-fatal.ll', '-o', out / 'freestanding-fatal.o'])
	run(['cc', '-nostdlib', '-static', '-Wl,-e,_start', start, out / 'freestanding-fatal.o', support / 'failure-trap.o', '-o', out / 'freestanding-fatal'])
	assert run(['nm', '-u', out / 'freestanding-fatal']) == '' and process([out / 'freestanding-fatal']).returncode < 0
	write_json(out / 'symbols.json', rows)
	return rows


def install(build, out):
	dest = out / 'install'
	run(['meson', 'install', '-C', build, '--no-rebuild', '--destdir', dest])
	options = {row['name']: row['value'] for row in json.loads((build / 'meson-info/intro-buildoptions.json').read_text())}
	prefix = dest / options['prefix'].lstrip('/')
	library = prefix / options['datadir'] / 'astra'
	support = prefix / options['libdir'] / 'astra/x86_64-linux'
	assert (support / 'target.txt').exists()
	installed = out / 'installed'; installed.mkdir(exist_ok=True)
	commands = examples(prefix / 'bin/astrac', library, support, ROOT / 'examples/base', installed, out)
	# Only the install copy and consumer sources live outside the repository;
	# all generated executables/logs stay in the active build directory.
	with tempfile.TemporaryDirectory(prefix='astra-baselib-consumer-') as temporary:
		moved = Path(temporary)
		shutil.copytree(prefix, moved / 'prefix')
		shutil.copytree(ROOT / 'examples/base', moved / 'examples')
		relocated = out / 'relocated'; relocated.mkdir(exist_ok=True)
		commands += examples(moved / 'prefix/bin/astrac', moved / 'prefix' / options['datadir'] / 'astra', moved / 'prefix' / options['libdir'] / 'astra/x86_64-linux', moved / 'examples', relocated, moved / 'examples')
		# Source paths and installation prefixes cannot enter post-syntax identity.
		original = [ROOT / 'examples/base/contracts.astra', *BASE]
		moved_base = [moved / 'prefix' / options['datadir'] / 'astra/base' / path.name for path in BASE]
		for stage in ['semantics', 'core', 'instances', 'cfg', 'ssa', 'nabi', 'cabi', 'llvm']:
			assert run([build / 'astrac', '--dump-' + stage, *original]) == run([moved / 'prefix/bin/astrac', '--dump-' + stage, moved / 'examples/contracts.astra', *moved_base], cwd=moved / 'examples')
	write_json(out / 'consumption-commands.json', commands)
	return dict(prefix=str(prefix), data=options['datadir'], libdir=options['libdir'], external_examples=6, installed_examples=6, relocated_stage_comparisons=8)


def main(build, out):
	out.mkdir(parents=True, exist_ok=True)
	compiler, support = build / 'astrac', build / 'lib/astra'
	driver_records = driver(compiler, out, support)
	symbol_records = symbols(compiler, out, support)
	local = out / 'local'; local.mkdir(exist_ok=True)
	examples(compiler, ROOT / 'lib/astra', support, ROOT / 'examples/base', local, ROOT)
	installed = install(build, out)
	write_json(out / 'results.json', dict(driver_failures=len(driver_records), symbols=symbol_records, install=installed, target=run(['cc', '-dumpmachine']).strip(), compiler=run(['cc', '--version']).splitlines()[0], libc=run(['getconf', 'GNU_LIBC_VERSION']).strip(), llvm=run(['llvm-config', '--version']).strip()))
	print(f'{len(driver_records)} driver failure controls; six symbol boundaries; six local, six installed and six relocated consumers')


if __name__ == '__main__':
	main(Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve())
