# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independent composite native units, ownership ABI, absent source and memory."""
from pathlib import Path
import hashlib
import importlib.util
import json
import os
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
EXPORTS = ['Composite10.'+name for name in ['Token', 'Payload', 'Envelope', 'create', 'relay', 'consume']]
TRACE = b'1:3\n1:4\n2:122\n9:3\n9:4\n1:10\n1:11\n9:10\n3:140\n9:11\n1:20\n1:21\n2:34\n9:20\n9:21\n'
GENERIC_EXPORTS = EXPORTS+['Composite10.'+name for name in ['Sample', 'Store<Composite10.Envelope>', 'Store<Composite10.Sample>', 'archive', 'forward_archive', 'archive_count']]
GENERIC_TRACE = b'1:1\n1:2\n1:3\n1:4\n1:5\n1:6\n2:122\n9:3\n9:4\n1:20\n1:21\n9:2\n9:1\n1:30\n1:31\n2:126\n9:5\n9:6\n4:126\n9:31\n9:30\n9:21\n9:20\n5:18\n6:31\n'


def main(compiler_path, output_path, profile='record'):
	assert profile in ['record', 'generic']
	compiler, output = Path(compiler_path).resolve(), Path(output_path).resolve()
	assert not output.is_relative_to(ROOT)
	output.mkdir(parents=True, exist_ok=True)
	out = Path(tempfile.mkdtemp(prefix=profile+'-units-', dir=output))
	sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
	provider, observer = HERE/'unit-record-provider.astra', HERE/'unit-observer.c'
	provider_inputs = [provider]+([HERE/'unit-generic-provider.astra'] if profile == 'generic' else [])
	consumer = HERE/('unit-'+profile+'-consumer.astra')
	exports = GENERIC_EXPORTS if profile == 'generic' else EXPORTS
	trace = GENERIC_TRACE if profile == 'generic' else TRACE
	receipt = dict(compiler=str(compiler), compiler_sha256=sha(compiler),
		sources={str(path.relative_to(ROOT)): sha(path) for path in [*provider_inputs, consumer, observer, Path(__file__).resolve()]}, profile=profile, checks=[], products={})

	def run(argv, expected=0, diagnostic=None, memory=False, stdout=b''):
		argv = list(map(str, argv))
		result = subprocess.run(argv, cwd=ROOT, capture_output=True, timeout=90,
			env=dict(os.environ, CCACHE_DISABLE='1', PYTHONDONTWRITEBYTECODE='1'))
		passed = result.returncode == expected and (stdout is None or result.stdout == stdout)
		if diagnostic:
			passed &= diagnostic.encode() in result.stderr
			passed &= all(word not in result.stderr for word in [b'internal error', b'assertion', b'CRITICAL'])
		elif memory:
			passed &= all(word in result.stderr for word in [b'ERROR SUMMARY: 0 errors', b'in use at exit: 0 bytes in 0 blocks', b'(suppressed: 0 from 0)'])
		else:
			passed &= not result.stderr
		receipt['checks'].append(dict(command=argv, expected_exit=expected, actual_exit=result.returncode,
			stdout=result.stdout.decode(errors='replace'), stderr=result.stderr.decode(errors='replace'), passed=bool(passed),
			astra_inputs={arg: sha(Path(arg)) for arg in argv if arg.endswith('.astra') and Path(arg).is_file()}))
		(out/'checks.json').write_text(json.dumps(receipt, indent=2)+'\n')
		assert passed, receipt['checks'][-1]
		return result.stdout

	observer_object = out/'observer.o'
	for source in [*provider_inputs, consumer]:
		run([compiler, '--format', '--check', source])
	run(['cc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-c', observer, '-o', observer_object])
	providers = {}
	for level in [0, 1, 2]:
		directory = out/f'p{level}'; directory.mkdir()
		sources = []
		for source in provider_inputs:
			copy = directory/source.name; copy.write_bytes(source.read_bytes()); sources.append(copy)
		interface, implementation = directory/'provider.asti', directory/'provider.o'
		run([compiler, f'-O{level}', '-c', '--module', 'Composite10', '--emit-interface', interface,
			*[item for name in exports for item in ['--native-export', name]], *sources, '-o', implementation])
		metadata = interface.read_bytes()
		assert b'runtime-units/6' in metadata and b'owner=' in metadata and b'buffer=I32' in metadata and b'class=Composite10.Token' in metadata
		assert b'unit_event' not in metadata and b'secret' not in metadata
		if profile == 'generic':
			assert b'generic=Composite10.Store;' in metadata and b'[function C:Composite10.Store<Composite10.Sample>::deinit]' in metadata
			assert b'len(this.entries)' not in metadata, 'producer generic body leaked into its interface'
		for source in sources:
			assert str(source).encode() not in metadata
			source.unlink(); assert not source.exists()
		providers[level] = interface, implementation
		receipt['products'][str(interface)] = sha(interface); receipt['products'][str(implementation)] = sha(implementation)
	identity = lambda path: re.search(rb'^identity=(.+)$', path.read_bytes(), re.M).group(1)
	assert len({identity(pair[0]) for pair in providers.values()}) == 1
	if profile == 'generic':
		directory = out/'reordered'; directory.mkdir()
		run([compiler, '-O2', '-c', '--module', 'Composite10', '--emit-interface', directory/'provider.asti',
			*[item for name in reversed(exports) for item in ['--native-export', name]], *reversed(provider_inputs), '-o', directory/'provider.o'])
		assert identity(directory/'provider.asti') == identity(providers[0][0])
	for stage in ['--check', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-llvm']:
		run([compiler, stage, '--import-module', providers[0][0], consumer], stdout=None)
	for producer_level, consumer_level in [(0, 0), (0, 2), (2, 0), (2, 2), (1, 1)]:
		interface, implementation = providers[producer_level]
		consumer_object = out/f'p{producer_level}-c{consumer_level}.o'
		executable = out/f'p{producer_level}-c{consumer_level}'
		run([compiler, f'-O{consumer_level}', '--entry-object', '--import-module', interface, consumer, '-o', consumer_object])
		run(['cc', '-no-pie', consumer_object, implementation, observer_object, '-o', executable])
		run([executable], stdout=trace)
		run(['valgrind', '--default-suppressions=no', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', '--error-exitcode=99', executable], memory=True, stdout=trace)
		receipt['products'][str(consumer_object)] = sha(consumer_object); receipt['products'][str(executable)] = sha(executable)
	interface, implementation = providers[0]
	llvm = run([compiler, '--dump-llvm', '--import-module', interface, consumer], stdout=None)
	assert len(re.findall(rb'^declare fastcc .*@astra_mod_', llvm, re.M)) >= 6
	assert not re.search(rb'^define .*@astra_mod_', llvm, re.M)
	run([compiler, '-O2', '--import-module', interface, consumer, '--link-object', observer_object, '-o', out/'driver-linked'])
	run([out/'driver-linked'], stdout=trace)
	controls = [
		('record-copy', 'relay(move value)', 'relay(value)', 'move'),
		('private-field', 'child.read() != 10', 'child.code != 10', 'private'),
		('consumed-owner', 'if (consume(move next, 7) != 122)', 'consume(move next, 7); if (consume(move next, 7) != 122)', 'moved'),
	] if profile == 'record' else [
		('generic-record-copy', 'values.replace(0, move replacement)', 'values.replace(0, replacement)', 'move'),
		('generic-owner-copy', 'forward_archive(move original)', 'forward_archive(original)', 'move'),
		('generic-wrong-specialization', 'var original = archive(1);', 'var original = archive(1); var wrong = new Store<Sample>(0); archive_count(wrong);', 'type'),
	]
	for name, before, after, diagnostic in controls:
		invalid = out/(name+'.astra'); invalid.write_text(consumer.read_text().replace(before, after, 1))
		for stage in ['--check', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-llvm']:
			run([compiler, stage, '--import-module', interface, invalid], expected=1, diagnostic=diagnostic)
	if profile == 'generic':
		invalid = out/'unexported-specialization.astra'
		invalid.write_text('using Composite10; struct OtherSample{int x;} int main(){var value=new Store<OtherSample>(0);return value.count();}\n')
		for stage in ['--check', '--dump-nabi', '--dump-llvm']:
			run([compiler, stage, '--import-module', interface, invalid], expected=1, diagnostic='unexpected imported native callable')
	baseline = interface.read_bytes()
	for old, new in [
		(b'runtime-units/6', b'composite-owners/1'),
		(b'target=', b'target=wrong-'), (b'data_layout=', b'data_layout=wrong-'),
		(b'record(Composite10.Envelope,1,', b'record(Composite10.Envelope,0,'),
		(b'buffer=I32:', b'buffer=U32:'), (b'class=Composite10.Token', b'class=Composite10.Wrong'),
		(b'owned=1;', b'owned=0;'),
	]:
		assert old in baseline
		interface.write_bytes(baseline.replace(old, new, 1))
		run([compiler, '--check', '--import-module', interface, consumer], expected=1, diagnostic='native module:')
		interface.write_bytes(baseline)
	run([compiler, '--check', '--import-module', interface, consumer])
	# Approved exact historical producers now execute through the shared
	# positive recipe, with unchanged selectors and hidden implementation source.
	positive_recipe = ROOT / 'tests/structural-generics-15/native-class-owners.py'
	spec = importlib.util.spec_from_file_location('native_class_owners', positive_recipe)
	positive = importlib.util.module_from_spec(spec); spec.loader.exec_module(positive)
	positive_profiles = ['record-owner'] if profile == 'record' else ['generic-owner', 'class-argument']
	positive_path = positive.main(compiler, out / 'approved-native-owners', positive_profiles)
	positive_receipt = json.loads(positive_path.read_text())
	assert positive_receipt['status'] == 'PASS' and positive_receipt['compiler_sha256'] == receipt['compiler_sha256']
	receipt['sources'][str(positive_recipe.relative_to(ROOT))] = sha(positive_recipe)
	receipt['approved_native_owners'] = dict(path=str(positive_path), sha256=sha(positive_path), profiles=positive_profiles)
	if profile == 'generic':
		name = 'open-template'
		selectors = [*EXPORTS, 'Composite10.Store']
		run([compiler, '-c', '--module', 'Composite10', '--emit-interface', out/(name+'.asti'),
			*[item for selector in selectors for item in ['--native-export', selector]], *provider_inputs, '-o', out/(name+'.o')], expected=1, diagnostic='explicit closed')
		assert not (out/(name+'.o')).exists() and not (out/(name+'.asti')).exists()
	receipt['status'] = 'PASS'
	(out/'checks.json').write_text(json.dumps(receipt, indent=2)+'\n')
	print(f'PASS {len(receipt["checks"])} {profile} unit commands; receipt {out / "checks.json"}')


if __name__ == '__main__':
	main(*sys.argv[1:])
