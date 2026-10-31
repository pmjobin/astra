#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Execute distinct A126/A127/A128 through independent C and relocated GI clients."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import tempfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]


def sha(path):
	return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument('compiler', type=Path)
	parser.add_argument('output', type=Path)
	parser.add_argument('--prefix', type=Path)
	args = parser.parse_args()
	compiler, output = args.compiler.resolve(), args.output.resolve()
	assert not output.is_relative_to(ROOT)
	output.mkdir(parents=True, exist_ok=True)
	work = Path(tempfile.mkdtemp(prefix='gobject-applications-', dir=output))
	installed = args.prefix.resolve() if args.prefix else None
	if installed:
		assert compiler == installed / 'bin/astrac'
	sources = installed / 'share/astra/examples/interop-tooling-14/gobject' if installed else ROOT / 'examples/interop-tooling-14/gobject'
	lib = installed / 'share/astra' if installed else ROOT / 'lib/astra'
	rows, applications = [], {}
	receipt = {'compiler_sha256': sha(compiler), 'checks': rows, 'applications': applications,
		'sources': {p.name: sha(p) for p in sources.iterdir() if p.is_file()}}
	def run(command, *, contains='', env=None):
		assert sha(compiler) == receipt['compiler_sha256'], 'compiler changed during qualification'
		p = subprocess.run(list(map(str, command)), cwd=work, capture_output=True, text=True, timeout=120,
			env=dict(os.environ, CCACHE_DISABLE='1', G_DEBUG='fatal-warnings', **(env or {})))
		rows.append({'command': list(map(str, command)), 'environment': env or {}, 'exit': p.returncode,
			'stdout': p.stdout, 'stderr': p.stderr})
		(work / 'checks.json').write_text(json.dumps(receipt, indent=2) + '\n')
		assert p.returncode == 0 and contains in p.stdout + p.stderr, rows[-1]
		return p.stdout
	receipt['providers'] = run(['pkg-config', '--modversion', 'gobject-2.0', 'gobject-introspection-1.0'])
	includes = shlex.split(run(['pkg-config', '--cflags', 'gobject-2.0']))
	libs = shlex.split(run(['pkg-config', '--libs', 'gobject-2.0']))
	# This installed GLib uses GNU __COUNTER__ in public inline/macro bodies.
	# Preserve warnings as errors; select its GNU C11 SDK dialect explicitly.
	flags = ['-std=gnu11', '-Wall', '-Wextra', '-Werror', '-pthread']
	ns = {'g': 'http://www.gtk.org/introspection/core/1.0'}
	for number, filename in [('126', 'a126-settings.astra'), ('127', 'a127-diagnostic.astra'), ('128', 'a128-publisher.astra')]:
		app = 'A' + number
		namespace = 'Astra' + number
		name = namespace.lower()
		appwork = work / app
		appwork.mkdir()
		units = [sources / filename]
		if number == '127':
			units += [lib / 'base/errors.astra', lib / 'text/utf8-message.astra']
		receipt.setdefault('native_inputs', {})[app] = {str(p): sha(p) for p in units}
		header = appwork / (namespace + '.h')
		header.write_text(run([compiler, '--emit-gobject-header', *units]))
		native_header = appwork / ('a' + number + '-native.h')
		native_header.write_text(run([compiler, '--emit-class-header', *units]))
		adapter = appwork / 'adapter.c'
		adapter.write_text(run([compiler, '--emit-gobject-source', *units]))
		variants = []
		applications[app] = {'source_sha256': sha(units[0]), 'variants': variants}
		for level in ('0', '1', '2'):
			prefix = appwork / ('install-O' + level)
			for directory in ('lib', 'include', 'bin', 'share/gir-1.0', 'lib/girepository-1.0'):
				(prefix / directory).mkdir(parents=True, exist_ok=True)
			for h in (header, native_header):
				shutil.copyfile(h, prefix / 'include' / h.name)
			extra = []
			if number == '127':
				shutil.copyfile(sources / 'a127-report.h', prefix / 'include/a127-report.h')
				extra = [sources / 'a127-report.c', lib / 'platform/text-ops-posix.c']
			obj = appwork / ('native-O' + level + '.o')
			run([compiler, '-O' + level, '-c', *units, '-o', obj])
			library = prefix / ('lib/lib' + name + '.so')
			run(['gcc', *flags, '-O2', '-fPIC', '-shared', '-Wl,-z,defs', '-Wl,-soname,lib' + name + '.so',
				*includes, '-I', prefix / 'include', adapter, sources / 'app-support.c', *extra,
				lib / 'interop/foreign-14.c', obj, *libs, '-o', library])
			for cc in ('gcc', 'clang'):
				run([cc, *flags, '-O2', *includes, '-I', prefix / 'include', sources / ('a' + number + '-client.c'),
					'-L', prefix / 'lib', '-Wl,-rpath,$ORIGIN/../lib', '-l' + name, *libs, '-o', prefix / ('bin/' + cc + '-client')])
			gir = prefix / ('share/gir-1.0/' + namespace + '-1.0.gir')
			typelib = prefix / ('lib/girepository-1.0/' + namespace + '-1.0.typelib')
			headers = [prefix / 'include' / header.name]
			if number == '127':
				headers.append(prefix / 'include/a127-report.h')
			run(['g-ir-scanner', '--no-libtool', '--namespace=' + namespace, '--nsversion=1.0', '--include=GObject-2.0',
				'--identifier-prefix=' + namespace, '--symbol-prefix=' + name, '--library=' + name,
				'--library-path=' + str(prefix / 'lib'), '--c-include=' + header.name, '--warn-all', '--warn-error',
				'--output=' + str(gir), '--pkg=gobject-2.0', '-I' + str(prefix / 'include'), *headers],
				env={'LD_LIBRARY_PATH': str(prefix / 'lib')})
			class_info = ET.parse(gir).getroot().find('.//g:class', ns)
			assert class_info is not None and class_info.find('g:property', ns).get('name') == 'value'
			if number == '127':
				method = class_info.find("g:method[@name='report']", ns)
				assert method is not None and method.get('throws') == '1'
				assert method.find('g:return-value', ns).get('transfer-ownership') == 'full'
			run(['g-ir-compiler', gir, '--output=' + str(typelib)])
			# Move the complete installed library/headers/GIR/typelib/client tree before use.
			relocated = appwork / ('relocated-O' + level)
			prefix.rename(relocated)
			assert not prefix.exists()
			environment = {'LD_LIBRARY_PATH': str(relocated / 'lib'), 'GI_TYPELIB_PATH': str(relocated / 'lib/girepository-1.0')}
			for cc in ('gcc', 'clang'):
				binary = relocated / ('bin/' + cc + '-client')
				run([binary], contains='PASS ' + app, env=environment)
				if level in ('0', '2'):
					run(['valgrind', '--vgdb=no', '--default-suppressions=no', '--leak-check=full',
						'--show-leak-kinds=definite,indirect,possible', '--errors-for-leak-kinds=definite,indirect,possible',
						'--error-exitcode=99', binary], contains='ERROR SUMMARY: 0 errors', env=environment)
			run(['g-ir-inspect', '--version=1.0', '--print-shlibs', namespace], contains='lib' + name + '.so', env=environment)
			run(['python3', sources / 'introspection.py', namespace], contains='PASS ' + namespace + ' relocated', env=environment)
			deps = run(['readelf', '-d', relocated / ('lib/lib' + name + '.so')])
			assert 'libLLVM' not in deps and 'libstdc++' not in deps
			variants.append({'optimization': level, 'prefix': str(relocated), 'files': {
				str(p.relative_to(relocated)): sha(p) for p in sorted(relocated.rglob('*')) if p.is_file()}})
		applications[app]['status'] = 'PASS C runtime, relocated scanner GIR/typelib and Python GI'
	receipt['status'] = 'PASS'
	(work / 'checks.json').write_text(json.dumps(receipt, indent=2) + '\n')
	print(f'PASS: A126/A127/A128 real C and relocated GI; {len(rows)} commands; evidence {work}')


if __name__ == '__main__':
	main()
