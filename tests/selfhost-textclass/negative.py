#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Preserve frozen C0 refusals and distinguish unsupported native operations."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import resource
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]


def sha(path):
	return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
	resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
	p = argparse.ArgumentParser()
	for name in ('compiler', 'component', 'frozen', 'build', 'runtime'): p.add_argument('--'+name, type=Path, required=True)
	p.add_argument('--mode', choices=('O0', 'O2'), required=True); a = p.parse_args()
	assert all(not path.resolve().is_relative_to(ROOT) for path in (a.build, a.runtime))
	a.runtime.mkdir(parents=True, exist_ok=False); a.build.mkdir(parents=True, exist_ok=True)
	assert sha(a.compiler) == 'e3b2a5d6a4b9c5a42becbc3704f2d062489fb6f99a5ed1727461dfef4cf8681b'
	identity = json.loads(a.component.with_suffix('.identity.json').read_text()); assert sha(a.component) == identity['sha256']
	assert all(sha(path) == value for group in ('sources', 'tools') for path, value in identity['identity'][group].items())
	commands, rows = [], []
	def run(argv, name):
		start = time.monotonic(); environment = dict(os.environ, CCACHE_DISABLE='1'); environment.pop('VALGRIND_OPTS', None)
		r = subprocess.run(['/usr/bin/time', '-v', '-o', a.runtime/(name+'.time'), *map(str, argv)], cwd=a.build, capture_output=True, timeout=180, env=environment)
		(a.runtime/(name+'.stdout')).write_bytes(r.stdout); (a.runtime/(name+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(name=name, argv=list(map(str, argv)), exit=r.returncode, seconds=time.monotonic()-start)); (a.runtime/'commands.json').write_text(json.dumps(commands, indent=2)+'\n'); return r
	for item in json.loads((a.frozen/'negatives.json').read_text()):
		name = item['name']; assert all(sha(row['path']) == row['sha256'] for row in item['sources']); sources = [row['path'] for row in item['sources']]
		assert all(row['build_exit'] == 1 for row in item['C0'].values())
		oracle = run([a.compiler, '--check', *sources], name+'-C0'); assert oracle.returncode == 1 and b'error:' in oracle.stderr
		candidate = run([a.component, '--classstorage-admit', a.mode, a.build/'unused', *sources], name+'-admit'); assert candidate.returncode != 0 and any(word in candidate.stdout for word in (b'ERROR', b'DEFER'))
		output = a.build/(name+'.o'); output.write_bytes(b'preserved-textclass-negative-destination\n'); original = sha(output)
		writer = run([a.component, '--classstorage-emit-obj', a.mode, output, *sources], name+'-writer'); assert writer.returncode != 0 and sha(output) == original
		rows.append(dict(name=name, sources=item['sources'], classification='C0_INVALID_NATIVE_REFUSED', candidate_exit=candidate.returncode, writer_exit=writer.returncode, destination_preserved=original))
		# The complete original module, including its recoverable factory, is a
		# separate source contract. Native refusal must not become an invalidity claim.
	factory = a.runtime/'invalid-utf8-factory.astra'
	factory.write_text('''int main() {
	u8[2] bytes = {192, 175};
	try { var message = utf8_message(slice(bytes)); return 90; } catch (InvalidUtf8 error) { return 5; }
}
''')
	sources = [ROOT/'lib/astra/base/errors.astra', ROOT/'lib/astra/text/utf8-message.astra', factory]
	product = a.build/'C0-invalid-utf8'; oracle = run([a.compiler, '-'+a.mode, *sources, '-o', product], 'factory-C0-build'); assert oracle.returncode == 0, oracle.stderr[-1000:]
	oracle = run([product], 'factory-C0-execute'); assert oracle.returncode == 5
	memory = run(['valgrind', '--command-line-only=yes', '--default-suppressions=no', '--trace-malloc=yes', '--error-exitcode=97', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', '--track-origins=yes', product], 'factory-C0-memory'); assert memory.returncode == 5
	output = a.build/'factory-refused.o'; output.write_bytes(b'preserved-factory-deferred-destination\n'); original = sha(output)
	candidate = run([a.component, '--classstorage-admit', a.mode, output, *sources], 'factory-native-admit'); writer = run([a.component, '--classstorage-emit-obj', a.mode, output, *sources], 'factory-native-writer')
	assert candidate.returncode in (1, 2, 3) and writer.returncode == 2 and sha(output) == original
	assert any(word in candidate.stdout for word in (b'ERROR', b'DEFER')) and b'LLVM_' in writer.stderr
	rows.append(dict(name='original-invalid-utf8-factory', sources=[dict(path=str(path), sha256=sha(path)) for path in sources], classification='C0_RECOVERABLE_INVALID_UTF8_NATIVE_EXCEPTION_FACTORY_DEFERRED', C0_exit=5, C0_normal_memory_exit=5, candidate_exit=candidate.returncode, destination_preserved=original))
	(a.runtime/'result.json').write_text(json.dumps(dict(status='PASS', mode=a.mode, component_sha256=sha(a.component), cases=rows, limitation='Factory and recoverable exceptions remain native DEFERRED. Only C0 execution/cleanup and native pre-output refusal are qualified here.'), indent=2)+'\n')
	print('Six frozen invalid programs refused; C0 recoverable UTF-8 error is clean and remains native DEFERRED')


if __name__ == '__main__':
	main()
