# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Build and execute the explicitly selected final-source qualification."""
from pathlib import Path
import hashlib
import json
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence, identity


def main(build, output):
	build = Path(build).resolve()
	e = Evidence(build / 'astrac', output, 'concurrency-final-selection')
	selection = Path(__file__).with_name('regression-selection.txt')
	historical = selection.read_text().splitlines()
	assert historical and len(historical) == len(set(historical))
	registered = json.loads(e.run(['meson', 'introspect', build, '--tests']).stdout)
	tests = {row['name']: row for row in registered}
	current = sorted(name for name in tests if name.startswith('concurrency-runtime-13-'))
	assert len(current) == 22, current
	names = current + historical
	assert set(names) <= tests.keys(), set(names) - tests.keys()
	targets = {row['id']: row for row in json.loads(e.run(['meson', 'introspect', build, '--targets']).stdout)}
	dependencies = {dep for name in names for dep in tests[name]['depends']}
	products = sorted({str(Path(filename).relative_to(build)) for dep in dependencies for filename in targets[dep]['filename']})
	build_files = json.loads(e.run(['meson', 'introspect', build, '--buildsystem-files']).stdout)
	assert str(ROOT / 'meson.build') in build_files
	e.data['selection'] = names
	e.data['pre_build_compiler'] = e.data['compiler']
	e.run(['ninja', '-C', build, '-j4', *products], timeout=1800)
	e.data['compiler'] = identity(e.compiler)
	logbase = 'concurrency-runtime-13-final'
	e.run(['meson', 'test', '-C', build, '--no-rebuild', '--num-processes', '1',
		'--print-errorlogs', '--logbase', logbase, *names], timeout=7200,
		env={'ASTRA_LIBURING_PREFIX': str(Path.home() / '.local/opt/liburing-2.15')})
	log = build / 'meson-logs' / (logbase + '.json')
	rows = [json.loads(line) for line in log.read_text().splitlines()]
	assert len(rows) == len(names), (len(rows), len(names))
	assert all(row['result'] == 'OK' and row['returncode'] == 0 for row in rows)
	e.run([sys.executable, ROOT / 'tests/interop-async-5/timer-check.py', e.compiler,
		e.output / 'timer', Path.home() / '.local/opt/liburing-2.15'], timeout=900)
	e.data['results'] = [{'name': row['name'], 'result': row['result'], 'seconds': row['duration']} for row in rows]
	e.data['source_tree'] = hashlib.sha256(e.run(['git', '-C', ROOT, 'diff', '--binary', 'HEAD']).stdout.encode()).hexdigest()
	e.files(selection, Path(__file__), log, log.with_suffix('.txt'))
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
