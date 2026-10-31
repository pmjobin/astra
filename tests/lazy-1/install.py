# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Four source inputs, all 24 orders at staged and relocated prefixes."""
import hashlib
import itertools
import json
from pathlib import Path
import shutil
import subprocess
import sys

SOURCE = Path(__file__).resolve().parents[2]

def sha(path):
	return hashlib.sha256(path.read_bytes()).hexdigest()

def main(build, output):
	output.mkdir(parents=True, exist_ok=True)
	current = output/'current'
	owner = {'task': 'LAZY-1 installation witness', 'source': str(SOURCE)}
	if current.exists():
		assert not current.is_symlink() and json.loads((current/'owner.json').read_text()) == owner
		prior = current/'receipts.json'
		if prior.exists():
			history = output/'receipt-history'
			history.mkdir(exist_ok=True)
			(history/(sha(prior)+'.json')).write_bytes(prior.read_bytes())
		shutil.rmtree(current)
	current.mkdir()
	(current/'owner.json').write_text(json.dumps(owner)+'\n')
	record = {'compiler_sha256': sha(build/'astrac'), 'receipts': [], 'phases': []}
	def run(name, argv, expected=0, stdout=None, cwd=SOURCE):
		p = subprocess.run(list(map(str, argv)), capture_output=True, cwd=cwd, timeout=90)
		row = {'name': name, 'command': list(map(str, argv)), 'expected_exit': expected, 'observed_exit': p.returncode, 'stdout_sha256': hashlib.sha256(p.stdout).hexdigest(), 'stderr_sha256': hashlib.sha256(p.stderr).hexdigest(), 'status': 'PASS' if p.returncode == expected and (expected != 0 or not p.stderr) and (stdout is None or p.stdout == stdout) else 'FAIL'}
		record['receipts'].append(row)
		(current/'receipts.json').write_text(json.dumps(record, separators=(',', ':'))+'\n')
		assert row['status'] == 'PASS', (name, p.returncode, p.stdout[-1000:], p.stderr[-3000:])
		return p.stdout
	options = {r['name']: r['value'] for r in json.loads(run('options', ['meson', 'introspect', build, '--buildoptions']))}
	stage = current/'stage'
	run('install', ['meson', 'install', '-C', build, '--no-rebuild', '--destdir', stage])
	prefix = stage/Path(options['prefix']).relative_to('/')
	client = current/'client'
	shutil.copytree(SOURCE/'tests/lazy-1/application', client)
	helper = client/'observer.o'
	run('strict-observer', ['gcc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-c', SOURCE/'tests/lazy-1/fixtures/observer.c', '-o', helper])
	canonical = None
	for phase in ('staged', 'relocated'):
		if phase == 'relocated':
			new = current/'relocated-prefix'
			shutil.move(prefix, new)
			prefix = new
		def locate(option):
			path = Path(options[option])
			return prefix/(path.relative_to(options['prefix']) if path.is_absolute() else path)
		compiler, library = locate('bindir')/'astrac', locate('datadir')/'astra'
		assert sha(compiler) == sha(build/'astrac') and (library/'base/errors.astra').read_bytes() == (SOURCE/'lib/astra/base/errors.astra').read_bytes()
		sources = [library/'base/errors.astra', Path('model.astra'), Path('operations.astra'), Path('main.astra')]
		observed = run(phase+'-SSA', [compiler, '--dump-ssa', *sources], cwd=client)
		if canonical is None: canonical = observed
		assert observed == canonical
		run(phase+'-missing-root', [compiler, '--check', *sources[1:]], expected=1, cwd=client)
		for index, order in enumerate(itertools.permutations(sources)):
			run(phase+f'-order-{index:02d}', [compiler, '--dump-ssa', *order], stdout=canonical, cwd=client)
			run(phase+f'-link-{index:02d}', [compiler, *order, '--link-object', helper, '-o', client/'application'], cwd=client)
			run(phase+f'-execute-{index:02d}', [client/'application'], expected=42, stdout=b'FLOOE', cwd=client)
		plain = client/'plain.astra'
		plain.write_text('class Plain{init(){}lazy property int value{get{return 42;}}}int main(){var object=new Plain();return object.value;}\n')
		ir = run(phase+'-plain-LLVM', [compiler, '--dump-llvm', plain], cwd=client)
		assert b'astra.class.1' not in ir and b'original.exception' not in ir and b'astra.text.' not in ir
		run(phase+'-plain-link', [compiler, plain, '-o', client/'plain'], cwd=client)
		run(phase+'-plain-execute', [client/'plain'], expected=42, stdout=b'', cwd=client)
		record['phases'].append({'phase': phase, 'orders': 24, 'source_files': 4, 'SSA_sha256': hashlib.sha256(canonical).hexdigest(), 'compiler_sha256': sha(compiler)})
	record['status'] = 'PASS'
	(current/'receipts.json').write_text(json.dumps(record, separators=(',', ':'))+'\n')
	print('LAZY installation PASS: 24 orders at each prefix; exact FLOOE trace; independent plain lazy client')

if __name__ == '__main__':
	main(Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve())
