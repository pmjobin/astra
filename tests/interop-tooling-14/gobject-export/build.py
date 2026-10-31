#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Compile real GObject exports, independent clients and scanner-produced GI."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import shlex
import subprocess
import tempfile
import xml.etree.ElementTree as ET


def main():
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument('--compiler', type=Path, required=True)
	parser.add_argument('--output', type=Path, required=True)
	args = parser.parse_args()
	args.compiler = args.compiler.resolve()
	source = Path(__file__).resolve().parent
	root = source.parents[2]
	output = args.output.resolve()
	assert not output.is_relative_to(root)
	output.mkdir(parents=True, exist_ok=True)
	work = Path(tempfile.mkdtemp(prefix='gobject-export-', dir=output))
	identity = {'scope': 'actual native GObject export and mixed C+GObject',
		'compiler_sha256': hashlib.sha256(args.compiler.read_bytes()).hexdigest(), 'checks': []}
	inputs = [source / name for name in ('counter.astra', 'client.c', 'normalized.c', 'support.c', 'introspection.py', 'build.py')]
	inputs.append(root / 'lib/runtime/interop/foreign-14.c')
	inputs += [root / 'lib/runtime/runtime' / name for name in ('monitors-13.c', 'monitors-13.h')]
	identity['sources'] = {str(path.relative_to(root)): hashlib.sha256(path.read_bytes()).hexdigest() for path in inputs}
	def save():
		(work / 'build.json').write_text(json.dumps(identity, indent=2) + '\n')
	def run(command, contains='', env=None, expected=0):
		assert hashlib.sha256(args.compiler.read_bytes()).hexdigest() == identity['compiler_sha256'], 'compiler changed during qualification'
		p = subprocess.run(list(map(str, command)), capture_output=True, text=True, timeout=120, cwd=work,
			env=dict(os.environ, CCACHE_DISABLE='1', G_DEBUG='fatal-warnings', **(env or {})))
		identity['checks'].append({'command': list(map(str, command)), 'exit': p.returncode, 'expected_exit': expected, 'stdout': p.stdout, 'stderr': p.stderr})
		save()
		assert p.returncode == expected and contains in p.stdout + p.stderr, identity['checks'][-1]
		return p.stdout
	identity['providers'] = run(['pkg-config', '--modversion', 'gobject-2.0', 'gobject-introspection-1.0'])
	unit = source / 'counter.astra'
	(work / 'counter.h').write_text(run([args.compiler, '--emit-class-header', unit]))
	(work / 'gobject14.h').write_text(run([args.compiler, '--emit-gobject-header', unit]))
	(work / 'adapter.c').write_text(run([args.compiler, '--emit-gobject-source', unit]))
	identity['generated_sources'] = {name: hashlib.sha256((work / name).read_bytes()).hexdigest() for name in ('counter.h', 'gobject14.h', 'adapter.c')}
	flags = ['-std=c11', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread']
	includes = shlex.split(run(['pkg-config', '--cflags', 'gobject-2.0']))
	libs = shlex.split(run(['pkg-config', '--libs', 'gobject-2.0']))
	for level in ('0', '1', '2'):
		prefix = work / ('prefix-O' + level)
		(prefix / 'lib').mkdir(parents=True)
		(prefix / 'include').mkdir()
		for name in ('counter.h', 'gobject14.h'):
			(prefix / 'include' / name).write_bytes((work / name).read_bytes())
		obj = work / ('native-O' + level + '.o')
		run([args.compiler, '-O' + level, '-c', unit, '-o', obj])
		library = prefix / 'lib/libastra14.so'
		run(['cc', *flags, '-O' + level, '-fPIC', '-shared', '-Wl,-z,defs', '-Wl,-soname,libastra14.so', *includes,
			'-Wl,--wrap=calloc', '-Wl,--wrap=g_try_malloc0', '-Wl,--wrap=g_try_malloc0_n',
			work / 'adapter.c', source / 'support.c', root / 'lib/runtime/interop/foreign-14.c', obj, *libs, '-o', library])
		binary = work / ('client-O' + level)
		run(['cc', *flags, '-O2', '-I', prefix / 'include', *includes, source / 'client.c', '-L', prefix / 'lib',
			'-Wl,-rpath,' + str(prefix / 'lib'), '-lastra14', *libs, '-o', binary])
		run([binary], contains='partial-native-cleanup restored-adaptation')
		if level in ('0', '2'):
			run(['valgrind', '--vgdb=no', '--default-suppressions=no', '--leak-check=full',
				'--show-leak-kinds=definite,indirect,possible', '--errors-for-leak-kinds=definite,indirect,possible',
				'--error-exitcode=99', binary], contains='ERROR SUMMARY: 0 errors')
		gir_dir = prefix / 'share/gir-1.0'
		typelib_dir = prefix / 'lib/girepository-1.0'
		gir_dir.mkdir(parents=True)
		typelib_dir.mkdir()
		gir = gir_dir / 'Astra14-1.0.gir'
		typelib = typelib_dir / 'Astra14-1.0.typelib'
		environment = {'LD_LIBRARY_PATH': str(prefix / 'lib'), 'GI_TYPELIB_PATH': str(typelib_dir)}
		run(['g-ir-scanner', '--no-libtool', '--namespace=Astra14', '--nsversion=1.0', '--include=GObject-2.0',
			'--identifier-prefix=Astra14', '--symbol-prefix=astra14', '--library=astra14', '--library-path=' + str(prefix / 'lib'),
			'--c-include=gobject14.h', '--warn-all', '--warn-error', '--output=' + str(gir), '--pkg=gobject-2.0',
			'-I' + str(prefix / 'include'), prefix / 'include/gobject14.h'], env=environment)
		ns = {'g': 'http://www.gtk.org/introspection/core/1.0', 's': 'http://www.gtk.org/introspection/glib/1.0'}
		class_info = ET.parse(gir).getroot().find('.//g:class', ns)
		assert class_info is not None and class_info.get('name') == 'Counter'
		assert class_info.find('g:property', ns).get('name') == 'value'
		assert class_info.find('s:signal', ns).get('name') == 'changed'
		assert class_info.find("g:function[@name='as_gobject']", ns).get('introspectable') == '0'
		run(['g-ir-compiler', gir, '--output=' + str(typelib)])
		run(['g-ir-inspect', '--version=1.0', '--print-shlibs', 'Astra14'], contains='libastra14.so', env=environment)
		run(['python3', source / 'introspection.py'], contains='exact native finalization', env=environment)
		identity.setdefault('products', {})[level] = {str(path.relative_to(prefix)): hashlib.sha256(path.read_bytes()).hexdigest()
			for path in sorted(prefix.rglob('*')) if path.is_file()}
	healthy = unit.read_text()
	# The admitted Shared/Monitor composition keeps exactly the same foreign
	# headers/adapter. Its native methods acquire/release the explicit monitor,
	# while foreign data access still refuses the wrong constructing thread.
	monitor = work / 'monitor.astra'
	monitor.write_text(healthy.replace('[Shared]', '[Shared,Monitor]'))
	identity['monitor_source_sha256'] = hashlib.sha256(monitor.read_bytes()).hexdigest()
	for option, name in [('--emit-class-header', 'counter.h'), ('--emit-gobject-header', 'gobject14.h'), ('--emit-gobject-source', 'adapter.c')]:
		assert run([args.compiler, option, monitor]) == (work / name).read_text()
	for level in ('0', '2'):
		obj = work / ('monitor-O' + level + '.o')
		binary = work / ('monitor-O' + level)
		run([args.compiler, '-O' + level, '-c', monitor, '-o', obj])
		run(['cc', *flags, '-O2', '-I', work, *includes, work / 'adapter.c', source / 'client.c', source / 'support.c',
			root / 'lib/runtime/interop/foreign-14.c', root / 'lib/runtime/runtime/monitors-13.c', obj,
			'-Wl,--wrap=calloc', '-Wl,--wrap=g_try_malloc0', '-Wl,--wrap=g_try_malloc0_n', *libs, '-o', binary])
		run([binary], contains='partial-native-cleanup restored-adaptation')
		run(['valgrind', '--vgdb=no', '--default-suppressions=no', '--leak-check=full',
			'--errors-for-leak-kinds=definite,indirect,possible', '--error-exitcode=99', binary], contains='ERROR SUMMARY: 0 errors')
		identity.setdefault('monitor_products', {})[level] = hashlib.sha256(binary.read_bytes()).hexdigest()
	normalized = work / 'normalized.astra'
	normalized.write_text(healthy.replace('set(int value) { this.data = value; }',
		'set(int value) { if (value == this.data) { this.data = value + 1; } else { if (value < 0) { this.data = 0; } else { if (value > 100) { this.data = 100; } else { this.data = value; } } } }'))
	for level in ('0', '2'):
		obj = work / ('normalized-O' + level + '.o')
		run([args.compiler, '-O' + level, '-c', normalized, '-o', obj])
		binary = work / ('normalized-O' + level)
		run(['cc', *flags, '-O2', '-I', work, *includes, work / 'adapter.c', source / 'normalized.c', source / 'support.c',
			root / 'lib/runtime/interop/foreign-14.c', obj, '-Wl,--wrap=calloc', '-Wl,--wrap=g_try_malloc0', '-Wl,--wrap=g_try_malloc0_n', *libs, '-o', binary])
		run([binary], contains='signals reflect committed values')
	bad = work / 'invalid.astra'
	for text, reason in [
		(healthy.replace('[CExport(name="astra14_counter", property="value")]', ''), 'explicit Class CExport bridge'),
		(healthy.replace('version="1.0"', 'version="2.0"'), 'explicit Type/Namespace/1.0'),
		(healthy.replace('name="astra14_counter"', 'name="wrong_counter"'), 'matching snake-case C prefix'),
		(healthy.replace('namespace="Astra14"', 'namespace="Wrong"'), 'explicit Type/Namespace/1.0'),
		(healthy.replace('[Shared]', ''), 'plain Shared'),
		(healthy.replace('[Shared]', '[ThreadBound,Shared]'), 'plain Shared'),
		(healthy.replace('[GObjectExport', '[COMExport]\n[GObjectExport'), 'incompatible selected foreign personalities'),
	]:
		bad.write_text(text)
		run([args.compiler, '--check', bad], expected=1, contains=reason)
	for stage in ('syntax', 'semantics', 'core', 'cfg', 'ssa', 'nabi', 'cabi'):
		run([args.compiler, '--dump-' + stage, unit], contains='GObjectExport')
	run([args.compiler, '--target=x86_64-w64-windows-gnu', '--check', unit], expected=1, contains='hosted Linux x64')
	run([args.compiler, '--runtime=none', '--check', unit], expected=1, contains='hosted Linux x64')
	run([args.compiler, '--emit-gobject-header', unit, '-o', unit], expected=2)
	assert unit.read_text() == healthy
	run([args.compiler, '--check', unit])
	pure = work / 'pure.astra'
	pure.write_text('[Shared] class Cell { init() {} }\nint main() { var root = new Cell(); var copy = root.clone(); release root; release copy; return 0; }\n')
	run([args.compiler, '-O2', pure, '-o', work / 'pure'])
	run([work / 'pure'])
	dependencies = run(['readelf', '-d', work / 'pure'])
	assert not any(name in dependencies for name in ['libgobject', 'libglib', 'libLLVM', 'libffi'])
	assert all(hashlib.sha256(path.read_bytes()).hexdigest() == identity['sources'][str(path.relative_to(root))] for path in inputs), 'test inputs changed during qualification'
	identity['status'] = 'PASS C runtime and installed scanner-generated GIR/typelib consumers'
	save()
	print(work)


if __name__ == '__main__':
	main()
