# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Four-source installed and relocated exception application in all 24 orders."""
from pathlib import Path
import hashlib
import itertools
import json
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]


def qualify(build, output):
	build = Path(build).resolve(); output = Path(output).resolve(); output.mkdir(parents=True, exist_ok=True)
	rows = []
	def run(command, expected=0, stdout=None, cwd=None):
		p = subprocess.run(list(map(str, command)), capture_output=True, cwd=cwd, timeout=90)
		rows.append(dict(command=list(map(str, command)), expected=expected, observed=p.returncode, stdout_sha256=hashlib.sha256(p.stdout).hexdigest(), stderr_sha256=hashlib.sha256(p.stderr).hexdigest()))
		if str(command[0]) == 'valgrind':
			errors = re.search(rb'ERROR SUMMARY: ([0-9,]+) errors', p.stderr); live = re.search(rb'in use at exit: ([0-9,]+) bytes in ([0-9,]+) blocks', p.stderr); suppressed = re.search(rb'\(suppressed: ([0-9,]+) from ([0-9,]+)\)', p.stderr)
			assert errors is not None and live is not None and suppressed is not None, p.stderr[-4000:]
			rows[-1]['memory'] = dict(errors=int(errors[1].replace(b',', b'')), live_bytes=int(live[1].replace(b',', b'')), live_blocks=int(live[2].replace(b',', b'')), suppressed_errors=int(suppressed[1].replace(b',', b'')), default_suppressions=False)
			assert all(rows[-1]['memory'][name] == 0 for name in ['errors','live_bytes','live_blocks','suppressed_errors']), rows[-1]
		(output/'checks.json').write_text(json.dumps(rows, indent='\t')+'\n')
		assert p.returncode == expected and (stdout is None or p.stdout == stdout), (command, p.returncode, p.stdout[-1000:], p.stderr[-3000:])
		return p.stdout
	options = {row['name']:row['value'] for row in json.loads(run(['meson', 'introspect', build, '--buildoptions']))}
	stage = output/'install'; relocated = output/'relocated'; assert not stage.exists() and not relocated.exists()
	run(['meson', 'install', '-C', build, '--no-rebuild', '--destdir', stage])
	relocated.mkdir(); prefix = relocated/'prefix'; shutil.move(stage/Path(options['prefix']).relative_to('/'), prefix); shutil.rmtree(stage)
	def location(option):
		path = Path(options[option]); return prefix/(path.relative_to(options['prefix']) if path.is_absolute() else path)
	compiler = location('bindir')/'astrac'; library = location('datadir')/'astra'; support = location('libdir')/'astra/x86_64-linux'
	assert (library/'base/errors.astra').read_bytes() == (ROOT/'lib/astra/base/errors.astra').read_bytes()
	assert hashlib.sha256(compiler.read_bytes()).digest() == hashlib.sha256((build/'astrac').read_bytes()).digest()
	client = relocated/'client'; shutil.copytree(ROOT/'tests/error-1/application', client)
	sources = [library/'base/errors.astra', library/'hosted/text.astra', Path('controller.astra'), Path('main.astra')]
	canonical = run([compiler, '--dump-ssa', *sources], cwd=client)
	run([compiler, '--check', *sources[1:]], 1, cwd=client)
	duplicate = client/'duplicate.astra'; duplicate.write_text('[ExceptionRoot]class Fault{readonly string text;init(string text){this.text=text;}virtual property string message{get{return this.text;}}}\n')
	run([compiler, '--check', *sources, duplicate], 1, cwd=client); duplicate.unlink()
	for order in itertools.permutations(sources):
		assert run([compiler, '--dump-ssa', *order], cwd=client) == canonical
		executable = client/'application'; run([compiler, *order, '--link-object', support/'text-posix.o', '-o', executable], cwd=client); run([executable], 42, b'installed\0\xc3\xa9\n', cwd=client)
	plain = client/'plain.astra'; plain.write_text('int main(){return 42;}\n')
	for inputs in ([plain], [plain, library/'base/errors.astra']):
		executable = client/'plain'; run([compiler, *inputs, '-o', executable], cwd=client); run([executable], 42, b'', cwd=client)
	run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', client/'application'], 42, b'installed\0\xc3\xa9\n', cwd=client)
	print(json.dumps(dict(orders=24, installed_compiler_sha256=hashlib.sha256(compiler.read_bytes()).hexdigest(), ssa_sha256=hashlib.sha256(canonical).hexdigest(), source_files=4, old_plain_results=2)))


if __name__ == '__main__':
	sys.dont_write_bytecode = True
	sys.path.insert(0, str(ROOT / 'tools/qualification'))
	from output_paths import fresh_output
	qualify(sys.argv[1], fresh_output(sys.argv[2]))
