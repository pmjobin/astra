# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Ordinary bounded Ninja build and explicit risk-selected Meson tests."""
from pathlib import Path
import hashlib
import json
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence, identity


def main(build, output):
	build = Path(build).resolve()
	assert not build.is_relative_to(ROOT)
	e = Evidence(build / 'astrac', output, 'surge-12-regressions')
	selection = Path(__file__).with_name('regression-selection.txt')
	names = selection.read_text().splitlines()
	assert names and len(names) == len(set(names))
	introspection = {}
	for category in ('tests', 'targets', 'buildsystem-files'):
		command = ['meson', 'introspect', str(build), '--' + category]
		result = subprocess.run(command, check=True, capture_output=True, text=True)
		introspection[category] = json.loads(result.stdout)
		e.data.setdefault('introspection', []).append(dict(command=command,
			sha256=hashlib.sha256(result.stdout.encode()).hexdigest(), exit=result.returncode))
	assert str(ROOT / 'meson.build') in introspection['buildsystem-files'], 'shared build routes to a different source'
	tests = {row['name']: row for row in introspection['tests']}
	assert set(names) <= set(tests), set(names) - set(tests)
	targets = {row['id']: row for row in introspection['targets']}
	dependencies = sorted({dependency for name in names for dependency in tests[name]['depends']})
	products = sorted({str(Path(filename).relative_to(build)) for dependency in dependencies for filename in targets[dependency]['filename']})
	e.data['selection'] = names
	e.data['pre_build_compiler'] = e.data['compiler']
	e.files(selection)
	e.run(['ninja', '-C', build, '-j4', *products], timeout=1800)
	e.data['compiler'] = identity(e.compiler)
	e.run(['meson', 'test', '-C', build, '--no-rebuild', '--num-processes', '2',
		'--print-errorlogs', '--logbase', 'surge-12-final-selection', *names], timeout=3600)
	e.files(build / 'meson-logs/surge-12-final-selection.json',
		build / 'meson-logs/surge-12-final-selection.txt')
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
