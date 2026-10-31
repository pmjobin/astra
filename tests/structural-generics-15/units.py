# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Qualify opaque transitive native-unit graphs and independent metadata refusals."""
from pathlib import Path
import hashlib
import itertools
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time


ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent


def sha(path):
	return hashlib.sha256(path.read_bytes()).hexdigest()


def metadata(text):
	groups = {}
	current = None
	for line in text.splitlines():
		if not line:
			continue
		if line.startswith('[') and line.endswith(']'):
			current = line[1:-1]
			assert current not in groups
			groups[current] = {}
		else:
			key, value = line.split('=', 1)
			assert key not in groups[current]
			groups[current][key] = value
	return groups


def encoded(groups):
	return '\n\n'.join('[' + name + ']\n' + '\n'.join(
		key + '=' + value for key, value in fields.items())
		for name, fields in groups.items()) + '\n'


def fingerprint(groups, include_object):
	parts = []
	for name in sorted(groups):
		if name == 'receipt' or (not include_object and name == 'object'):
			continue
		parts.append(f'{len(name)}:{name}')
		for key in sorted(groups[name]):
			if not include_object and key in ['identity', 'symbol', 'declarations', 'declarations_sha256']:
				continue
			value = groups[name][key]
			parts.append(f'{len(key)}:{key}{len(value)}:{value}')
	return hashlib.sha256(''.join(parts).encode()).hexdigest()


def reseal(groups):
	groups['abi']['identity'] = fingerprint(groups, False)
	groups['receipt']['fingerprint'] = fingerprint(groups, True)
	return encoded(groups)


