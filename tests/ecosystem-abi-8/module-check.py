# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independent native units: ABI/owner matrix, unavailable source, debug and refusals."""
from pathlib import Path
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
EXPORTS = ['Native8.Pair', 'Native8.Cell', 'Native8.twice', 'Native8.pack', 'Native8.adjust', 'Native8.make', 'Native8.inspect']
EXPECTED = b'1:9\n9:9\n1:10\n9:10\n'


def main(compiler_path, output_path):
	compiler, output = Path(compiler_path).resolve(), Path(output_path).resolve()
	assert not output.is_relative_to(ROOT)
	output.mkdir(parents=True, exist_ok=True)
	out = Path(tempfile.mkdtemp(prefix='module-', dir=output))
	rows = []
	sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
	receipt = dict(compiler=str(compiler), compiler_sha256=sha(compiler), checks=rows)

	def run(command, expected=0, contains=(), stdout=None):
		command = list(map(str, command))
		p = subprocess.run(command, cwd=ROOT, capture_output=True, timeout=90,
			env=dict(os.environ, CCACHE_DISABLE='1', DEBUGINFOD_URLS=''))
		text = (p.stdout+p.stderr).decode(errors='replace')
		valid = p.returncode == expected and all(s in text for s in contains) and (stdout is None or p.stdout == stdout)
		rows.append(dict(command=command, expected_exit=expected, exit=p.returncode,
			stdout=p.stdout.decode(errors='replace'), stderr=p.stderr.decode(errors='replace'), passed=valid))
		(out/'checks.json').write_text(json.dumps(receipt, indent=2)+'\n')
		assert valid, rows[-1]
		return p.stdout

	def provider(directory, level, source=HERE/'module-provider.astra', exports=EXPORTS, debug=True, expected=0, contains=()):
		directory.mkdir(exist_ok=True)
		flags = ['-g'] if debug else []
		run([compiler, *flags, f'-O{level}', '-c', '--module', 'Native8', '--emit-interface', directory/'provider.asti',
			*[item for name in exports for item in ('--native-export', name)], source, '-o', directory/'provider.o'], expected, contains)
		return directory/'provider.asti', directory/'provider.o'

	observer = out/'observer.o'
	run(['/usr/bin/cc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-c', HERE/'module-observer.c', '-o', observer])
	providers = {level: provider(out/f'p{level}', level) for level in (0, 1, 2)}
	products = []
	for producer_level, consumer_level in ((0, 0), (0, 2), (2, 0), (2, 2), (1, 1)):
		interface, implementation = providers[producer_level]
		directory = out/f'p{producer_level}-c{consumer_level}'; directory.mkdir()
		consumer, executable = directory/'consumer.o', directory/'program'
		run([compiler, '-g', f'-O{consumer_level}', '--entry-object', '--import-module', interface, HERE/'module-consumer.astra', '-o', consumer])
		run(['/usr/bin/cc', '-no-pie', consumer, implementation, observer, '-o', executable])
		run([executable], stdout=EXPECTED)
		run(['llvm-dwarfdump', '--verify', executable], contains=('No errors.', 'module-consumer.astra', 'module-provider.astra'))
		run(['readelf', '--debug-dump=decodedline', executable], contains=('module-consumer.astra', 'module-provider.astra'))
		run(['valgrind', '--default-suppressions=no', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=definite,indirect,possible', '--error-exitcode=99', executable], stdout=EXPECTED,
			contains=('ERROR SUMMARY: 0 errors',))
		memory = rows[-1]['stderr']
		assert 'All heap blocks were freed' in memory or all(s in memory for s in ('definitely lost: 0 bytes', 'indirectly lost: 0 bytes', 'possibly lost: 0 bytes'))
		dependencies = run(['readelf', '-d', executable])
		assert b'libgobject' not in dependencies and b'libglib' not in dependencies
		products += [consumer, executable]
	interface, implementation = providers[0]
	run(['/usr/bin/cc', '-no-pie', out/'p0-c0/consumer.o', observer, '-o', out/'missing-provider'], expected=1, contains=('undefined reference', 'astra_mod_'))
	run([compiler, '-O2', '--import-module', interface, HERE/'module-consumer.astra', '--link-object', observer, '-o', out/'driver-linked'])
	run([out/'driver-linked'], stdout=EXPECTED)
	llvm = run([compiler, '--dump-llvm', '--import-module', interface, HERE/'module-consumer.astra']).decode()
	assert len(re.findall(r'^declare fastcc .*@astra_mod_', llvm, re.M)) >= 8
	assert not re.search(r'^define .*@astra_mod_', llvm, re.M)
	run(['nm', '-g', '--defined-only', implementation], contains=('astra_mod_',))
	debug_program = out/'p0-c0/program'
	run(['gdb', '--nx', '--batch', '-ex', 'set debuginfod enabled off', '-ex', f'break {HERE/"module-provider.astra"}:21',
		'-ex', 'run', '-ex', 'print delta', '-ex', 'continue', debug_program], contains=('Breakpoint 1,', '$1 = 2', 'exited normally'))

	# Producer implementation text is absent during this separate consumer build.
	directory = out/'unavailable-source'; directory.mkdir()
	source = directory/'provider-source.astra'; source.write_bytes((HERE/'module-provider.astra').read_bytes())
	missing_interface, missing_object = provider(directory, 0, source=source, debug=False)
	metadata = missing_interface.read_text()
	assert 'module_event' not in metadata and 'secret' not in metadata and str(source) not in metadata
	source.unlink()
	assert not source.exists()
	run([compiler, '-O2', '--import-module', missing_interface, HERE/'module-consumer.astra', '--link-object', observer, '-o', directory/'program'])
	run([directory/'program'], stdout=EXPECTED)
	assert not source.exists()

	# Copying sources to a distinct path and reordering declarations preserves ABI.
	directory = out/'reordered'; directory.mkdir()
	text = (HERE/'module-provider.astra').read_text()
	line = 'int twice(int value) { return value * 2; }\n'
	assert text.count(line) == 1
	source = directory/'reordered.astra'; source.write_text(text.replace(line, '')+'\n'+line)
	reordered, _ = provider(directory, 2, source=source)
	identity = lambda p: re.search(r'^identity=(.*)$', p.read_text(), re.M).group(1)
	assert identity(reordered) == identity(interface)

	baseline = interface.read_bytes()
	mutations = {
		'version': ('format=astra-native-module/2', 'format=astra-native-module/0'),
		'schema': ('schema=gnu-x86_64-lp64-runtime-units/6', 'schema=obsolete/0'),
		'compiler': ('compiler=', 'compiler=obsolete'),
		'target': ('target=', 'target=wrong-'),
		'layout': ('data_layout=', 'data_layout=wrong-'),
		'ownership': (':heap', ':lexical'),
		'type': ('source(int,', 'source(f64,'),
		'physical-result': ('result=I32;', 'result=F64;'),
		'visibility': ('int:1@', 'int:0@'),
		'extent': ('size=4;', 'size=8;'),
		'symbol': ('symbol=astra_mod_', 'symbol=forged_'),
		'fingerprint': ('fingerprint=', 'fingerprint=0'),
	}
	for name, (old, new) in mutations.items():
		assert old.encode() in baseline, (name, old)
		interface.write_bytes(baseline.replace(old.encode(), new.encode(), 1))
		run([compiler, '--check', '--import-module', interface, HERE/'module-consumer.astra'], expected=1, contains=('native module:',))
		interface.write_bytes(baseline)
	for suffix in (b'\x00hidden', b'\n[unknown]\nfield=value\n', b'\n[abi]\nmodule=Native8\n'):
		interface.write_bytes(baseline+suffix)
		run([compiler, '--check', '--import-module', interface, HERE/'module-consumer.astra'], expected=1, contains=('native module:',))
		interface.write_bytes(baseline)
	object_bytes = implementation.read_bytes()
	implementation.write_bytes(observer.read_bytes())
	run([compiler, '--check', '--import-module', interface, HERE/'module-consumer.astra'], expected=1, contains=('object identity mismatch',))
	implementation.write_bytes(object_bytes)
	run([compiler, '--check', '--import-module', interface, HERE/'module-consumer.astra'])

	negatives = {
		'private-field': 'using Native8; int main(){var cell=make(1);return cell.value;}',
		'internal-access': 'using Native8; int main(){return secret(1);}',
		'borrow-escape': 'using Native8; owned Cell bad(borrowed Cell cell){return move cell;} int main(){return 0;}',
		'collision': 'namespace Native8; int twice(int value){return value;}',
	}
	for name, text in negatives.items():
		source = out/(name+'.astra'); source.write_text(text+'\n')
		run([compiler, '--check', '--import-module', interface, source], expected=1, contains=('error:',))
	provider(out/'internal-export', 0, exports=[*EXPORTS, 'Native8.secret'], expected=1, contains=('internal function cannot be exported',))
	assert not (out/'internal-export/provider.o').exists()
	run([compiler, '--entry-object', '--check', HERE/'module-consumer.astra'], expected=2)
	run([compiler, '--module', 'Native8', '-c', HERE/'module-provider.astra'], expected=2)
	run([debug_program], stdout=EXPECTED)
	receipt['sources'] = {str(p.relative_to(ROOT)): sha(p) for p in [HERE/'module-provider.astra', HERE/'module-consumer.astra', HERE/'module-observer.c']}
	receipt['products'] = {str(p.relative_to(out)): sha(p) for p in [observer, *products, *[p for pair in providers.values() for p in pair]]}
	(out/'checks.json').write_text(json.dumps(receipt, indent=2)+'\n')
	print(f'PASS: independent native modules O0/O2 matrix + O1, Class/POD ABI, absent source, DWARF/GDB, memory and refusals; evidence {out}')


if __name__ == '__main__':
	main(*sys.argv[1:])
