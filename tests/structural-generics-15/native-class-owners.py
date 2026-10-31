# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Exercise exact native Class owners and historical closed-Class arguments."""
from pathlib import Path
import hashlib
import json
import os
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[2]
HERE = ROOT / 'tests/language-generalization-10'
EXPORTS = ['Composite10.' + name for name in ['Token', 'Payload', 'Envelope', 'create', 'relay', 'consume']]
GENERIC_EXPORTS = EXPORTS + ['Composite10.' + name for name in ['Sample', 'Store<Composite10.Envelope>',
	'Store<Composite10.Sample>', 'archive', 'forward_archive', 'archive_count']]


def main(compiler_path, output_path, profiles=None):
	compiler = Path(compiler_path).resolve(strict=True)
	output = Path(output_path).resolve()
	assert not output.is_relative_to(ROOT)
	output.mkdir(parents=True, exist_ok=True)
	out = Path(tempfile.mkdtemp(prefix='native-class-owners-', dir=output))
	sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
	sources = [Path(__file__).resolve(), HERE / 'unit-record-provider.astra',
		HERE / 'unit-generic-provider.astra', HERE / 'unit-observer.c', HERE / 'unit-record.py']
	receipt = dict(compiler_sha256=sha(compiler), sources={str(p.relative_to(ROOT)): sha(p) for p in sources}, checks=[], products={})

	def run(argv, stdout=b'', memory=False):
		argv = list(map(str, argv))
		result = subprocess.run(argv, cwd=out, capture_output=True, timeout=90,
			env=dict(os.environ, CCACHE_DISABLE='1', PYTHONDONTWRITEBYTECODE='1', DEBUGINFOD_URLS=''))
		passed = result.returncode == 0 and result.stdout == stdout
		if memory:
			passed &= all(s in result.stderr for s in [b'ERROR SUMMARY: 0 errors',
				b'in use at exit: 0 bytes in 0 blocks', b'(suppressed: 0 from 0)'])
		else:
			passed &= not result.stderr
		receipt['checks'].append(dict(argv=argv, exit=result.returncode, stdout=result.stdout.decode(errors='replace'),
			stderr=result.stderr.decode(errors='replace'), passed=bool(passed)))
		(out / 'checks.json').write_text(json.dumps(receipt, indent='\t') + '\n')
		assert passed, receipt['checks'][-1]

	observer = out / 'observer.o'
	run(['cc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-c', HERE / 'unit-observer.c', '-o', observer])
	profiles = profiles or ['record-owner', 'generic-owner', 'class-argument']
	assert len(profiles) == len(set(profiles)) and set(profiles) <= {'record-owner', 'generic-owner', 'class-argument'}
	receipt['profiles'] = profiles
	for profile in profiles:
		for level in [0, 1, 2]:
			directory = out / f'{profile}-O{level}'
			directory.mkdir()
			provider = directory / 'unit-record-provider.astra'
			# Keep the exact old provider and added own_token implementation.
			text = (HERE / provider.name).read_text()
			if profile != 'class-argument':
				text += '\nint own_token(owned Token token){return token.read();}\n'
			provider.write_text(text)
			inputs = [provider]
			if profile != 'record-owner':
				generic = directory / 'unit-generic-provider.astra'
				generic.write_bytes((HERE / generic.name).read_bytes())
				inputs.append(generic)
			selectors = (GENERIC_EXPORTS if profile == 'generic-owner' else EXPORTS) + [
				'Composite10.Store<Composite10.Token>' if profile == 'class-argument' else 'Composite10.own_token']
			interface, implementation = directory / 'provider.asti', directory / 'provider.o'
			run([compiler, f'-O{level}', '-c', '--module', 'Composite10', '--emit-interface', interface,
				*[part for selector in selectors for part in ['--native-export', selector]], *inputs, '-o', implementation])
			for source in inputs:
				source.unlink()
			consumer = directory / 'consumer.astra'
			if profile == 'class-argument':
				consumer.write_text('''using Composite10;
int main() {
	var store = new Store<Token>(0);
	var first = new Token(11);
	var second = new Token(22);
	if (!store.append(move first) || !store.append(move second)) { return 1; }
	var replacement = new Token(33);
	store.replace(0, move replacement);
	var extracted = store.take(1);
	if (extracted.read() != 22 || store.count() != 1) { return 2; }
	return 0;
}
''')
				trace = b'1:11\n1:22\n1:33\n9:11\n9:22\n9:33\n'
			else:
				consumer.write_text('using Composite10; int main(){var value=new Token(44);return own_token(move value)-44;}\n')
				trace = b'1:44\n9:44\n'
			executable = directory / 'client'
			run([compiler, f'-O{level}', '--import-module', interface, consumer, '--link-object', observer, '-o', executable])
			run([executable], stdout=trace)
			run(['valgrind', '--default-suppressions=no', '--leak-check=full', '--show-leak-kinds=all',
				'--errors-for-leak-kinds=all', '--error-exitcode=99', executable], stdout=trace, memory=True)
			for path in [interface, implementation, executable]:
				receipt['products'][str(path)] = sha(path)
	receipt['status'] = 'PASS'
	(out / 'checks.json').write_text(json.dumps(receipt, indent='\t') + '\n')
	print(out / 'checks.json')
	return out / 'checks.json'


if __name__ == '__main__':
	main(*sys.argv[1:])