def main(compiler_path, output_path):
	compiler = Path(compiler_path).resolve(strict=True)
	output = Path(output_path).resolve()
	assert not output.is_relative_to(ROOT)
	output.mkdir(parents=True, exist_ok=True)
	out = Path(tempfile.mkdtemp(prefix='typed-units-', dir=output))
	fixtures = [HERE / name for name in ['unit-leaf.astra', 'unit-middle.astra',
		'unit-client.astra', 'unit-side.astra', 'unit-top.astra', 'unit-diamond-client.astra',
		'unit-owner-middle.astra', 'unit-owner-client.astra', 'unit-declared-provider.astra',
		'unit-declared-middle.astra', 'unit-declared-client.astra', 'unit-type-only-provider.astra',
		'unit-type-only-client.astra', 'unit-resource-provider.astra', 'unit-resource-middle.astra',
		'unit-resource-client.astra', 'unit-callable-provider.astra', 'unit-callable-middle.astra',
		'unit-callable-client.astra', 'unit-class-callable-provider.astra',
		'unit-class-callable-middle.astra', 'unit-class-callable-client.astra',
		'unit-record-callable-provider.astra', 'unit-record-callable-middle.astra',
		'unit-record-callable-client.astra', 'unit-resource-result-provider.astra',
		'unit-resource-result-middle.astra', 'unit-resource-result-client.astra',
		'unit-class-result-provider.astra', 'unit-class-result-middle.astra', 'unit-class-result-client.astra',
		'unit-record-result-provider.astra', 'unit-record-result-middle.astra', 'unit-record-result-client.astra',
		'unit-record-loan-provider.astra', 'unit-record-loan-middle.astra', 'unit-record-loan-client.astra',
		'unit-symbolic-callable-provider.astra', 'unit-symbolic-callable-middle.astra', 'unit-symbolic-callable-client.astra',
		'unit-symbolic-consuming-provider.astra', 'unit-symbolic-consuming-middle.astra', 'unit-symbolic-consuming-client.astra',
		'unit-symbolic-result-provider.astra', 'unit-symbolic-result-middle.astra', 'unit-symbolic-result-client.astra',
		'unit-owned-formal-middle.astra', 'unit-owned-formal-client.astra', 'scoped-code-inspection.astra',
		'unit-method-provider.astra', 'unit-method-middle.astra', 'unit-method-client.astra',
		'unit-checked-provider.astra', 'unit-checked-middle.astra', 'unit-checked-client.astra',
		'unit-closure-provider.astra', 'unit-closure-client.astra',
		'unit-interface-provider.astra', 'unit-interface-middle.astra', 'unit-interface-client.astra',
		'unit-task-provider.astra', 'unit-task-middle.astra', 'unit-task-client.astra',
		'unit-readonly-provider.astra', 'unit-readonly-middle.astra', 'unit-readonly-client.astra',
		'unit-callback-provider.astra', 'unit-callback-middle.astra', 'unit-callback-client.astra',
		'../../lib/astra/collections/map.astra']]
	owner_provider = ROOT / 'tests/language-generalization-10/unit-record-provider.astra'
	owner_observer = ROOT / 'tests/language-generalization-10/unit-observer.c'
	resource_api = ROOT / 'tests/own-field/fixtures/resources.vapi'
	resource_observer = ROOT / 'tests/own-field/companion.c'
	receipt = dict(format='astra-m15-typed-unit-graphs/1', compiler=str(compiler),
		compiler_sha256=sha(compiler), sources={str(p.relative_to(ROOT)): sha(p)
		for p in [Path(__file__).resolve(), *fixtures, owner_provider, owner_observer, resource_api, resource_observer]}, checks=[], products={})

	def save():
		(out / 'checks.json').write_text(json.dumps(receipt, indent='\t') + '\n')

	def run(argv, expected=0, diagnostic=None, memory=False, stdout=b'', cwd=out):
		argv = list(map(str, argv))
		started = time.perf_counter()
		result = subprocess.run(argv, cwd=cwd, capture_output=True, timeout=90,
			env=dict(os.environ, CCACHE_DISABLE='1', PYTHONDONTWRITEBYTECODE='1', DEBUGINFOD_URLS=''))
		passed = result.returncode == expected and (stdout is None or result.stdout == stdout)
		if diagnostic:
			passed &= diagnostic.encode() in result.stderr
			passed &= all(word not in result.stderr for word in [b'assertion', b'CRITICAL', b'internal error'])
		elif memory:
			passed &= all(word in result.stderr for word in [b'ERROR SUMMARY: 0 errors',
				b'in use at exit: 0 bytes in 0 blocks', b'(suppressed: 0 from 0)'])
		else:
			passed &= not result.stderr
		receipt['checks'].append(dict(argv=argv, cwd=str(cwd), expected_exit=expected,
			exit=result.returncode, elapsed_seconds=time.perf_counter() - started,
			stdout=result.stdout.decode(errors='replace'), stderr=result.stderr.decode(errors='replace'), passed=bool(passed)))
		save()
		assert passed, receipt['checks'][-1]
		return result.stdout

	def product(path):
		receipt['products'][str(path)] = dict(sha256=sha(path), bytes=path.stat().st_size)

	def stage(source, destination):
		for path in source.iterdir():
			if path.suffix in ['.asti', '.o']:
				shutil.copyfile(path, destination / path.name)

	def provider(directory, stem, module, exported, level, imports=(), source=None, vapis=()):
		directory.mkdir(exist_ok=True)
		copy = directory / (stem + '-implementation.astra')
		copy.write_bytes((HERE / ('unit-' + stem + '.astra')).read_bytes() if source is None else source)
		interface, implementation = directory / (stem + '.asti'), directory / (stem + '.o')
		selectors = [exported] if isinstance(exported, str) else exported
		run([compiler, '-g', '-O' + str(level), '-c', '--module', module,
			*[item for path in vapis for item in ['--vapi', path]],
			'--emit-interface', interface, *[item for name in selectors for item in ['--native-export', name]],
			*[item for path in imports for item in ['--import-module', directory / path]],
			copy, '-o', implementation])
		text = interface.read_text()
		assert 'astra-native-module/2' in text and 'gnu-x86_64-lp64-runtime-units/6' in text
		assert str(copy) not in text and '* 3' not in text and '+ 2' not in text and '+ 5' not in text
		groups = metadata(text)
		assert encoded(groups) == text
		assert fingerprint(groups, False) == groups['abi']['identity']
		assert fingerprint(groups, True) == groups['receipt']['fingerprint']
		copy.unlink()
		assert not copy.exists()
		product(interface)
		product(implementation)
		return interface

	consumer = out / 'consumer.astra'
	consumer.write_bytes((HERE / 'unit-client.astra').read_bytes())
	leaves = {}
	for level in [0, 1, 2]:
		directory = out / ('leaf-' + str(level))
		provider(directory, 'leaf', 'StructuralLeaf', 'StructuralLeaf.transform', level)
		leaves[level] = directory
	middles = {}
	for leaf_level, middle_level in [*itertools.product([0, 2], repeat=2), (1, 1)]:
		directory = out / f'l{leaf_level}-m{middle_level}'
		directory.mkdir()
		stage(leaves[leaf_level], directory)
		provider(directory, 'middle', 'StructuralMiddle', 'StructuralMiddle.combine',
			middle_level, ['leaf.asti'])
		groups = metadata((directory / 'middle.asti').read_text())
		assert groups['dependency StructuralLeaf']['interface_sha256'] == sha(directory / 'leaf.asti')
		assert groups['dependency StructuralLeaf']['object_sha256'] == sha(directory / 'leaf.o')
		middles[leaf_level, middle_level] = directory
	for leaf_level, middle_level, client_level in [*itertools.product([0, 2], repeat=3), (1, 1, 1)]:
		directory = middles[leaf_level, middle_level]
		executable = directory / ('client-O' + str(client_level))
		run([compiler, '-g', '-O' + str(client_level), '--import-module', directory / 'middle.asti',
			consumer, '-o', executable])
		run([executable])
		run(['valgrind', '--default-suppressions=no', '--leak-check=full', '--show-leak-kinds=all',
			'--errors-for-leak-kinds=all', '--error-exitcode=99', executable], memory=True)
		product(executable)

		# Nested record ownership and its two independent Class children and buffer
		# pass through the dependent producer's actual record argument/result plans.
	observer = out / 'owner-observer.o'
	run(['cc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-c', owner_observer, '-o', observer])
	product(observer)
	owner_consumer = out / 'owner-consumer.astra'
	owner_consumer.write_bytes((HERE / 'unit-owner-client.astra').read_bytes())
	owner_exports = ['Composite10.' + name for name in ['Token', 'Payload', 'Envelope', 'create', 'relay', 'consume']]
	owner_leaves = {}
	for level in [0, 1, 2]:
		directory = out / ('owner-leaf-' + str(level))
		provider(directory, 'owner-leaf', 'Composite10', owner_exports, level, source=owner_provider.read_bytes())
		assert 'unit_event' not in (directory / 'owner-leaf.asti').read_text()
		owner_leaves[level] = directory
	owner_middles = {}
	for leaf_level, middle_level in [*itertools.product([0, 2], repeat=2), (1, 1)]:
		directory = out / f'owner-l{leaf_level}-m{middle_level}'
		directory.mkdir()
		stage(owner_leaves[leaf_level], directory)
		provider(directory, 'owner-middle', 'StructuralOwners', ['StructuralOwners.relay', 'StructuralOwners.consume'],
			middle_level, ['owner-leaf.asti'])
		owner_middles[leaf_level, middle_level] = directory
	for leaf_level, middle_level, client_level in [*itertools.product([0, 2], repeat=3), (1, 1, 1)]:
		directory = owner_middles[leaf_level, middle_level]
		executable = directory / ('owner-client-O' + str(client_level))
		run([compiler, '-O' + str(client_level), '--import-module', directory / 'owner-middle.asti',
			owner_consumer, '--link-object', observer, '-o', executable])
		trace = b'1:3\n1:4\n2:122\n9:3\n9:4\n'
		run([executable], stdout=trace)
		run(['valgrind', '--default-suppressions=no', '--leak-check=full', '--show-leak-kinds=all',
			'--errors-for-leak-kinds=all', '--error-exitcode=99', executable], memory=True, stdout=trace)
		product(executable)
	base = middles[0, 0]

	# Resource channels use the same native cleanup authority as record leaves.
	# Every compiler process receives only the public platform declarations.
	resource_object = out / 'resource-observer.o'
	run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-O2', '-c', resource_observer, '-o', resource_object])
	resource_members = ['create', 'relay', 'inspect', 'consume', 'empty', 'create_other', 'relay_other', 'inspect_other', 'consume_other']
	resource_leaves = {}
	for level in [0, 1, 2]:
		directory = out / ('resource-leaf-' + str(level))
		provider(directory, 'resource-provider', 'NativeResources', ['NativeResources.' + member for member in resource_members], level, vapis=[resource_api])
		resource_leaves[level] = directory
	resource_middles = {}
	for leaf_level, middle_level in [*itertools.product([0, 2], repeat=2), (1, 1)]:
		directory = out / f'resource-l{leaf_level}-m{middle_level}'
		directory.mkdir()
		stage(resource_leaves[leaf_level], directory)
		provider(directory, 'resource-middle', 'ResourceTransport', ['ResourceTransport.' + member for member in resource_members], middle_level,
			imports=['resource-provider.asti'], vapis=[resource_api])
		resource_middles[leaf_level, middle_level] = directory
	resource_consumer = out / 'resource-consumer.astra'
	resource_consumer.write_bytes((HERE / 'unit-resource-client.astra').read_bytes())
	for leaf_level, middle_level, client_level in [*itertools.product([0, 2], repeat=3), (1, 1, 1)]:
		directory = resource_middles[leaf_level, middle_level]
		executable = directory / ('client-O' + str(client_level))
		run([compiler, '-O' + str(client_level), '--vapi', resource_api, '--import-module', directory / 'resource-middle.asti',
			resource_consumer, '--link-object', resource_object, '-o', executable])
		trace = b'+231\n-231\n+232\n-232\n+233\n-233\n+234\n+235\n-235\n-234\n'
		run([executable], stdout=trace)
		run(['valgrind', '--default-suppressions=no', '--leak-check=full', '--show-leak-kinds=all',
			'--errors-for-leak-kinds=all', '--error-exitcode=99', executable], memory=True, stdout=trace)
		product(executable)

	resource_base = resource_middles[0, 0]
	wrong_api = out / 'wrong-resource-cleanup.vapi'
	wrong_api.write_text(resource_api.read_text().replace('destroy_function = "of_release"', 'destroy_function = "of_release_other"'))
	for name, source, api, diagnostic in [
		('wrong-resource-cleanup', 'int main(){var value=ResourceTransport.create(42);return 0;}', wrong_api,
		'exact type/ownership/native ABI signature mismatch'),
		('wrong-resource-type', 'int main(){var value=make_other(42);return ResourceTransport.inspect(value);}', resource_api,
		"expects type 'R', provided 'Other'"),
		('borrowed-resource-transfer', 'int retire(borrowed R value){return ResourceTransport.consume(move value);}int main(){return 0;}', resource_api,
		'must be an owned nominal handle local or parameter'),
	]:
		path = out / (name + '.astra')
		path.write_text(source)
		for phase in ['--check', '--dump-nabi', '--dump-llvm']:
			run([compiler, phase, '--vapi', api, '--import-module', resource_base / 'resource-middle.asti', path],
				expected=1, diagnostic=diagnostic, stdout=None)

			# Copied native code values carry typed ownership channels across the graph.
			# Both provider code and consumer code run through opaque imported invokers.
	callback_leaves = {}
	for level in [0, 1, 2]:
		directory = out / ('callback-leaf-' + str(level))
		provider(directory, 'callable-provider', 'NativeCallbacks',
			['NativeCallbacks.Input<int,bool>', 'NativeCallbacks.callback', 'NativeCallbacks.invoke', 'NativeCallbacks.field_callback'], level, vapis=[resource_api])
		callback_leaves[level] = directory
	callback_middles = {}
	for leaf_level, middle_level in [*itertools.product([0, 2], repeat=2), (1, 1)]:
		directory = out / f'callback-l{leaf_level}-m{middle_level}'
		directory.mkdir()
		stage(callback_leaves[leaf_level], directory)
		provider(directory, 'callable-middle', 'CallbackTransport',
			['CallbackTransport.callback', 'CallbackTransport.apply', 'CallbackTransport.direct', 'CallbackTransport.field_callback'], middle_level,
			imports=['callable-provider.asti'], vapis=[resource_api])
		callback_middles[leaf_level, middle_level] = directory
	callback_consumer = out / 'callback-consumer.astra'
	callback_consumer.write_bytes((HERE / 'unit-callable-client.astra').read_bytes())
	for leaf_level, middle_level, client_level in [*itertools.product([0, 2], repeat=3), (1, 1, 1)]:
		directory = callback_middles[leaf_level, middle_level]
		executable = directory / ('client-O' + str(client_level))
		run([compiler, '-O' + str(client_level), '--vapi', resource_api, '--import-module', directory / 'callable-middle.asti',
			callback_consumer, '--link-object', resource_object, '-o', executable])
		trace = b'+236\n+237\n-237\n+238\n-238\n+239\n-239\n-236\n'
		run([executable], stdout=trace)
		run(['valgrind', '--default-suppressions=no', '--leak-check=full', '--show-leak-kinds=all',
			'--errors-for-leak-kinds=all', '--error-exitcode=99', executable], memory=True, stdout=trace)
		product(executable)


		# Consuming Class inputs retain exact nominal heap cleanup across opaque
		# libraries, including consumer implementations called back inside the leaf.
	class_leaves = {}
	for level in [0, 1, 2]:
		directory = out / ('class-callback-leaf-' + str(level))
		provider(directory, 'class-callable-provider', 'NativeClassCallbacks',
			['NativeClassCallbacks.Cargo<int,bool>', 'NativeClassCallbacks.callback', 'NativeClassCallbacks.invoke'], level, vapis=[resource_api])
		class_leaves[level] = directory
	class_middles = {}
	for leaf_level, middle_level in [*itertools.product([0, 2], repeat=2), (1, 1)]:
		directory = out / f'class-callback-l{leaf_level}-m{middle_level}'
		directory.mkdir()
		stage(class_leaves[leaf_level], directory)
		provider(directory, 'class-callable-middle', 'ClassCallbackTransport',
			['ClassCallbackTransport.callback', 'ClassCallbackTransport.apply', 'ClassCallbackTransport.direct'], middle_level,
			imports=['class-callable-provider.asti'], vapis=[resource_api])
		class_middles[leaf_level, middle_level] = directory
	class_consumer = out / 'class-callback-consumer.astra'
	class_consumer.write_bytes((HERE / 'unit-class-callable-client.astra').read_bytes())
	for leaf_level, middle_level, client_level in [*itertools.product([0, 2], repeat=3), (1, 1, 1)]:
		directory = class_middles[leaf_level, middle_level]
		executable = directory / ('client-O' + str(client_level))
		run([compiler, '-O' + str(client_level), '--vapi', resource_api, '--import-module', directory / 'class-callable-middle.asti',
			class_consumer, '--link-object', resource_object, '-o', executable])
		trace = b'+241\nD730\n-241\n+242\nD730\n-242\n+243\nD730\n-243\n'
		run([executable], stdout=trace)
		run(['valgrind', '--default-suppressions=no', '--leak-check=full', '--show-leak-kinds=all',
			'--errors-for-leak-kinds=all', '--error-exitcode=99', executable], memory=True, stdout=trace)
		product(executable)


		# Whole owning records transport nested Class/Resource/buffer responsibility
		# through code values. Scalar owner/borrow inputs follow expanded pairs.
	record_callback_leaves = {}
	for level in [0, 1, 2]:
		directory = out / ('record-callback-leaf-' + str(level))
		provider(directory, 'record-callable-provider', 'NativeRecordCallbacks',
			['NativeRecordCallbacks.Child', 'NativeRecordCallbacks.Contents', 'NativeRecordCallbacks.Packet',
			'NativeRecordCallbacks.packet', 'NativeRecordCallbacks.callback', 'NativeRecordCallbacks.invoke'], level, vapis=[resource_api])
		record_callback_leaves[level] = directory
	record_callback_middles = {}
	for leaf_level, middle_level in [*itertools.product([0, 2], repeat=2), (1, 1)]:
		directory = out / f'record-callback-l{leaf_level}-m{middle_level}'
		directory.mkdir()
		stage(record_callback_leaves[leaf_level], directory)
		provider(directory, 'record-callable-middle', 'RecordCallbackTransport',
			['RecordCallbackTransport.packet', 'RecordCallbackTransport.callback', 'RecordCallbackTransport.apply', 'RecordCallbackTransport.direct'], middle_level,
			imports=['record-callable-provider.asti'], vapis=[resource_api])
		record_callback_middles[leaf_level, middle_level] = directory
	record_callback_consumer = out / 'record-callback-consumer.astra'
	record_callback_consumer.write_bytes((HERE / 'unit-record-callable-client.astra').read_bytes())
	for leaf_level, middle_level, client_level in [*itertools.product([0, 2], repeat=3), (1, 1, 1)]:
		directory = record_callback_middles[leaf_level, middle_level]
		executable = directory / ('client-O' + str(client_level))
		run([compiler, '-O' + str(client_level), '--vapi', resource_api, '--import-module', directory / 'record-callable-middle.asti',
			record_callback_consumer, '--link-object', resource_object, '-o', executable])
		trace = b'+227\n+221\n+222\n+228\n-228\n-222\n-221\nD221\n+223\n+224\n+229\n-229\n-224\n-223\nD223\n+225\n+226\n+230\n-230\n-226\n-225\nD225\n-227\n'
		run([executable], stdout=trace)
		run(['valgrind', '--default-suppressions=no', '--leak-check=full', '--show-leak-kinds=all',
			'--errors-for-leak-kinds=all', '--error-exitcode=99', executable], memory=True, stdout=trace)
		product(executable)

		# Resource factory results preserve their ownership channel through opaque
		# producer and dependent libraries, including a consumer-defined factory.
	result_leaves = {}
	for level in [0, 1, 2]:
		directory = out / ('resource-result-leaf-' + str(level))
		provider(directory, 'resource-result-provider', 'NativeResourceResults',
			['NativeResourceResults.callback', 'NativeResourceResults.invoke'], level, vapis=[resource_api])
		result_leaves[level] = directory
	result_middles = {}
	for leaf_level, middle_level in [*itertools.product([0, 2], repeat=2), (1, 1)]:
		directory = out / f'resource-result-l{leaf_level}-m{middle_level}'
		directory.mkdir()
		stage(result_leaves[leaf_level], directory)
		provider(directory, 'resource-result-middle', 'ResourceResultTransport',
			['ResourceResultTransport.callback', 'ResourceResultTransport.apply', 'ResourceResultTransport.direct'], middle_level,
			imports=['resource-result-provider.asti'], vapis=[resource_api])
		result_middles[leaf_level, middle_level] = directory
	result_consumer = out / 'resource-result-consumer.astra'
	result_consumer.write_bytes((HERE / 'unit-resource-result-client.astra').read_bytes())
	for leaf_level, middle_level, client_level in [*itertools.product([0, 2], repeat=3), (1, 1, 1)]:
		directory = result_middles[leaf_level, middle_level]
		executable = directory / ('client-O' + str(client_level))
		run([compiler, '-O' + str(client_level), '--vapi', resource_api, '--import-module', directory / 'resource-result-middle.asti',
			result_consumer, '--link-object', resource_object, '-o', executable])
		trace = b'+201\n+202\n+203\n+204\n-204\n-203\n-202\n-201\n'
		run([executable], stdout=trace)
		run(['valgrind', '--default-suppressions=no', '--leak-check=full', '--show-leak-kinds=all',
			'--errors-for-leak-kinds=all', '--error-exitcode=99', executable], memory=True, stdout=trace)
		product(executable)

		# No exported direct Resource result can mask a lost destructor fingerprint
		# on the factory's nested owned result channel.
	result_factory_dir = out / 'resource-result-factory-only'
	result_factory_interface = provider(result_factory_dir, 'resource-result-provider', 'NativeResourceResults',
		['NativeResourceResults.callback'], 0, vapis=[resource_api])
	result_code_only = out / 'resource-result-code-only.astra'
	result_code_only.write_text('int main(){Fn<owned R,int> code=NativeResourceResults.callback();return 0;}')
	for phase in ['--check', '--dump-nabi', '--dump-llvm']:
		run([compiler, phase, '--vapi', wrong_api, '--import-module', result_factory_interface, result_code_only], expected=1,
			diagnostic='exact type/ownership/native ABI signature mismatch', stdout=None)

		# Returned Class owners retain the closed field graph and heap allocation
		# contract through producer, dependent and reverse consumer factories.
	class_result_leaves = {}
	for level in [0, 1, 2]:
		directory = out / ('class-result-leaf-' + str(level))
		provider(directory, 'class-result-provider', 'NativeClassResults',
			['NativeClassResults.Seed<int,bool>', 'NativeClassResults.Cargo<NativeClassResults.Seed<int,bool>,int>',
			'NativeClassResults.callback', 'NativeClassResults.invoke'], level, vapis=[resource_api])
		class_result_leaves[level] = directory
	class_result_middles = {}
	for leaf_level, middle_level in [*itertools.product([0, 2], repeat=2), (1, 1)]:
		directory = out / f'class-result-l{leaf_level}-m{middle_level}'
		directory.mkdir()
		stage(class_result_leaves[leaf_level], directory)
		provider(directory, 'class-result-middle', 'ClassResultTransport',
			['ClassResultTransport.callback', 'ClassResultTransport.apply', 'ClassResultTransport.direct'], middle_level,
			imports=['class-result-provider.asti'], vapis=[resource_api])
		class_result_middles[leaf_level, middle_level] = directory
	class_result_consumer = out / 'class-result-consumer.astra'
	class_result_consumer.write_bytes((HERE / 'unit-class-result-client.astra').read_bytes())
	for leaf_level, middle_level, client_level in [*itertools.product([0, 2], repeat=3), (1, 1, 1)]:
		directory = class_result_middles[leaf_level, middle_level]
		executable = directory / ('client-O' + str(client_level))
		run([compiler, '-O' + str(client_level), '--vapi', resource_api, '--import-module', directory / 'class-result-middle.asti',
			class_result_consumer, '--link-object', resource_object, '-o', executable])
		trace = b'+211\n+212\n+213\n+214\nD870\n-214\nD870\n-213\nD870\n-212\nD870\n-211\n'
		run([executable], stdout=trace)
		run(['valgrind', '--default-suppressions=no', '--leak-check=full', '--show-leak-kinds=all',
			'--errors-for-leak-kinds=all', '--error-exitcode=99', executable], memory=True, stdout=trace)
		product(executable)


		# Record results use the same complete native carrier in producer, middle,
		# consumer and reverse callbacks; the producer source is removed by provider().
	record_result_leaves = {}
	for level in [0, 1, 2]:
		directory = out / ('record-result-leaf-' + str(level))
		provider(directory, 'record-result-provider', 'NativeRecordResults',
			['NativeRecordResults.Leaf', 'NativeRecordResults.Copy<NativeRecordResults.Leaf,int>',
			'NativeRecordResults.Child', 'NativeRecordResults.Contents', 'NativeRecordResults.Packet',
			'NativeRecordResults.copy_callback', 'NativeRecordResults.invoke_copy',
			'NativeRecordResults.create_packet', 'NativeRecordResults.packet_callback', 'NativeRecordResults.invoke_packet'], level, vapis=[resource_api])
		record_result_leaves[level] = directory
	record_result_middles = {}
	for leaf_level, middle_level in [*itertools.product([0, 2], repeat=2), (1, 1)]:
		directory = out / f'record-result-l{leaf_level}-m{middle_level}'
		directory.mkdir()
		stage(record_result_leaves[leaf_level], directory)
		provider(directory, 'record-result-middle', 'RecordResultTransport',
			['RecordResultTransport.copy_callback', 'RecordResultTransport.copy', 'RecordResultTransport.packet_callback',
			'RecordResultTransport.packet', 'RecordResultTransport.direct'], middle_level,
			imports=['record-result-provider.asti'], vapis=[resource_api])
		record_result_middles[leaf_level, middle_level] = directory
	record_result_consumer = out / 'record-result-consumer.astra'
	record_result_consumer.write_bytes((HERE / 'unit-record-result-client.astra').read_bytes())
	for leaf_level, middle_level, client_level in [*itertools.product([0, 2], repeat=3), (1, 1, 1)]:
		directory = record_result_middles[leaf_level, middle_level]
		executable = directory / ('client-O' + str(client_level))
		run([compiler, '-O' + str(client_level), '--vapi', resource_api, '--import-module', directory / 'record-result-middle.asti',
			record_result_consumer, '--link-object', resource_object, '-o', executable])
		trace = b'+181\n+182\n+183\n+184\n-184\nD184\n-183\nD183\n-182\nD182\n-181\nD181\n'
		run([executable], stdout=trace)
		run(['valgrind', '--default-suppressions=no', '--leak-check=full', '--show-leak-kinds=all',
			'--errors-for-leak-kinds=all', '--error-exitcode=99', executable], memory=True, stdout=trace)
		product(executable)
	record_factory_dir = out / 'record-result-factory-only'
	record_factory_interface = provider(record_factory_dir, 'record-result-provider', 'NativeRecordResults',
		['NativeRecordResults.Child', 'NativeRecordResults.Contents', 'NativeRecordResults.Packet', 'NativeRecordResults.packet_callback'], 0, vapis=[resource_api])
	record_code_only = out / 'record-result-code-only.astra'
	record_code_only.write_text('int main(){Fn<NativeRecordResults.Packet,int> code=NativeRecordResults.packet_callback();return 0;}')
	for phase in ['--check', '--dump-nabi', '--dump-llvm']:
		run([compiler, phase, '--vapi', wrong_api, '--import-module', record_factory_interface, record_code_only], expected=1,
			diagnostic='exact type/ownership/native ABI signature mismatch', stdout=None)


		# Borrowed record code channels retain the complete native record identity
		# and do not transfer cleanup, including reverse callbacks through the middle.
	record_loan_leaves = {}
	for level in [0, 1, 2]:
		directory = out / ('record-loan-leaf-' + str(level))
		provider(directory, 'record-loan-provider', 'NativeRecordLoans',
			['NativeRecordLoans.Child', 'NativeRecordLoans.Contents', 'NativeRecordLoans.Packet',
			'NativeRecordLoans.packet', 'NativeRecordLoans.callback', 'NativeRecordLoans.invoke'], level, vapis=[resource_api])
		record_loan_leaves[level] = directory
	record_loan_middles = {}
	for leaf_level, middle_level in [*itertools.product([0, 2], repeat=2), (1, 1)]:
		directory = out / f'record-loan-l{leaf_level}-m{middle_level}'
		directory.mkdir()
		stage(record_loan_leaves[leaf_level], directory)
		provider(directory, 'record-loan-middle', 'RecordLoanTransport',
			['RecordLoanTransport.callback', 'RecordLoanTransport.apply'], middle_level,
			imports=['record-loan-provider.asti'], vapis=[resource_api])
		record_loan_middles[leaf_level, middle_level] = directory
	record_loan_consumer = out / 'record-loan-consumer.astra'
	record_loan_consumer.write_bytes((HERE / 'unit-record-loan-client.astra').read_bytes())
	for leaf_level, middle_level, client_level in [*itertools.product([0, 2], repeat=3), (1, 1, 1)]:
		directory = record_loan_middles[leaf_level, middle_level]
		executable = directory / ('client-O' + str(client_level))
		run([compiler, '-O' + str(client_level), '--vapi', resource_api, '--import-module', directory / 'record-loan-middle.asti',
			record_loan_consumer, '--link-object', resource_object, '-o', executable])
		trace = b'+221\n+222\n+231\n+232\n+223\n-223\n-232\n-231\nD231\n-222\n-221\nD221\n'
		run([executable], stdout=trace)
		run(['valgrind', '--default-suppressions=no', '--leak-check=full', '--show-leak-kinds=all',
			'--errors-for-leak-kinds=all', '--error-exitcode=99', executable], memory=True, stdout=trace)
		product(executable)
	record_loan_factory = out / 'record-loan-factory-only'
	record_loan_interface = provider(record_loan_factory, 'record-loan-provider', 'NativeRecordLoans',
		['NativeRecordLoans.Child', 'NativeRecordLoans.Contents', 'NativeRecordLoans.Packet', 'NativeRecordLoans.callback'], 0, vapis=[resource_api])
	record_loan_code_only = out / 'record-loan-code-only.astra'
	record_loan_code_only.write_text('int main(){Fn<int,borrowed NativeRecordLoans.Packet,borrowed R,int> code=NativeRecordLoans.callback();return 0;}')
	for phase in ['--check', '--dump-nabi', '--dump-llvm']:
		run([compiler, phase, '--vapi', wrong_api, '--import-module', record_loan_interface, record_loan_code_only], expected=1,
			diagnostic='exact type/ownership/native ABI signature mismatch', stdout=None)

		# No public Class callback or constructor transports R directly. A changed
		# destructor must still fail through the exported owning field's layout.
	class_code_only = out / 'class-callback-code-only.astra'
	class_code_only.write_text('int main(){Fn<int,owned NativeClassCallbacks.Cargo<int,bool>,int> code=ClassCallbackTransport.callback();return 0;}')
	for phase in ['--check', '--dump-nabi', '--dump-llvm']:
		run([compiler, phase, '--vapi', wrong_api, '--import-module', class_middles[0, 0] / 'class-callable-middle.asti', class_code_only], expected=1,
			diagnostic='native type layout/visibility mismatch', stdout=None)

		# Isolate the code-result contract: this surface has no direct Resource
		# parameter/result whose destructor fingerprint could mask a missing Fn fact.
	factory_dir = out / 'callback-factory-only'
	factory_interface = provider(factory_dir, 'callable-provider', 'NativeCallbacks',
		['NativeCallbacks.Input<int,bool>', 'NativeCallbacks.field_callback'], 0, vapis=[resource_api])
	code_only = out / 'callback-code-only.astra'
	code_only.write_text('int main(){Fn<int,NativeCallbacks.Input<int,bool>> code=NativeCallbacks.field_callback();return 0;}')
	for phase in ['--check', '--dump-nabi', '--dump-llvm']:
		run([compiler, phase, '--vapi', wrong_api, '--import-module', factory_interface, code_only], expected=1,
			diagnostic='exact type/ownership/native ABI signature mismatch', stdout=None)

		# A record-only unit has no implementation functions. Its exact published
		# nominal application and layout survive pruning as declaration metadata.
	type_consumer = out / 'type-only-consumer.astra'
	type_consumer.write_bytes((HERE / 'unit-type-only-client.astra').read_bytes())
	for level in [0, 1, 2]:
		directory = out / ('type-only-O' + str(level))
		interface = provider(directory, 'type-only-provider', 'NativeRecordOnly',
			['NativeRecordOnly.Pair<i32,bool>', 'NativeRecordOnly.Pair<i64,bool>',
			'NativeRecordOnly.Pair<f64,int>', 'NativeRecordOnly.Pair<NativeRecordOnly.Pair<i64,bool>,bool>'], level)
		groups = metadata(interface.read_text())
		assert not any(group.startswith('function ') for group in groups)
		assert 'type NativeRecordOnly.Pair<int,bool>' in groups
		assert 'type NativeRecordOnly.Pair<i32,bool>' not in groups
		executable = directory / 'client'
		run([compiler, '-O' + str(level), '--import-module', interface, type_consumer, '-o', executable])
		run([executable])
		run(['valgrind', '--default-suppressions=no', '--leak-check=full', '--show-leak-kinds=all',
			'--errors-for-leak-kinds=all', '--error-exitcode=99', executable], memory=True)
		product(executable)

	duplicate_dir = out / 'duplicate-type-selectors'
	duplicate_dir.mkdir()
	duplicate_source = duplicate_dir / 'provider.astra'
	duplicate_source.write_bytes((HERE / 'unit-type-only-provider.astra').read_bytes())
	run([compiler, '-c', '--module', 'NativeRecordOnly', '--native-export', 'NativeRecordOnly.Pair<int,bool>',
		'--native-export', 'NativeRecordOnly.Pair<i32,bool>', '--emit-interface', duplicate_dir / 'provider.asti',
		duplicate_source, '-o', duplicate_dir / 'provider.o'], expected=1,
		diagnostic='duplicate native export selectors resolve to the same nominal type')
	duplicate_source.unlink()

	# Imported record headers describe a closed inventory, including when a
	# concrete application appears only after a local generic helper is demanded.
	closed_interface = out / 'type-only-O0/type-only-provider.asti'
	for name, body in {
		'unexported-record': 'int main(){NativeRecordOnly.Pair<bool,int> value={first=true,second=42};return value.second-42;}',
		'unexported-record-helper': 'int hidden<T>(T item){NativeRecordOnly.Pair<T,int> value={first=item,second=42};return value.second;}int main(){return hidden<bool>(true)-42;}',
	}.items():
		path = out / (name + '.astra')
		path.write_text(body)
		for phase in ['--check', '--dump-nabi', '--dump-llvm']:
			run([compiler, phase, '--import-module', closed_interface, path], expected=1,
				diagnostic='native module: closed record application is not exported', stdout=None)

			# Ordinary Class declarations: two independent parameters, direct scalar and
			# copied-record fields, bookkeeping and real methods, with no slots field.
	declared_consumer = out / 'declared-consumer.astra'
	declared_consumer.write_bytes((HERE / 'unit-declared-client.astra').read_bytes())
	declared_exports = ['DeclaredUnits.Stats', 'DeclaredUnits.PairBox<int,bool>',
		'DeclaredUnits.PairBox<DeclaredUnits.Stats,int>', 'DeclaredUnits.number', 'DeclaredUnits.record',
		'DeclaredUnits.Leaf', 'DeclaredUnits.Carrier', 'DeclaredUnits.OwnerBox<DeclaredUnits.Leaf>',
		'DeclaredUnits.OwnerBox<DeclaredUnits.PairBox<DeclaredUnits.Stats,int>>',
		'DeclaredUnits.OwnerBox<DeclaredUnits.Carrier>', 'DeclaredUnits.native_owner',
		'DeclaredUnits.nested_owner', 'DeclaredUnits.record_owner', 'DeclaredUnits.relay_leaf']
	declared_exports += ['DeclaredUnits.Coupled<DeclaredUnits.Stats,int>',
		'DeclaredUnits.Coupled<DeclaredUnits.Coupled<DeclaredUnits.Stats,int>,bool>',
		'DeclaredUnits.PairBox<DeclaredUnits.Coupled<DeclaredUnits.Stats,int>,bool>',
		'DeclaredUnits.coupled', 'DeclaredUnits.nested_coupled', 'DeclaredUnits.boxed_coupled']
	declared_leaves = {}
	for level in [0, 1, 2]:
		directory = out / ('declared-leaf-' + str(level))
		interface = provider(directory, 'declared-provider', 'DeclaredUnits', declared_exports, level)
		assert 'this.' not in interface.read_text() and 'return ' not in interface.read_text()
		assert 'astra.gen.struct.' not in interface.read_text(), 'private record storage symbol leaked into the public contract'
		groups = metadata(interface.read_text())
		for owner in ['DeclaredUnits.PairBox<int,bool>', 'DeclaredUnits.PairBox<DeclaredUnits.Stats,int>']:
			for member in ['get:value', 'get:alternative', 'get:version', 'set:version']:
				assert 'function C:' + owner + '::' + member in groups
		declared_leaves[level] = directory
	declared_middles = {}
	for leaf_level, middle_level in [*itertools.product([0, 2], repeat=2), (1, 1)]:
		directory = out / f'declared-l{leaf_level}-m{middle_level}'
		directory.mkdir()
		stage(declared_leaves[leaf_level], directory)
		provider(directory, 'declared-middle', 'DeclaredMiddle', ['DeclaredMiddle.' + name for name in
			['advance', 'native_owner', 'nested_owner', 'record_owner', 'relay_leaf', 'relay_coupled', 'relay_nested', 'inspect_boxed']],
			middle_level, ['declared-provider.asti'])
		declared_middles[leaf_level, middle_level] = directory
	for leaf_level, middle_level, client_level in [*itertools.product([0, 2], repeat=3), (1, 1, 1)]:
		directory = declared_middles[leaf_level, middle_level]
		executable = directory / ('declared-client-O' + str(client_level))
		run([compiler, '-O' + str(client_level), '--import-module', directory / 'declared-middle.asti',
			declared_consumer, '-o', executable])
		run([executable])
		run(['valgrind', '--default-suppressions=no', '--leak-check=full', '--show-leak-kinds=all',
			'--errors-for-leak-kinds=all', '--error-exitcode=99', executable], memory=True)
		product(executable)

		# Declarations cannot smuggle executable accessors or rename a property while
		# retaining the object's original callable inventory and external symbols.
	property_base = declared_middles[0, 0]
	for name, before, after, diagnostic in [
		('borrowed-property-escape', 'if (native.view.read()', 'var escaped = native.view; if (native.view.read()', 'borrowed'),
		('borrowed-record-escape', 'if (inspect_carrier(owning_record.view)', 'var escaped = owning_record.view; if (inspect_carrier(owning_record.view)', 'borrowed'),
		('property-wrong-value', 'number.version = 18;', 'number.version = true;', 'type'),
	]:
		invalid = out / (name + '.astra')
		text = declared_consumer.read_text()
		assert before in text
		invalid.write_text(text.replace(before, after, 1))
		for stage_name in ['--check', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-llvm']:
			run([compiler, stage_name, '--import-module', property_base / 'declared-middle.asti', invalid], expected=1, diagnostic=diagnostic)
	readonly_import = out / 'opaque-import-readonly.astra'
	readonly_import.write_text('''class ScopedNativeReader {
	private owned DeclaredUnits.Leaf[slots] values;
	init() { this.values = new DeclaredUnits.Leaf[slots]; }
	int inspect(borrowed DeclaredUnits.Leaf value) { return value.read(); }
	int read() {
		var value = new DeclaredUnits.Leaf(42);
		if (!this.values.reserve(1)) { return 1; }
		this.values.append(move value);
		return this.inspect(this.values[0]);
	}
}
int main() { var reader = new ScopedNativeReader(); return reader.read(); }
''')
	for stage_name in ['--check', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-llvm']:
		run([compiler, stage_name, '--import-module', property_base / 'declared-middle.asti', readonly_import], stdout=None)
		# Approved unchanged readonly import: verify the original exit and lifetime
		# at all public levels with its transitive producer implementations hidden.
	for level in [0, 1, 2]:
		executable = out / ('opaque-import-readonly-O' + str(level))
		run([compiler, '-O' + str(level), '--import-module', property_base / 'declared-middle.asti', readonly_import, '-o', executable])
		run([executable], expected=42)
		run(['valgrind', '--default-suppressions=no', '--leak-check=full', '--show-leak-kinds=all',
			'--errors-for-leak-kinds=all', '--error-exitcode=99', executable], expected=42, memory=True)
		product(executable)
	property_consumer = out / 'property-consumer.astra'
	property_consumer.write_text('int main(){var value=DeclaredUnits.number(40);return value.value-42;}\n')
	for name, before, after, diagnostic in [
		('executable-property', 'property int version { get {}', 'property int version { get { return 0; }', 'native interface cannot contain executable property bodies'),
		('renamed-property', 'property int version', 'property int altered', 'unexpected imported native callable'),
	]:
		directory = out / ('refusal-' + name)
		directory.mkdir()
		stage(declared_leaves[0], directory)
		path = directory / 'declared-provider.asti'
		groups = metadata(path.read_text())
		declarations = groups['abi']['declarations']
		assert before in declarations
		declarations = declarations.replace(before, after, 1)
		groups['abi']['declarations'] = declarations
		groups['abi']['declarations_sha256'] = hashlib.sha256(declarations.replace(r'\n', '\n').encode()).hexdigest()
		path.write_text(reseal(groups))
		run([compiler, '--check', '--import-module', path, property_consumer], expected=1, diagnostic=diagnostic)
	llvm = run([compiler, '--dump-llvm', '--import-module', base / 'middle.asti', consumer], stdout=None)
	assert len(re.findall(rb'^declare fastcc .*@astra_mod_', llvm, re.M)) >= 2
	assert not re.search(rb'^define .*@astra_mod_', llvm, re.M)
	undefined = run(['nm', '-u', base / 'middle.o'], stdout=None)
	leaf_symbol = metadata((base / 'leaf.asti').read_text())['function F:StructuralLeaf.transform']['symbol']
	assert leaf_symbol.encode() in undefined
	run(['llvm-dwarfdump', '--verify', base / 'client-O0'], stdout=None)
	lines = run(['readelf', '--debug-dump=decodedline', base / 'client-O0'], stdout=None)
	assert all(name in lines for name in [b'leaf-implementation.astra', b'middle-implementation.astra', b'consumer.astra'])

	# Relocate only opaque artifacts; neither producer implementation is present.
	relocated = out / 'relocated'
	relocated.mkdir()
	stage(base, relocated)
	trace, entry = relocated / 'opens.log', relocated / 'client-entry.o'
	run(['strace', '-f', '-e', 'trace=openat,openat2', '-o', trace, compiler, '-O2',
		'--entry-object', '--import-module', relocated / 'middle.asti', consumer, '-o', entry])
	opens = trace.read_text()
	assert all(str(relocated / name) in opens for name in ['leaf.asti', 'middle.asti', 'leaf.o', 'middle.o'])
	assert 'implementation.astra' not in opens
	assert all(str(path) not in opens for path in fixtures)
	receipt['artifact_only_trace'] = dict(path=str(trace), sha256=sha(trace))

	# Both branches share the same exact leaf origin and object, linked once.
	diamond = out / 'diamond'
	diamond.mkdir()
	stage(base, diamond)
	shutil.copyfile(diamond / 'leaf.asti', diamond / 'alias-leaf.asti')
	provider(diamond, 'side', 'StructuralSide', 'StructuralSide.offset', 2, ['alias-leaf.asti'])
	provider(diamond, 'top', 'StructuralTop', 'StructuralTop.sum', 0, ['side.asti', 'middle.asti'])
	top_metadata = (diamond / 'top.asti').read_bytes()
	provider(diamond, 'top', 'StructuralTop', 'StructuralTop.sum', 0, ['middle.asti', 'side.asti'])
	assert (diamond / 'top.asti').read_bytes() == top_metadata
	diamond_consumer = out / 'diamond-consumer.astra'
	diamond_consumer.write_bytes((HERE / 'unit-diamond-client.astra').read_bytes())
	for level in [0, 1, 2]:
		executable = diamond / ('diamond-O' + str(level))
		run([compiler, '-O' + str(level), '--import-module', diamond / 'top.asti', diamond_consumer, '-o', executable])
		run([executable])
		run(['valgrind', '--default-suppressions=no', '--leak-check=full', '--show-leak-kinds=all',
			'--errors-for-leak-kinds=all', '--error-exitcode=99', executable], memory=True)
		product(executable)

		# Changing only the leaf algorithm requires fresh pinned dependent metadata.
	changed = out / 'changed-algorithm'
	changed.mkdir()
	source = (HERE / 'unit-leaf.astra').read_bytes().replace(b'* 3', b'* 4')
	provider(changed, 'leaf', 'StructuralLeaf', 'StructuralLeaf.transform', 2, source=source)
	provider(changed, 'middle', 'StructuralMiddle', 'StructuralMiddle.combine', 2, ['leaf.asti'])
	run([compiler, '-O2', '--import-module', changed / 'middle.asti', consumer, '-o', changed / 'client'])
	run([changed / 'client'], expected=13)
	run([base / 'client-O0'])

	# A second real producer with the same nominal module but different object
	# cannot silently replace the leaf imported by the other diamond branch.
	conflict = out / 'conflicting-origin'
	conflict.mkdir()
	stage(base, conflict)
	other_source = conflict / 'other-leaf-implementation.astra'
	other_source.write_bytes(source)
	run([compiler, '-O2', '-c', '--module', 'StructuralLeaf', '--emit-interface', conflict / 'other-leaf.asti',
		'--native-export', 'StructuralLeaf.transform', other_source, '-o', conflict / 'other-leaf.o'])
	other_source.unlink()
	# The side explicitly selects the alternative leaf artifact pair.
	provider(conflict, 'side', 'StructuralSide', 'StructuralSide.offset', 2, ['other-leaf.asti'])
	top_source = conflict / 'top-implementation.astra'
	top_source.write_bytes((HERE / 'unit-top.astra').read_bytes())
	run([compiler, '-c', '--module', 'StructuralTop', '--emit-interface', conflict / 'top.asti',
		'--native-export', 'StructuralTop.sum', '--import-module', conflict / 'middle.asti',
		'--import-module', conflict / 'side.asti', top_source, '-o', conflict / 'top.o'],
		expected=1, diagnostic='conflicting imported nominal module origin')
	assert not (conflict / 'top.o').exists() and not (conflict / 'top.asti').exists()

	def mutant(name, change, diagnostic):
		directory = out / ('refusal-' + name)
		directory.mkdir()
		stage(base, directory)
		change(directory)
		run([compiler, '--check', '--import-module', directory / 'middle.asti', consumer],
			expected=1, diagnostic=diagnostic)

	def edge(directory, key, value):
		path = directory / 'middle.asti'
		groups = metadata(path.read_text())
		groups['dependency StructuralLeaf'][key] = value
		path.write_text(reseal(groups))

	mutant('missing-interface', lambda d: (d / 'leaf.asti').unlink(), 'native module:')
	mutant('missing-object', lambda d: (d / 'leaf.o').unlink(), 'native module:')
	mutant('stale-object', lambda d: shutil.copyfile(changed / 'leaf.o', d / 'leaf.o'), 'object identity mismatch')
	for key in ['interface_sha256', 'object_sha256', 'abi_identity']:
		mutant(key, lambda d, key=key: edge(d, key, '0' * 64), 'dependency module/interface/object/ABI identity mismatch')

	def nominal_mismatch(directory):
		path = directory / 'middle.asti'
		groups = metadata(path.read_text())
		groups['dependency OtherLeaf'] = groups.pop('dependency StructuralLeaf')
		path.write_text(reseal(groups))
	mutant('dependency-name', nominal_mismatch, 'dependency module/interface/object/ABI identity mismatch')

	def incomplete(directory):
		path = directory / 'middle.asti'
		groups = metadata(path.read_text())
		del groups['dependency StructuralLeaf']['object_sha256']
		path.write_text(reseal(groups))
	mutant('missing-dependency-field', incomplete, 'missing/unknown interface field')

	def oversized(directory, name, length):
		with (directory / name).open('wb') as stream:
			stream.truncate(length)
	mutant('interface-size', lambda d: oversized(d, 'leaf.asti', 2 * 1024 * 1024 + 1), 'artifact exceeds finite size limit')
	mutant('object-size', lambda d: oversized(d, 'leaf.o', 128 * 1024 * 1024 + 1), 'artifact exceeds finite size limit')
	for name, filename in [('parent-path', '../leaf.asti'), ('absolute-path', str(base / 'leaf.asti')),
		('backslash-path', r'bad\\leaf.asti')]:
		mutant(name, lambda d, filename=filename: edge(d, 'interface', filename), 'safe adjacent interface basename')

	def symlink(directory, name):
		(directory / name).unlink()
		(directory / name).symlink_to(base / name)
	mutant('interface-symlink', lambda d: symlink(d, 'leaf.asti'), 'interface symlinks are not admitted')
	mutant('object-symlink', lambda d: symlink(d, 'leaf.o'), 'object identity mismatch')

	def cycle(directory, alias=False):
		path = directory / 'middle.asti'
		groups = metadata(path.read_text())
		dependency = groups.pop('dependency StructuralLeaf')
		dependency['interface'] = 'alias.asti' if alias else 'middle.asti'
		groups['dependency StructuralMiddle'] = dependency
		path.write_text(reseal(groups))
		if alias:
			shutil.copyfile(path, directory / 'alias.asti')
	mutant('cycle', cycle, 'dependency cycle at interface path')
	mutant('alias-cycle', lambda d: cycle(d, True), 'dependency cycle at nominal module')

	def deep(directory):
		next_path = None
		for index in reversed(range(66)):
			groups = metadata((base / 'leaf.asti').read_text())
			groups['abi']['module'] = 'Depth' + str(index)
			function = groups.pop('function F:StructuralLeaf.transform')
			groups['function F:Depth' + str(index) + '.transform'] = function
			if next_path:
				groups['dependency Depth' + str(index + 1)] = dict(interface=next_path.name,
					interface_sha256=sha(next_path), object_sha256=sha(base / 'leaf.o'), abi_identity='0' * 64)
			path = directory / ('depth' + str(index) + '.asti')
			path.write_text(reseal(groups))
			next_path = path
		edge(directory, 'interface', 'depth0.asti')
	mutant('depth', deep, 'dependency depth exceeds 64 edges')

	def old_format(directory):
		path = directory / 'middle.asti'
		path.write_text(path.read_text().replace('astra-native-module/2', 'astra-native-module/1'))
	mutant('old-format', old_format, 'rebuild all native units')

	def executable_body(directory):
		path = directory / 'middle.asti'
		groups = metadata(path.read_text())
		declarations = groups['abi']['declarations']
		assert ' {}' in declarations
		declarations = declarations.replace(' {}', ' { return 0; }', 1)
		groups['abi']['declarations'] = declarations
		groups['abi']['declarations_sha256'] = hashlib.sha256(declarations.replace(r'\n', '\n').encode()).hexdigest()
		path.write_text(reseal(groups))
	mutant('executable-body', executable_body, 'native interface cannot contain executable implementation bodies')
	run([compiler, '--check', '--import-module', base / 'middle.asti',
		'--import-module', base / 'middle.asti', consumer], expected=1, diagnostic='duplicate imported module identity')

	# Symbolic callback substitutions consume only imported declarations. Both
	# directions cross leaf -> middle -> client with producer source removed.
	symbolic_leaves = {}
	for level in [0, 1, 2]:
		directory = out / ('symbolic-callable-leaf-' + str(level))
		provider(directory, 'symbolic-callable-provider', 'SymbolicNative',
			['SymbolicNative.Packet', 'SymbolicNative.Child', 'SymbolicNative.callback',
			'SymbolicNative.invoke', 'SymbolicNative.create_child', 'SymbolicNative.loan_callback',
			'SymbolicNative.invoke_loan'], level, vapis=[resource_api])
		symbolic_leaves[level] = directory
	symbolic_middles = {}
	for leaf_level, middle_level in [*itertools.product([0, 2], repeat=2), (1, 1)]:
		directory = out / f'symbolic-callable-l{leaf_level}-m{middle_level}'
		directory.mkdir()
		stage(symbolic_leaves[leaf_level], directory)
		provider(directory, 'symbolic-callable-middle', 'SymbolicTransport',
			['SymbolicTransport.callback', 'SymbolicTransport.invoke', 'SymbolicTransport.create_child',
			'SymbolicTransport.loan_callback', 'SymbolicTransport.invoke_loan'], middle_level,
			imports=['symbolic-callable-provider.asti'], vapis=[resource_api])
		symbolic_middles[leaf_level, middle_level] = directory
	symbolic_consumer = out / 'symbolic-callable-client.astra'
	symbolic_consumer.write_bytes((HERE / 'unit-symbolic-callable-client.astra').read_bytes())
	for leaf_level, middle_level, client_level in [*itertools.product([0, 2], repeat=3), (1, 1, 1)]:
		directory = symbolic_middles[leaf_level, middle_level]
		executable = directory / ('client-O' + str(client_level))
		run([compiler, '-O' + str(client_level), '--vapi', resource_api,
			'--import-module', directory / 'symbolic-callable-middle.asti', symbolic_consumer,
			'--link-object', resource_object, '-o', executable])
		trace = b'D973\n'
		run([executable], stdout=trace)
		run(['valgrind', '--default-suppressions=no', '--leak-check=full', '--show-leak-kinds=all',
			'--errors-for-leak-kinds=all', '--error-exitcode=99', executable], memory=True, stdout=trace)
		product(executable)

		# Generic consuming callbacks preserve imported Class/Resource ownership
		# through the same opaque leaf/middle/consumer graph in both directions.
	consuming_leaves = {}
	for level in [0, 1, 2]:
		directory = out / ('symbolic-consuming-leaf-' + str(level))
		provider(directory, 'symbolic-consuming-provider', 'NativeGenericConsume',
			['NativeGenericConsume.Cargo<int,bool>', 'NativeGenericConsume.create',
			'NativeGenericConsume.callback', 'NativeGenericConsume.resource_callback',
			'NativeGenericConsume.invoke', 'NativeGenericConsume.invoke_resource'], level, vapis=[resource_api])
		consuming_leaves[level] = directory
	consuming_middles = {}
	for leaf_level, middle_level in [*itertools.product([0, 2], repeat=2), (1, 1)]:
		directory = out / f'symbolic-consuming-l{leaf_level}-m{middle_level}'
		directory.mkdir()
		stage(consuming_leaves[leaf_level], directory)
		provider(directory, 'symbolic-consuming-middle', 'GenericConsumeTransport',
			['GenericConsumeTransport.create', 'GenericConsumeTransport.callback',
			'GenericConsumeTransport.resource_callback', 'GenericConsumeTransport.invoke',
			'GenericConsumeTransport.invoke_resource', 'GenericConsumeTransport.producer_invoke'], middle_level,
			imports=['symbolic-consuming-provider.asti'], vapis=[resource_api])
		consuming_middles[leaf_level, middle_level] = directory
	consuming_consumer = out / 'symbolic-consuming-client.astra'
	consuming_consumer.write_bytes((HERE / 'unit-symbolic-consuming-client.astra').read_bytes())
	for leaf_level, middle_level, client_level in [*itertools.product([0, 2], repeat=3), (1, 1, 1)]:
		directory = consuming_middles[leaf_level, middle_level]
		executable = directory / ('client-O' + str(client_level))
		run([compiler, '-O' + str(client_level), '--vapi', resource_api,
			'--import-module', directory / 'symbolic-consuming-middle.asti', consuming_consumer,
			'--link-object', resource_object, '-o', executable])
		trace = b'+181\nD975\n-181\n+182\nD975\n-182\n+183\nD975\n-183\n+184\n-184\n+185\n-185\n'
		run([executable], stdout=trace)
		run(['valgrind', '--default-suppressions=no', '--leak-check=full', '--show-leak-kinds=all',
			'--errors-for-leak-kinds=all', '--error-exitcode=99', executable], memory=True, stdout=trace)
		product(executable)

		# Symbolic owned-result forwarding crosses opaque objects in both directions.
		# The middle library specializes from imported declarations; its Class factory
		# field also carries the leaf's exact owned result and destruction signature.
	result_leaves = {}
	for level in [0, 1, 2]:
		directory = out / ('symbolic-result-leaf-' + str(level))
		provider(directory, 'symbolic-result-provider', 'NativeGenericFactory',
			['NativeGenericFactory.Ticket<int,bool>', 'NativeGenericFactory.ticket_factory',
			'NativeGenericFactory.resource_factory', 'NativeGenericFactory.other_factory'],
			level, vapis=[resource_api])
		result_leaves[level] = directory
	result_middles = {}
	for leaf_level, middle_level in [*itertools.product([0, 2], repeat=2), (1, 1)]:
		directory = out / f'symbolic-result-l{leaf_level}-m{middle_level}'
		directory.mkdir()
		stage(result_leaves[leaf_level], directory)
		provider(directory, 'symbolic-result-middle', 'GenericFactoryTransport',
			['GenericFactoryTransport.resource_factory', 'GenericFactoryTransport.resource',
			'GenericFactoryTransport.other', 'GenericFactoryTransport.ticket',
			'GenericFactoryTransport.direct_ticket', 'GenericFactoryTransport.inferred_ticket'], middle_level,
			imports=['symbolic-result-provider.asti'], vapis=[resource_api])
		result_middles[leaf_level, middle_level] = directory
	result_consumer = out / 'symbolic-result-client.astra'
	result_consumer.write_bytes((HERE / 'unit-symbolic-result-client.astra').read_bytes())
	for leaf_level, middle_level, client_level in [*itertools.product([0, 2], repeat=3), (1, 1, 1)]:
		directory = result_middles[leaf_level, middle_level]
		executable = directory / ('client-O' + str(client_level))
		run([compiler, '-O' + str(client_level), '--vapi', resource_api,
			'--import-module', directory / 'symbolic-result-middle.asti', result_consumer,
			'--link-object', resource_object, '-o', executable])
		trace = b'+221\n+222\n+223\n+224\n+225\n+226\nD1201\n-226\nD1201\n-225\nD1201\n-224\n-223\n-222\n-221\n'
		run([executable], stdout=trace)
		run(['valgrind', '--default-suppressions=no', '--leak-check=full', '--show-leak-kinds=all',
			'--errors-for-leak-kinds=all', '--error-exitcode=99', executable], memory=True, stdout=trace)
		product(executable)

		# Constructed-Class owned formals specialize in an opaque dependent library.
		# Its public entry retains the established independently allocated Class ABI;
		# the internal generic helper derives storage from that exact incoming owner.
	formal_middles = {}
	for leaf_level, middle_level in [*itertools.product([0, 2], repeat=2), (1, 1)]:
		directory = out / f'owned-formal-l{leaf_level}-m{middle_level}'
		directory.mkdir()
		stage(result_leaves[leaf_level], directory)
		provider(directory, 'owned-formal-middle', 'GenericInputTransport',
			'GenericInputTransport.consume', middle_level,
			imports=['symbolic-result-provider.asti'], vapis=[resource_api])
		formal_middles[leaf_level, middle_level] = directory
	formal_consumer = out / 'owned-formal-client.astra'
	formal_consumer.write_bytes((HERE / 'unit-owned-formal-client.astra').read_bytes())
	for leaf_level, middle_level, client_level in [*itertools.product([0, 2], repeat=3), (1, 1, 1)]:
		directory = formal_middles[leaf_level, middle_level]
		executable = directory / ('client-O' + str(client_level))
		run([compiler, '-O' + str(client_level), '--vapi', resource_api,
			'--import-module', directory / 'owned-formal-middle.asti', formal_consumer,
			'--link-object', resource_object, '-o', executable])
		trace = b'+211\nD1201\n-211\n'
		run([executable], stdout=trace)
		run(['valgrind', '--default-suppressions=no', '--leak-check=full', '--show-leak-kinds=all',
			'--errors-for-leak-kinds=all', '--error-exitcode=99', executable], memory=True, stdout=trace)
		product(executable)

		# Independent method tuples are producer-compiled selections. No algorithm
		# or unselected specialization becomes an executable consumer declaration.
	method_exports = ['NativeMethods.' + name for name in [
		'Answer<int,bool>', 'Answer<int,i64>', 'Marker', 'Counter<int>',
		'Counter<int>::project<NativeMethods.Answer<int,bool>>',
		'Counter<int>::merge<i64,NativeMethods.Answer<int,i64>>',
		'Counter<int>::constant<NativeMethods.Marker>']]
	method_leaves = {}
	for level in [0, 1, 2]:
		directory = out / ('method-leaf-' + str(level))
		provider(directory, 'method-provider', 'NativeMethods', method_exports, level)
		groups = metadata((directory / 'method-provider.asti').read_text())
		assert 'function C:NativeMethods.Counter<int>::constant<NativeMethods.Marker>' in groups
		assert 'function C:NativeMethods.Counter<int>::project<int>' not in groups
		method_leaves[level] = directory
	method_middles = {}
	for leaf_level, middle_level in [*itertools.product([0, 2], repeat=2), (1, 1)]:
		directory = out / f'method-l{leaf_level}-m{middle_level}'
		directory.mkdir()
		stage(method_leaves[leaf_level], directory)
		provider(directory, 'method-middle', 'MethodMiddle',
			['MethodMiddle.' + name for name in ['create', 'inspect', 'combine', 'marker']],
			middle_level, ['method-provider.asti'])
		method_middles[leaf_level, middle_level] = directory
	method_consumer = out / 'method-client.astra'
	method_consumer.write_bytes((HERE / 'unit-method-client.astra').read_bytes())
	for leaf_level, middle_level, client_level in [*itertools.product([0, 2], repeat=3), (1, 1, 1)]:
		directory = method_middles[leaf_level, middle_level]
		executable = directory / ('method-client-O' + str(client_level))
		run([compiler, '-O' + str(client_level), '--import-module', directory / 'method-middle.asti',
			method_consumer, '-o', executable])
		run([executable])
		run(['valgrind', '--default-suppressions=no', '--leak-check=full', '--show-leak-kinds=all',
			'--errors-for-leak-kinds=all', '--error-exitcode=99', executable], memory=True)
		product(executable)
	method_refusal = out / 'method-unexported.astra'
	method_refusal.write_text('int identity(int value){return value;} '
		'int main(){var value=MethodMiddle.create(42);return value.project<int>(identity);}\n')
	run([compiler, '--import-module', method_middles[0, 0] / 'method-middle.asti', method_refusal,
		'-o', out / 'method-unexported'], expected=1, diagnostic='unexpected imported native callable')
	assert not (out / 'method-unexported').exists()
	method_refusal.write_text('int main(){var value=MethodMiddle.create(42);return value.constant<int>();}\n')
	run([compiler, '--import-module', method_middles[0, 0] / 'method-middle.asti', method_refusal,
		'-o', out / 'method-wrong-constraint'], expected=1,
		diagnostic='type arguments do not satisfy the declared capability constraint')
	assert not (out / 'method-wrong-constraint').exists()
	duplicate_method = out / 'method-duplicate.astra'
	duplicate_method.write_bytes((HERE / 'unit-method-provider.astra').read_bytes())
	run([compiler, '-c', '--module', 'NativeMethods',
		'--native-export', 'NativeMethods.Counter<int>::project<int>',
		'--native-export', 'NativeMethods.Counter<int>::project<i32>',
		'--emit-interface', out / 'method-duplicate.asti', duplicate_method,
		'-o', out / 'method-duplicate.o'], expected=1,
		diagnostic='duplicate native method selectors resolve to the same closed member')
	assert not (out / 'method-duplicate.asti').exists() and not (out / 'method-duplicate.o').exists()

	# One producer-owned exception root and descriptor graph crosses the same
	# checked result channels in both directions; later subclasses retain their
	# own virtual implementations and retire through their actual descriptors.
	checked_exports = ['CheckedLibrary.' + name for name in
		['Error', 'Failure', 'Reply<int>', 'analyze', 'message_length']]
	checked_leaves = {}
	for level in [0, 1, 2]:
		directory = out / ('checked-leaf-' + str(level))
		provider(directory, 'checked-provider', 'CheckedLibrary', checked_exports, level)
		groups = metadata((directory / 'checked-provider.asti').read_text())
		assert groups['type CheckedLibrary.Error']['symbol'].startswith('astra_mod_')
		assert groups['type CheckedLibrary.Failure']['symbol'].startswith('astra_mod_')
		assert groups['type CheckedLibrary.Reply<int>']['symbol'] == ''
		assert 'checked-bound=CheckedLibrary.Error;checked-root=CheckedLibrary.Error;' in groups[
			'function F:CheckedLibrary.analyze']['signature']
		checked_leaves[level] = directory
	checked_middles = {}
	for leaf_level, middle_level in [*itertools.product([0, 2], repeat=2), (1, 1)]:
		directory = out / f'checked-l{leaf_level}-m{middle_level}'
		directory.mkdir()
		stage(checked_leaves[leaf_level], directory)
		provider(directory, 'checked-middle', 'CheckedMiddle',
			['CheckedMiddle.analyze', 'CheckedMiddle.message_length'], middle_level,
			['checked-provider.asti'])
		checked_middles[leaf_level, middle_level] = directory
	checked_consumer = out / 'checked-client.astra'
	checked_consumer.write_bytes((HERE / 'unit-checked-client.astra').read_bytes())
	for leaf_level, middle_level, client_level in [*itertools.product([0, 2], repeat=3), (1, 1, 1)]:
		directory = checked_middles[leaf_level, middle_level]
		executable = directory / ('checked-client-O' + str(client_level))
		run([compiler, '-O' + str(client_level), '--import-module', directory / 'checked-middle.asti',
			checked_consumer, '-o', executable])
		run([executable])
		run(['valgrind', '--default-suppressions=no', '--leak-check=full', '--show-leak-kinds=all',
			'--errors-for-leak-kinds=all', '--error-exitcode=99', executable], memory=True)
		product(executable)
	checked_refusal = out / 'checked-forged-client.astra'
	checked_refusal.write_text('int main(){try{var value=CheckedLibrary.analyze(40,false);'
		'return value.value-42;}catch(CheckedLibrary.Error error){return 1;}}\n')
	for kind in ['descriptor', 'bound']:
		directory = out / ('checked-forged-' + kind)
		directory.mkdir()
		stage(checked_leaves[0], directory)
		interface = directory / 'checked-provider.asti'
		groups = metadata(interface.read_text())
		if kind == 'descriptor':
			groups['type CheckedLibrary.Error']['symbol'] += '_forged'
			diagnostic = 'exported descriptor fingerprint mismatch'
		else:
			declarations = groups['abi']['declarations'].replace('throws Error', 'throws Failure')
			assert declarations != groups['abi']['declarations']
			groups['abi']['declarations'] = declarations
			groups['abi']['declarations_sha256'] = hashlib.sha256(declarations.replace(r'\n', '\n').encode()).hexdigest()
			diagnostic = 'exact type/ownership/native ABI signature mismatch'
		interface.write_text(reseal(groups))
		run([compiler, '--import-module', interface, checked_refusal, '-o', directory / 'unsafe'],
			expected=1, diagnostic=diagnostic)
		assert not (directory / 'unsafe').exists()

	closure_middles = {}
	closure_exports = ['ClosureLibrary.' + name for name in [
		'Environment<int>', 'Environment<CheckedLibrary.Reply<int>>', 'invoke', 'consume', 'observe']]
	for leaf_level, middle_level in [*itertools.product([0, 2], repeat=2), (1, 1)]:
		directory = out / f'closure-l{leaf_level}-m{middle_level}'
		directory.mkdir()
		stage(checked_leaves[leaf_level], directory)
		provider(directory, 'closure-provider', 'ClosureLibrary', closure_exports, middle_level,
			['checked-provider.asti'], vapis=[resource_api])
		groups = metadata((directory / 'closure-provider.asti').read_text())
		assert 'native-closure<environment=ClosureLibrary.Environment<int>;error=CheckedLibrary.Error;' in groups[
			'function F:ClosureLibrary.invoke']['signature']
		closure_middles[leaf_level, middle_level] = directory
	closure_consumer = out / 'closure-client.astra'
	closure_consumer.write_bytes((HERE / 'unit-closure-client.astra').read_bytes())
	closure_trace = (b'+201\nD1701\nD1701\nD1702\nD1701\n+202\nD1703\nD1700\n-202\n'
		b'+203\nD1703\nD1702\nD1700\n-203\n+204\nD1704\nD1700\n-204\nD1700\n-201\n')
	for leaf_level, middle_level, client_level in [*itertools.product([0, 2], repeat=3), (1, 1, 1)]:
		directory = closure_middles[leaf_level, middle_level]
		executable = directory / ('closure-client-O' + str(client_level))
		run([compiler, '-O' + str(client_level), '--vapi', resource_api,
			'--import-module', directory / 'closure-provider.asti', closure_consumer,
			'--link-object', resource_object, '-o', executable])
		run([executable], stdout=closure_trace)
		run(['valgrind', '--default-suppressions=no', '--leak-check=full', '--show-leak-kinds=all',
			'--errors-for-leak-kinds=all', '--error-exitcode=99', executable], memory=True, stdout=closure_trace)
		product(executable)
	for kind, before, after in [
		('environment', 'CheckedClosure<Environment<int>,', 'CheckedClosure<Environment<CheckedLibrary.Reply<int>>,'),
		('error', ',CheckedLibrary.Error,', ',CheckedLibrary.Failure,'),
		('ownership', 'borrowed CheckedClosure<', 'owned CheckedClosure<')]:
		directory = out / ('closure-forged-' + kind)
		directory.mkdir()
		stage(closure_middles[0, 0], directory)
		interface = directory / 'closure-provider.asti'
		groups = metadata(interface.read_text())
		declarations = groups['abi']['declarations'].replace(before, after, 1)
		assert declarations != groups['abi']['declarations']
		groups['abi']['declarations'] = declarations
		groups['abi']['declarations_sha256'] = hashlib.sha256(declarations.replace(r'\n', '\n').encode()).hexdigest()
		interface.write_text(reseal(groups))
		entry = directory / 'entry.astra'
		entry.write_text('int main(){return 0;}\n')
		run([compiler, '--vapi', resource_api, '--import-module', interface, entry,
			'--link-object', resource_object, '-o', directory / 'unsafe'], expected=1,
			diagnostic='exact type/ownership/native ABI signature mismatch')
		assert not (directory / 'unsafe').exists()
	for kind, before, after, diagnostic in [
		('missing-move', 'ClosureLibrary.consume(move once,', 'ClosureLibrary.consume(once,', 'move'),
		('after-move', 'if (consumed.value != 43 || live() != 1)',
		'var again = ClosureLibrary.invoke(once, input, false); if (consumed.value != 43 || live() != 1)', 'moved')]:
		entry = out / ('closure-' + kind + '.astra')
		text = (HERE / 'unit-closure-client.astra').read_text()
		assert before in text
		entry.write_text(text.replace(before, after, 1))
		binary = out / ('closure-' + kind)
		run([compiler, '--vapi', resource_api, '--import-module',
			closure_middles[0, 0] / 'closure-provider.asti', entry,
			'--link-object', resource_object, '-o', binary], expected=1, diagnostic=diagnostic)
		assert not binary.exists()

		# The abstract operation slots and descriptor identity survive opaque
		# imports; implementations in both later layers remain real virtual targets.
	protocol_leaves = {}
	for level in [0, 1, 2]:
		directory = out / ('protocol-leaf-' + str(level))
		provider(directory, 'interface-provider', 'NativeProtocols',
			['NativeProtocols.Score', 'NativeProtocols.Information<int>', 'NativeProtocols.dispatch'], level)
		groups = metadata((directory / 'interface-provider.asti').read_text())
		assert 'interface=1;' in groups['type NativeProtocols.Score']['layout']
		protocol_leaves[level] = directory
	protocol_middles = {}
	for leaf_level, middle_level in [*itertools.product([0, 2], repeat=2), (1, 1)]:
		directory = out / f'protocol-l{leaf_level}-m{middle_level}'
		directory.mkdir()
		stage(protocol_leaves[leaf_level], directory)
		provider(directory, 'interface-middle', 'ProtocolMiddle',
			['ProtocolMiddle.First', 'ProtocolMiddle.create', 'ProtocolMiddle.evaluate'], middle_level,
			['interface-provider.asti'], vapis=[resource_api])
		protocol_middles[leaf_level, middle_level] = directory
	protocol_consumer = out / 'protocol-client.astra'
	protocol_consumer.write_bytes((HERE / 'unit-interface-client.astra').read_bytes())
	protocol_trace = b'D1802\nD1801\n'
	for leaf_level, middle_level, client_level in [*itertools.product([0, 2], repeat=3), (1, 1, 1)]:
		directory = protocol_middles[leaf_level, middle_level]
		executable = directory / ('protocol-client-O' + str(client_level))
		run([compiler, '-O' + str(client_level), '--vapi', resource_api,
			'--import-module', directory / 'interface-middle.asti', protocol_consumer,
			'--link-object', resource_object, '-o', executable])
		run([executable], stdout=protocol_trace)
		run(['valgrind', '--default-suppressions=no', '--leak-check=full', '--show-leak-kinds=all',
			'--errors-for-leak-kinds=all', '--error-exitcode=99', executable], memory=True, stdout=protocol_trace)
		product(executable)

		# Rehashing the declaration text cannot turn an abstract interface into a
		# concrete Class while retaining the original physical slot layout.
	protocol_forged = out / 'protocol-forged-role'
	protocol_forged.mkdir()
	stage(protocol_leaves[0], protocol_forged)
	interface = protocol_forged / 'interface-provider.asti'
	groups = metadata(interface.read_text())
	before = 'interface Score {\\n\tint apply(int input);\\n}'
	after = 'class Score {\\n\tinit() {}\\n\tvirtual int apply(int input) {}\\n}'
	declarations = groups['abi']['declarations'].replace(before, after)
	assert declarations != groups['abi']['declarations']
	groups['abi']['declarations'] = declarations
	groups['abi']['declarations_sha256'] = hashlib.sha256(declarations.replace(r'\n', '\n').encode()).hexdigest()
	interface.write_text(reseal(groups))
	entry = protocol_forged / 'entry.astra'
	entry.write_text('int main(){return 0;}\n')
	run([compiler, '--import-module', interface, entry, '-o', protocol_forged / 'unsafe'],
		expected=1, diagnostic='native type layout/visibility mismatch')
	assert not (protocol_forged / 'unsafe').exists()
	protocol_mutation = out / 'protocol-mutating-implementation.astra'
	text = (HERE / 'unit-interface-middle.astra').read_text()
	before = 'return this.bias + input;'
	assert text.count(before) == 1
	protocol_mutation.write_text(text.replace(before, 'this.bias = input; return this.bias;', 1))
	run([compiler, '--check', '--vapi', resource_api, '--import-module',
		protocol_leaves[0] / 'interface-provider.asti', protocol_mutation], expected=1,
		diagnostic='interface read-only implementation')

	# Imported bodies never establish readonly promises. The original producer
	# summary composes through copied record getters and another opaque library.
	readonly_leaves = {}
	for level in [0, 1, 2]:
		directory = out / ('readonly-leaf-' + str(level))
		provider(directory, 'readonly-provider', 'ReadLibrary',
			['ReadLibrary.Payload<int>', 'ReadLibrary.Snapshot<int>'], level, vapis=[resource_api])
		readonly_leaves[level] = directory
	readonly_middles = {}
	for leaf_level, middle_level in [*itertools.product([0, 2], repeat=2), (1, 1)]:
		directory = out / f'readonly-l{leaf_level}-m{middle_level}'
		directory.mkdir()
		stage(readonly_leaves[leaf_level], directory)
		provider(directory, 'readonly-middle', 'ReadMiddle',
			['ReadMiddle.inspect', 'ReadMiddle.mutate'], middle_level,
			['readonly-provider.asti'], vapis=[resource_api])
		groups = metadata((directory / 'readonly-middle.asti').read_text())
		assert groups['function F:ReadMiddle.inspect']['readonly'] == 'true'
		assert groups['function F:ReadMiddle.mutate']['readonly'] == 'false'
		readonly_middles[leaf_level, middle_level] = directory
	readonly_consumer = out / 'readonly-client.astra'
	readonly_consumer.write_bytes((HERE / 'unit-readonly-client.astra').read_bytes())
	readonly_trace = b'+231\n+232\n+233\nD2100\n-233\nD2100\n-232\nD2100\n-231\n'
	for leaf_level, middle_level, client_level in [*itertools.product([0, 2], repeat=3), (1, 1, 1)]:
		directory = readonly_middles[leaf_level, middle_level]
		executable = directory / ('readonly-client-O' + str(client_level))
		run([compiler, '-g', '-O' + str(client_level), '--vapi', resource_api,
			'--import-module', directory / 'readonly-middle.asti', readonly_consumer,
			'--link-object', resource_object, '-o', executable])
		run([executable], stdout=readonly_trace)
		run(['valgrind', '--default-suppressions=no', '--leak-check=full', '--show-leak-kinds=all',
			'--errors-for-leak-kinds=all', '--error-exitcode=99', executable], memory=True, stdout=readonly_trace)
		product(executable)
	readonly_mutation = out / 'readonly-mutating-inspector.astra'
	text = readonly_consumer.read_text()
	before = 'return ReadMiddle.inspect(value);'
	assert text.count(before) == 1
	readonly_mutation.write_text(text.replace(before, 'return ReadMiddle.mutate(value);', 1))
	for stage_name in ['--check', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi']:
		run([compiler, stage_name, '--vapi', resource_api, '--import-module',
			readonly_middles[0, 0] / 'readonly-middle.asti', readonly_mutation], expected=1,
			diagnostic='original readonly effect contract')
	for kind in ['missing', 'noncanonical', 'changed']:
		directory = out / ('readonly-forged-' + kind)
		directory.mkdir()
		stage(readonly_middles[0, 0], directory)
		interface = directory / 'readonly-middle.asti'
		groups = metadata(interface.read_text())
		fields = groups['function F:ReadMiddle.inspect']
		if kind == 'missing':
			del fields['readonly']
			diagnostic = 'missing/unknown interface field'
		elif kind == 'noncanonical':
			fields['readonly'] = '1'
			diagnostic = 'readonly effect requires canonical true/false'
		else:
			fields['readonly'] = 'false'
			diagnostic = 'exported symbol fingerprint mismatch'
		interface.write_text(reseal(groups))
		binary = directory / 'unsafe'
		run([compiler, '--vapi', resource_api, '--import-module', interface, readonly_consumer,
			'--link-object', resource_object, '-o', binary], expected=1, diagnostic=diagnostic)
		assert not binary.exists()

		# The actual Map declaration transports a conditional readonly summary and
		# mandatory callback obligations through a second opaque producer. Ordinary
		# callback invocations retain their permission to mutate outside protection.
	callback_source = (HERE / 'unit-callback-provider.astra').read_bytes() + b'\n' + (ROOT / 'lib/astra/collections/map.astra').read_bytes()
	callback_exports = ['NativeQueries.' + name for name in [
		'QueryResult<int>', 'Payload<int>', 'MapEntry<int,NativeQueries.Payload<int>>',
		'Map<int,NativeQueries.Payload<int>>',
		'Map<int,NativeQueries.Payload<int>>::lookup<NativeQueries.QueryResult<int>>',
		'Map<int,NativeQueries.Payload<int>>::inspect<NativeQueries.QueryResult<int>>', 'apply_ordinary']]
	callback_leaves = {}
	for level in [0, 1, 2]:
		directory = out / ('query-callback-leaf-' + str(level))
		provider(directory, 'callback-provider', 'NativeQueries', callback_exports, level,
			source=callback_source, vapis=[resource_api])
		groups = metadata((directory / 'callback-provider.asti').read_text())
		ordinary = groups['function F:NativeQueries.apply_ordinary']
		assert ordinary['readonly'] == 'true' and ordinary['readonly_inputs'] == '0' and ordinary['callback_inputs'] == ''
		callback_leaves[level] = directory
	callback_middles = {}
	for leaf_level, middle_level in [*itertools.product([0, 2], repeat=2), (1, 1)]:
		directory = out / f'query-callback-l{leaf_level}-m{middle_level}'
		directory.mkdir()
		stage(callback_leaves[leaf_level], directory)
		provider(directory, 'callback-middle', 'CallbackMiddle', ['CallbackMiddle.lookup'], middle_level,
			['callback-provider.asti'], vapis=[resource_api])
		fields = metadata((directory / 'callback-middle.asti').read_text())['function F:CallbackMiddle.lookup']
		assert fields['readonly'] == 'true' and fields['readonly_inputs'] == '0' and fields['callback_inputs'] == '0'
		callback_middles[leaf_level, middle_level] = directory
	callback_consumer = out / 'callback-client.astra'
	callback_consumer.write_bytes((HERE / 'unit-callback-client.astra').read_bytes())
	callback_trace = b'+241\n+242\nD2200\n-242\nD2200\n-241\n'
	for leaf_level, middle_level, client_level in [*itertools.product([0, 2], repeat=3), (1, 1, 1)]:
		directory = callback_middles[leaf_level, middle_level]
		executable = directory / ('callback-client-O' + str(client_level))
		run([compiler, '-g', '-O' + str(client_level), '--vapi', resource_api,
			'--import-module', directory / 'callback-middle.asti', callback_consumer,
			'--link-object', resource_object, '-o', executable])
		run([executable], stdout=callback_trace)
		run(['valgrind', '--default-suppressions=no', '--leak-check=full', '--show-leak-kinds=all',
			'--errors-for-leak-kinds=all', '--error-exitcode=99', executable], memory=True, stdout=callback_trace)
		product(executable)
	callback_interface = callback_middles[0, 0] / 'callback-middle.asti'
	for kind, before, after in [
		('required', 'var first = CallbackMiddle.lookup(values, 1, client_observation)', 'var first = CallbackMiddle.lookup(values, 1, client_mutation)'),
		('protected', 'NativeQueries.apply_ordinary(independent, client_observation)', 'NativeQueries.apply_ordinary(independent, client_mutation)')]:
		text = callback_consumer.read_text()
		assert text.count(before) == 1
		mutation = out / ('callback-mutating-' + kind + '.astra')
		mutation.write_text(text.replace(before, after, 1))
		for stage_name in ['--check', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi']:
			run([compiler, stage_name, '--vapi', resource_api, '--import-module', callback_interface,
				mutation], expected=1, diagnostic='native callback inputs')
	for field in ['readonly_inputs', 'callback_inputs']:
		for kind in ['missing', 'noncanonical', 'changed']:
			directory = out / ('callback-forged-' + field + '-' + kind)
			directory.mkdir()
			stage(callback_middles[0, 0], directory)
			interface = directory / 'callback-middle.asti'
			groups = metadata(interface.read_text())
			fields = groups['function F:CallbackMiddle.lookup']
			if kind == 'missing':
				del fields[field]
				diagnostic = 'missing/unknown interface field'
			elif kind == 'noncanonical':
				fields[field] = '0,0'
				diagnostic = 'callback effects require canonical Fn input ordinals'
			else:
				fields[field] = ''
				diagnostic = 'exported symbol fingerprint mismatch'
			interface.write_text(reseal(groups))
			binary = directory / 'unsafe'
			run([compiler, '--vapi', resource_api, '--import-module', interface, callback_consumer,
				'--link-object', resource_object, '-o', binary], expected=1, diagnostic=diagnostic)
			assert not binary.exists()

			# Producer-owned task factories retain their own resume/destroy code. All
			# libraries use one explicitly linked virtual executor provider and error root.
	task_runtime = compiler.parent / 'lib/astra/async-virtual.o'
	assert task_runtime.is_file()
	product(task_runtime)
	task_leaves = {}
	for level in [0, 1, 2]:
		directory = out / ('task-leaf-' + str(level))
		provider(directory, 'task-provider', 'NativeTasks', ['NativeTasks.' + name for name in
			['Error', 'AsyncError', 'Reply<int>', 'Job<int>', 'create', 'compute']], level, vapis=[resource_api])
		groups = metadata((directory / 'task-provider.asti').read_text())
		assert 'native-tasks-v17;task-abi=17;provider=0;runtime-error=NativeTasks.AsyncError;success=NativeTasks.Reply<int>;' in groups[
			'task F:NativeTasks.compute']['contract']
		assert re.fullmatch('[0-9a-f]{64}', groups['task F:NativeTasks.compute']['frame'])
		task_leaves[level] = directory
	task_middles = {}
	for leaf_level, middle_level in [*itertools.product([0, 2], repeat=2), (1, 1)]:
		directory = out / f'task-l{leaf_level}-m{middle_level}'
		directory.mkdir()
		stage(task_leaves[leaf_level], directory)
		provider(directory, 'task-middle', 'TaskMiddle', 'TaskMiddle.work', middle_level,
			['task-provider.asti'], vapis=[resource_api])
		task_middles[leaf_level, middle_level] = directory
	task_consumer = out / 'task-client.astra'
	task_consumer.write_bytes((HERE / 'unit-task-client.astra').read_bytes())
	task_trace = (b'+221\nD2000\n-221\n+222\nD2010\nD2001\nD2000\n-222\n'
		b'+223\nD2010\nD2001\nD2002\nD2000\n-223\nD2011\n'
		b'+224\nD2010\nD2001\nD2000\n-224\n+225\nD2010\nD2001\nD2002\nD2000\n-225\nD2011\n')
	for leaf_level, middle_level, client_level in [*itertools.product([0, 2], repeat=3), (1, 1, 1)]:
		directory = task_middles[leaf_level, middle_level]
		executable = directory / ('task-client-O' + str(client_level))
		run([compiler, '-g', '-O' + str(client_level), '--vapi', resource_api,
			'--import-module', directory / 'task-middle.asti', task_consumer,
			'--link-object', resource_object, '--link-object', task_runtime, '-o', executable])
		run([executable], stdout=task_trace)
		run(['valgrind', '--default-suppressions=no', '--leak-check=full', '--show-leak-kinds=all',
			'--errors-for-leak-kinds=all', '--error-exitcode=99', executable], memory=True, stdout=task_trace)
		product(executable)

	for kind in ['erased-async', 'runtime-provider', 'frame-syntax', 'missing-resume']:
		directory = out / ('task-forged-' + kind)
		directory.mkdir()
		stage(task_leaves[0], directory)
		interface = directory / 'task-provider.asti'
		groups = metadata(interface.read_text())
		if kind == 'erased-async':
			before = 'async Reply<int> compute('
			declarations = groups['abi']['declarations'].replace(before, 'Reply<int> compute(', 1)
			assert declarations != groups['abi']['declarations']
			groups['abi']['declarations'] = declarations
			groups['abi']['declarations_sha256'] = hashlib.sha256(declarations.replace(r'\n', '\n').encode()).hexdigest()
			diagnostic = 'native task declaration/metadata inventory mismatch'
		elif kind == 'runtime-provider':
			diagnostic = 'native task runtime/result/capture contract mismatch'
		elif kind == 'frame-syntax':
			groups['task F:NativeTasks.compute']['frame'] = 'x' * 64
			diagnostic = 'invalid private task frame fingerprint'
		else:
			symbol = groups['function F:NativeTasks.compute']['symbol'] + '_resume'
			run(['objcopy', '--localize-symbol=' + symbol, directory / 'task-provider.o'])
			groups['object']['sha256'] = sha(directory / 'task-provider.o')
			diagnostic = 'implementation is missing exact declared native exports'
		interface.write_text(reseal(groups))
		entry = directory / 'entry.astra'
		entry.write_text('enum RunStatus{Completed,Cancelled} async runtime Executor throws '
			'NativeTasks.AsyncError returns RunStatus' +
			(' provider "linux-io-uring"' if kind == 'runtime-provider' else '') + '; int main(){return 0;}\n')
		run([compiler, '--vapi', resource_api, '--import-module', interface, entry,
			'--link-object', task_runtime, '--link-object', resource_object, '-o', directory / 'unsafe'],
			expected=1, diagnostic=diagnostic)
		assert not (directory / 'unsafe').exists()
	for kind, before, after, diagnostic in [
		('missing-move', 'TaskMiddle.work(move input,', 'TaskMiddle.work(input,', 'move'),
		('after-move', 'if (mode == 0) {', 'if(input.value != 40){return 30;} if (mode == 0) {', 'moved')]:
		entry = out / ('task-' + kind + '.astra')
		text = (HERE / 'unit-task-client.astra').read_text()
		assert text.count(before) == 1
		entry.write_text(text.replace(before, after, 1))
		binary = out / ('task-' + kind)
		run([compiler, '--vapi', resource_api, '--import-module', task_middles[0, 0] / 'task-middle.asti',
			entry, '--link-object', resource_object, '--link-object', task_runtime, '-o', binary],
			expected=1, diagnostic=diagnostic)
		assert not binary.exists()
	trace_directory = task_middles[0, 0]
	trace_file = trace_directory / 'task-consumer-openat.log'
	traced_binary = trace_directory / 'task-client-traced'
	run(['strace', '-f', '-e', 'trace=openat', '-o', trace_file, compiler, '-g', '-O0',
		'--vapi', resource_api, '--import-module', trace_directory / 'task-middle.asti', task_consumer,
		'--link-object', resource_object, '--link-object', task_runtime, '-o', traced_binary])
	trace_text = trace_file.read_text()
	opened_astra = re.findall(r'"([^"\n]*\.astra)"', trace_text)
	assert opened_astra and all(path == str(task_consumer) for path in opened_astra), opened_astra
	assert 'task-provider.o' in trace_text and 'task-middle.o' in trace_text
	run([traced_binary], stdout=task_trace)
	product(trace_file)
	product(traced_binary)

	# Closed-unit target inference must not become an exported effect promise.
	# This control is temporary until declarative callback preconditions are
	# carried by the native interface and independently checked by consumers.
	callback_directory = out / 'callback-effect-contract'
	callback_directory.mkdir()
	callback_source = callback_directory / 'provider.astra'
	callback_source.write_text('namespace CallbackBoundary;\n' +
		(HERE / 'scoped-code-inspection.astra').read_text())
	callback_interface = callback_directory / 'provider.asti'
	callback_object = callback_directory / 'provider.o'
	selectors = ['CodeObservation', 'CodeItem', 'CodeStore<int>', 'CodeStore<f64>']
	run([compiler, '-c', '--module', 'CallbackBoundary',
		*[item for name in selectors for item in ['--native-export', 'CallbackBoundary.' + name]],
		'--emit-interface', callback_interface, callback_source, '-o', callback_object],
		expected=1, diagnostic='native export requires a declarative callback effect contract')
	assert not callback_interface.exists() and not callback_object.exists()

	# No original artifacts or implementation/recipe bytes change during the run.
	assert sha(compiler) == receipt['compiler_sha256']
	for source, digest in receipt['sources'].items():
		assert sha(ROOT / source) == digest
	for path, facts in receipt['products'].items():
		assert sha(Path(path)) == facts['sha256']
	receipt['all_passed'] = True
	save()
	print(out / 'checks.json')


if __name__ == '__main__':
	main(*sys.argv[1:])
