# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Four-source virtual-task application in every installed and relocated order."""
import hashlib
import itertools
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys

SOURCE = Path(__file__).resolve().parents[2]

def sha(path):
	return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
	build, output = Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve()
	output.mkdir(parents=True, exist_ok=True)
	run_root = output / 'current'
	owner = {'purpose': 'ASYNC-1 staged/relocated generated installation witness', 'source': str(SOURCE)}
	if run_root.exists():
		assert not run_root.is_symlink() and json.loads((run_root / 'owner.json').read_text()) == owner
		history = output / 'receipt-history'
		history.mkdir(exist_ok=True)
		prior = run_root / 'receipts.json'
		if prior.exists():
			(history / (sha(prior) + '.json')).write_bytes(prior.read_bytes())
		shutil.rmtree(run_root)
	run_root.mkdir()
	(run_root / 'owner.json').write_text(json.dumps(owner) + '\n')
	receipts = []
	def run(name, command, expected=0, cwd=None, stdout=None):
		result = subprocess.run(list(map(str, command)), cwd=cwd, capture_output=True, timeout=90)
		row = {'name': name, 'command': list(map(str, command)), 'expected_exit': expected, 'actual_exit': result.returncode, 'stdout_sha256': hashlib.sha256(result.stdout).hexdigest(), 'stderr_sha256': hashlib.sha256(result.stderr).hexdigest(), 'status': 'PASS' if result.returncode == expected and (stdout is None or result.stdout == stdout) else 'FAIL'}
		if command[0] == 'valgrind':
			errors = re.search(rb'ERROR SUMMARY: ([0-9,]+) errors', result.stderr)
			live = re.search(rb'in use at exit: ([0-9,]+) bytes in ([0-9,]+) blocks', result.stderr)
			suppressed = re.search(rb'\(suppressed: ([0-9,]+) from ([0-9,]+)\)', result.stderr)
			assert errors is not None and live is not None and suppressed is not None, result.stderr[-4000:]
			row['memory'] = {'errors': int(errors[1].replace(b',', b'')), 'live_bytes': int(live[1].replace(b',', b'')), 'live_blocks': int(live[2].replace(b',', b'')), 'suppressed_errors': int(suppressed[1].replace(b',', b'')), 'default_suppressions': False}
			if any(row['memory'][key] != 0 for key in ('errors', 'live_bytes', 'live_blocks', 'suppressed_errors')):
				row['status'] = 'FAIL'
		receipts.append(row)
		(run_root / 'receipts.json').write_text(json.dumps({'compiler_sha256': sha(build / 'astrac'), 'receipts': receipts}, indent='\t') + '\n')
		print(name, row['status'], flush=True)
		assert row['status'] == 'PASS', (command, result.returncode, result.stdout[-1000:], result.stderr[-3000:])
		return result.stdout
	options = {row['name']: row['value'] for row in json.loads(run('install-options', ['meson', 'introspect', build, '--buildoptions']))}
	stage = run_root / 'stage'
	run('staged-install', ['meson', 'install', '-C', build, '--no-rebuild', '--destdir', stage])
	prefix = stage / Path(options['prefix']).relative_to('/')
	client = run_root / 'client'
	shutil.copytree(SOURCE / 'tests/async-1/application', client)
	canonical = None
	stage_identities = []
	for phase in ('staged', 'relocated'):
		if phase == 'relocated':
			relocated = run_root / 'relocated-prefix'
			shutil.move(prefix, relocated)
			prefix = relocated
		def location(option):
			path = Path(options[option])
			return prefix / (path.relative_to(options['prefix']) if path.is_absolute() else path)
		compiler = location('bindir') / 'astrac'
		library = location('datadir') / 'astra'
		support = location('libdir') / 'astra/x86_64-linux/async-virtual.o'
		assert sha(compiler) == sha(build / 'astrac')
		for name in ('base/errors.astra', 'async/virtual.astra', 'async/virtual.c', 'async/virtual.h'):
			assert (library / name).read_bytes() == (SOURCE / 'lib/astra' / name).read_bytes()
		assert sha(support) == sha(build / 'lib/astra/async-virtual.o')
		sources = [library / 'base/errors.astra', library / 'async/virtual.astra', Path('controller.astra'), Path('main.astra')]
		observed = run(phase + '-source-order-canonical', [compiler, '--dump-ssa', *sources], cwd=client)
		if canonical is None:
			canonical = observed
		assert observed == canonical
		run(phase + '-missing-nomination', [compiler, '--check', sources[0], *sources[2:]], expected=1, cwd=client)
		duplicate = client / 'duplicate.astra'
		duplicate.write_text('async runtime OtherExecutor throws AsyncError returns RunStatus;\n')
		run(phase + '-duplicate-nomination', [compiler, '--check', *sources, duplicate], expected=1, cwd=client)
		duplicate.unlink()
		for index, order in enumerate(itertools.permutations(sources)):
			run(phase + '-source-order-%02d' % index, [compiler, '--dump-ssa', *order], cwd=client, stdout=canonical)
			executable = client / 'application'
			run(phase + '-source-native-link-%02d' % index, [compiler, *order, '--link-object', support, '-o', executable], cwd=client)
			run(phase + '-source-native-execute-%02d' % index, [executable], expected=42, cwd=client, stdout=b'')
		stage_identities.append({'phase': phase, 'orders': 24, 'compiler_sha256': sha(compiler), 'virtual_support_sha256': sha(support), 'ssa_sha256': hashlib.sha256(canonical).hexdigest()})
	run('installed-native-memory', ['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', client / 'application'], expected=42, cwd=client, stdout=b'')
	identity = {'installation_phases': stage_identities, 'source_files': 4, 'orders': 24, 'compiler_sha256': sha(compiler), 'virtual_support_sha256': sha(support), 'ssa_sha256': hashlib.sha256(canonical).hexdigest(), 'source_sha256': {str(path): sha(client / path if not path.is_absolute() else path) for path in sources}, 'receipts': receipts}
	(run_root / 'receipts.json').write_text(json.dumps(identity, indent='\t') + '\n')
	(output / 'current.json').write_text(json.dumps({'run': run_root.name, 'receipts_sha256': sha(run_root / 'receipts.json'), 'status': 'PASS'}, indent='\t') + '\n')
	return 0

if __name__ == '__main__':
	sys.exit(main())
