# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Ordinary template bodies, exact specializations, and native ownership."""
from pathlib import Path
import hashlib
import json
import os
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent


def main(compiler_path, output_path):
	compiler, output = Path(compiler_path).resolve(), Path(output_path).resolve()
	assert not output.is_relative_to(ROOT)
	output.mkdir(parents=True, exist_ok=True)
	out = Path(tempfile.mkdtemp(prefix='generic-', dir=output))
	sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
	source = HERE/'generic-body.astra'
	resource_source = HERE/'generic-resource.astra'
	record_source = HERE/'generic-record.astra'
	method_source = HERE/'generic-method.astra'
	owning_source = HERE/'generic-owning-record.astra'
	owner_source = HERE/'generic-owner.astra'
	nested_source = HERE/'generic-nested.astra'
	property_source = HERE/'generic-property.astra'
	lazy_property_source = HERE/'generic-property-lazy.astra'
	property_result_source = HERE/'generic-property-result.astra'
	errors = ROOT/'lib/astra/base/errors.astra'
	vector = ROOT/'lib/astra/collections/vector.astra'
	vapi = ROOT/'tests/own-field/fixtures/resources.vapi'
	observer_source = ROOT/'tests/owned-state-6/record-resources.c'
	receipt = dict(compiler=str(compiler), compiler_sha256=sha(compiler),
		sources={str(path.relative_to(ROOT)): sha(path) for path in [source, resource_source, record_source, method_source, owning_source, owner_source, nested_source, property_source, lazy_property_source, property_result_source, errors, vector, vapi, observer_source, Path(__file__).resolve()]},
		checks=[], products={})

	def run(argv, expected=0, diagnostic=None, memory=False, dump=False, stdout=b''):
		argv = list(map(str, argv))
		result = subprocess.run(argv, cwd=ROOT, capture_output=True, timeout=90,
			env=dict(os.environ, CCACHE_DISABLE='1', PYTHONDONTWRITEBYTECODE='1'))
		passed = result.returncode == expected
		if diagnostic:
			passed &= diagnostic.encode() in result.stderr
			passed &= all(text not in result.stderr for text in [b'internal ', b'assertion', b'CRITICAL'])
		elif memory:
			passed &= result.stdout == stdout and all(text in result.stderr for text in [b'ERROR SUMMARY: 0 errors',
				b'in use at exit: 0 bytes in 0 blocks', b'(suppressed: 0 from 0)'])
		else:
			passed &= not result.stderr and (dump or result.stdout == stdout)
		receipt['checks'].append(dict(command=argv, expected_exit=expected, actual_exit=result.returncode,
			stdout=result.stdout.decode(errors='replace'), stderr=result.stderr.decode(errors='replace'), passed=bool(passed),
			astra_inputs={arg: sha(Path(arg)) for arg in argv if arg.endswith('.astra') and Path(arg).is_file()}))
		(out/'checks.json').write_text(json.dumps(receipt, indent=2)+'\n')
		assert passed, receipt['checks'][-1]

	for stage in ['--check', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-llvm']:
		run([compiler, stage, source], dump=True)
	for level in ['-O0', '-O1', '-O2']:
		executable = out/('generic-body'+level)
		run([compiler, level, source, '-o', executable])
		receipt['products'][str(executable)] = sha(executable)
		run([executable])
		run(['valgrind', '--default-suppressions=no', '--leak-check=full', '--show-leak-kinds=all',
			'--errors-for-leak-kinds=all', '--error-exitcode=99', executable], memory=True)
	text = source.read_text()
	cases = [
		('missing-init', 'this.entries = new T[slots];', '', 'before definite initialization'),
		('duplicate-init', 'this.entries = new T[slots];', 'this.entries = new T[slots]; this.entries = new T[slots];', 'one exact empty initialization'),
		('duplicate-owner', 'this.entries.append(move value);', 'this.entries.append(move value); this.entries.append(move value);', 'moved'),
		('wrong-specialization', 'values.replace(90, move ignored);', 'values.replace(90, move ignored); wrong(values);', 'type'),
		('owned-copy', 'values.append(move one)', 'values.append(one)', 'move'),
	]
	for name, old, new, diagnostic in cases:
		invalid = out/(name+'.astra')
		invalid.write_text(text.replace(old, new) + ('\nvoid wrong(Depot<Other> value) {}\n' if name == 'wrong-specialization' else ''))
		for stage in ['--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-llvm']:
			run([compiler, stage, invalid], expected=1, diagnostic=diagnostic, dump=True)

	resource_inputs = ['--vapi', vapi, vector, resource_source]
	for stage in ['--check', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-llvm']:
		run([compiler, stage, *resource_inputs], dump=True)
	observer = out/'observer.o'
	run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-c', observer_source, '-o', observer])
	trace = b'+1\n+2\n+3\nD1\nD2\n+4\n-1\nD4\nD23\n+0\n+5\nD5\n+6\nD6\n+7\nD6\nD6\nD206\n-6\nD207\n-7\n-5\n-2\n-3\n-4\n'
	for level in ['-O0', '-O1', '-O2']:
		executable = out/('generic-resource'+level)
		run([compiler, level, *resource_inputs, '--link-object', observer, '-o', executable])
		receipt['products'][str(executable)] = sha(executable)
		run([executable], stdout=trace)
		run(['valgrind', '--default-suppressions=no', '--leak-check=full', '--show-leak-kinds=all',
			'--errors-for-leak-kinds=all', '--error-exitcode=99', executable], stdout=trace, memory=True)
	text = resource_source.read_text()
	for name, old, new, diagnostic, extra in [
		('resource-copy', 'values.append(move one)', 'values.append(one)', 'move', ''),
		('resource-use-after-move', 'mark(first(values));', 'mark(id(one));', 'moved', ''),
		('resource-wrong-domain', 'others.append(move other)', 'others.append(move taken)', 'type', ''),
		('resource-borrow-relocation', 'mark(first(values));', 'inspect_pair(values.entries[0], values.reserve(9));', 'overlaps', '\nvoid inspect_pair(R value, bool changed) {}\n'),
	]:
		invalid = out/(name+'.astra')
		invalid.write_text(text.replace(old, new, 1)+extra)
		for stage in ['--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-llvm']:
			run([compiler, stage, '--vapi', vapi, vector, invalid], expected=1, diagnostic=diagnostic, dump=True)

	for stage in ['--check', '--dump-semantics', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-llvm']:
		run([compiler, stage, vector, record_source], dump=True)
	for level in ['-O0', '-O1', '-O2']:
		executable = out/('generic-record'+level)
		run([compiler, level, vector, record_source, '-o', executable])
		receipt['products'][str(executable)] = sha(executable)
		run([executable])
		run(['valgrind', '--default-suppressions=no', '--leak-check=full', '--show-leak-kinds=all',
			'--errors-for-leak-kinds=all', '--error-exitcode=99', executable], memory=True)
	text = record_source.read_text()
	for name, old, new, diagnostic, extra in [
		('record-wrong-specialization', 'var result = counts.take(0);', 'wrong(counts); var result = counts.take(0);', 'type', '\nvoid wrong(Vector<OtherCount> value) {}\n'),
		('record-wrong-value', 'counts.append(count)', 'counts.append(sample)', 'exact nominal', ''),
		('record-index-type', 'values.entries[0]', 'values.entries[true]', 'int/i32', ''),
		('record-descriptor-copy', 'var copy = values.entries[0];', 'var descriptor = values.entries; var copy = values.entries[0];', 'descriptor is field-only', ''),
	]:
		invalid = out/(name+'.astra')
		invalid.write_text(text.replace(old, new, 1)+extra)
		for stage in ['--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-llvm']:
			run([compiler, stage, vector, invalid], expected=1, diagnostic=diagnostic, dump=True)
	method_inputs = ['--vapi', vapi, method_source]
	for stage in ['--check', '--dump-semantics', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-llvm']:
		run([compiler, stage, *method_inputs], dump=True)
	for level in ['-O0', '-O1', '-O2']:
		executable = out/('generic-method'+level)
		run([compiler, level, *method_inputs, '--link-object', observer, '-o', executable])
		receipt['products'][str(executable)] = sha(executable)
		trace = b'+1\n+2\n+3\n-3\n-2\n-1\n'
		run([executable], stdout=trace)
		run(['valgrind', '--default-suppressions=no', '--leak-check=full', '--show-leak-kinds=all',
			'--errors-for-leak-kinds=all', '--error-exitcode=99', executable], stdout=trace, memory=True)
	formatted = out/'formatted-method.astra'
	run([compiler, '--format', '-o', formatted, method_source])
	run([compiler, '--format', '--check', formatted])
	run([compiler, '--dump-llvm', '--vapi', vapi, formatted], dump=True)
	text = method_source.read_text()
	# Approved historical replacement: an unused U still has nominal identity,
	# but constant<R>() transports no owner and needs no copyability constraint.
	owner_argument = out/'method-owner-erasure.astra'
	assert text.count('objects.constant<Payload>()') == 1
	owner_argument.write_text(text.replace('objects.constant<Payload>()', 'objects.constant<R>()', 1))
	for stage in ['--check', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-llvm']:
		run([compiler, stage, '--vapi', vapi, owner_argument], dump=True)
	for level in ['-O0', '-O1', '-O2']:
		executable = out/('method-owner-erasure'+level)
		run([compiler, level, '--vapi', vapi, owner_argument, '--link-object', observer, '-o', executable])
		receipt['products'][str(executable)] = sha(executable)
		run([executable], stdout=trace)
		run(['valgrind', '--default-suppressions=no', '--leak-check=full', '--show-leak-kinds=all',
			'--errors-for-leak-kinds=all', '--error-exitcode=99', executable], stdout=trace, memory=True)
	for name, old, new, diagnostic in [
		('method-missing-argument', 'objects.echo<int>(7)', 'objects.echo(7)', 'one explicit'),
		('method-wrong-argument', 'objects.echo<int>(7)', 'objects.echo<bool>(7)', 'type'),
		('method-duplicate-owner', 'return move value;', 'bool consumed = this.push<int>(move value, 1); return move value;', 'moved'),
	]:
		invalid = out/(name+'.astra')
		invalid.write_text(text.replace(old, new, 1))
		for stage in ['--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-llvm']:
			run([compiler, stage, '--vapi', vapi, invalid], expected=1, diagnostic=diagnostic, dump=True)
	owning_inputs = ['--vapi', vapi, vector, errors, owning_source]
	for stage in ['--check', '--dump-semantics', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-llvm']:
		run([compiler, stage, *owning_inputs], dump=True)
	trace = b'+1\n+11\n+21\n+2\n+12\n+22\n+3\n+13\n+23\nD42\n+4\n+14\n+24\n-21\nD101\n-11\n-1\nD4\n+5\n+15\n+25\n-25\nD105\n-15\n-5\nD900\n+0\n-24\nD104\n-14\n-4\nD102\n-12\n-22\n-2\n-23\nD103\n-13\n-3\n'
	for level in ['-O0', '-O1', '-O2']:
		executable = out/('generic-owning-record'+level)
		run([compiler, level, *owning_inputs, '--link-object', observer, '-o', executable])
		receipt['products'][str(executable)] = sha(executable)
		run([executable], stdout=trace)
		run(['valgrind', '--default-suppressions=no', '--leak-check=full', '--show-leak-kinds=all',
			'--errors-for-leak-kinds=all', '--error-exitcode=99', executable], stdout=trace, memory=True)
	text = owning_source.read_text()
	for name, old, new, diagnostic in [
		('owning-record-copy', 'values.append(move first)', 'values.append(first)', 'explicit move'),
		('owning-record-duplicate', 'bool b = values.append(move second);', 'bool b = values.append(move first);', 'moved'),
		('owning-record-index-copy', 'var result = values.take(1);', 'var result = values.entries[1];', 'copy'),
		('owning-record-fresh-argument', 'values.append(move first)', 'values.append(produce(6))', 'explicit move'),
	]:
		invalid = out/(name+'.astra')
		invalid.write_text(text.replace(old, new, 1))
		for stage in ['--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-llvm']:
			run([compiler, stage, '--vapi', vapi, vector, errors, invalid], expected=1, diagnostic=diagnostic, dump=True)
	owner_inputs = ['--vapi', vapi, vector, errors, owner_source]
	for stage in ['--check', '--dump-semantics', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-llvm']:
		run([compiler, stage, *owner_inputs], dump=True)
	trace = b'+1\nD900\nD1\nD1\nD101\n-1\nD901\n+2\nD2\nD7\nD902\nD102\n-2\n'
	for level in ['-O0', '-O1', '-O2']:
		executable = out/('generic-owner'+level)
		run([compiler, level, *owner_inputs, '--link-object', observer, '-o', executable])
		receipt['products'][str(executable)] = sha(executable)
		run([executable], stdout=trace)
		run(['valgrind', '--default-suppressions=no', '--leak-check=full', '--show-leak-kinds=all',
			'--errors-for-leak-kinds=all', '--error-exitcode=99', executable], stdout=trace, memory=True)
	text = owner_source.read_text()
	for name, old, new, diagnostic in [
		('generic-owner-copy', 'relay(move original)', 'relay(original)', 'move'),
		('generic-owner-use-after-move', 'if (inspect(forwarded) != 1)', 'if (inspect(original) != 1)', 'moved'),
		('generic-owner-wrong-specialization', 'inspect(forwarded)', 'other_count(forwarded)', 'type'),
		('generic-owner-callee-failure-consumes', 'mark(901);', 'mark(inspect(forwarded));', 'moved'),
	]:
		invalid = out/(name+'.astra')
		invalid.write_text(text.replace(old, new, 1))
		for stage in ['--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-llvm']:
			run([compiler, stage, '--vapi', vapi, vector, errors, invalid], expected=1, diagnostic=diagnostic, dump=True)
	nested_inputs = ['--vapi', vapi, vector, nested_source]
	for stage in ['--check', '--dump-semantics', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-llvm']:
		run([compiler, stage, *nested_inputs], dump=True)
	trace = b'+1\n+2\nD2\n+3\nD102\n-2\nD1\n+4\nD41\n-4\nD101\n-1\nD103\n-3\n'
	for level in ['-O0', '-O1', '-O2']:
		executable = out/('generic-nested'+level)
		run([compiler, level, *nested_inputs, '--link-object', observer, '-o', executable])
		receipt['products'][str(executable)] = sha(executable)
		run([executable], stdout=trace)
		run(['valgrind', '--default-suppressions=no', '--leak-check=full', '--show-leak-kinds=all',
			'--errors-for-leak-kinds=all', '--error-exitcode=99', executable], stdout=trace, memory=True)
	text = nested_source.read_text()
	for name, old, new, diagnostic, extra in [
		('nested-owner-copy', 'groups.append(move first)', 'groups.append(first)', 'move', ''),
		('nested-readonly-mutation', 'count_entries(group)', 'mutate_entries(group)', 'readonly scoped inspector', '\nint mutate_entries(Vector<Entry> values) { bool changed = values.reserve(20); return values.count(); }\n'),
		('nested-owner-alias', 'sum = sum + count_entries(group);', 'var alias = group; sum = sum + count_entries(group);', 'call-scoped readonly', ''),
		('nested-wrong-specialization', 'mark(sum);', 'wrong(groups); mark(sum);', 'type', '\nvoid wrong(Vector<Vector<Pair>> values) {}\n'),
	]:
		invalid = out/(name+'.astra')
		invalid.write_text(text.replace(old, new, 1)+extra)
		for stage in ['--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-llvm']:
			run([compiler, stage, '--vapi', vapi, vector, invalid], expected=1, diagnostic=diagnostic, dump=True)
	cycle = out/'slot-record-cycle.astra'
	cycle.write_text('class Root{owned Packet[slots] entries;init(){this.entries=new Packet[slots];}}struct Packet{owned Root child;}int main(){var root=new Root();return 0;}\n')
	for stage in ['--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-llvm']:
		run([compiler, stage, cycle], expected=1, diagnostic='cyclic', dump=True)
	property_inputs = ['--vapi', vapi, property_source]
	run([compiler, '--format', '--check', property_source])
	for stage in ['--check', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-llvm']:
		run([compiler, stage, *property_inputs], dump=True)
	trace = b'+0\n+1\n+2\n+3\n+4\nD15\nD3\nD68\nD16\nD12\nD6\nD4\nD104\nD102\nD101\nD100\n-1\nD103\n-4\n-3\n-2\n'
	for level in ['-O0', '-O1', '-O2']:
		executable = out/('generic-property'+level)
		run([compiler, level, *property_inputs, '--link-object', observer, '-o', executable])
		receipt['products'][str(executable)] = sha(executable)
		run([executable], stdout=trace)
		run(['valgrind', '--default-suppressions=no', '--leak-check=full', '--show-leak-kinds=all',
			'--errors-for-leak-kinds=all', '--error-exitcode=99', executable], stdout=trace, memory=True)
	text = property_source.read_text()
	# Approved historical replacements: lazy getters use ordinary cache semantics;
	# T results use the substituted type and its supported ownership contract.
	for name, positive, trace in [
		('generic-property-lazy', lazy_property_source,
		b'+1\n+2\n+3\nD10\nD40\nD20\nD70\nD200\nD103\n-3\nD201\nD102\n-2\nD201\nD101\n-1\n'),
		('generic-property-T-result-positive', property_result_source, b'+4\nD44\n-4\n'),
	]:
		run([compiler, '--format', '--check', positive])
		for stage in ['--check', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-llvm']:
			run([compiler, stage, '--vapi', vapi, positive], dump=True)
		for level in ['-O0', '-O1', '-O2']:
			executable = out/(name+level)
			run([compiler, level, '--vapi', vapi, positive, '--link-object', observer, '-o', executable])
			receipt['products'][str(executable)] = sha(executable)
			run([executable], stdout=trace)
			run(['valgrind', '--default-suppressions=no', '--leak-check=full', '--show-leak-kinds=all',
				'--errors-for-leak-kinds=all', '--error-exitcode=99', executable], stdout=trace, memory=True)
			# Isolate the original integer getter at a copied-record specialization so
			# owner-result restrictions do not mask its genuine return-type mismatch.
	invalid = out/'generic-property-T-result.astra'
	invalid.write_text(text.split('struct PropertyPoint')[0].replace('property int size', 'property T size', 1)
		+ 'struct PropertyPoint { int x; int y; }\n'
		+ 'int main() { var points = new PropertyValues<PropertyPoint>(); var result = points.size; return result.x; }\n')
	for stage in ['--check', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-llvm']:
		run([compiler, stage, '--vapi', vapi, invalid], expected=1, diagnostic="exact nominal type 'PropertyPoint', found 'int'", dump=True)
	for name, old, new, diagnostic in [
		('generic-property-wrong-receiver', 'property_size(entries)', 'property_size(points)', 'type'),
	]:
		invalid = out/(name+'.astra'); invalid.write_text(text.replace(old, new, 1))
		for stage in ['--check', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-llvm']:
			run([compiler, stage, '--vapi', vapi, invalid], expected=1, diagnostic=diagnostic, dump=True)
	assert sha(compiler) == receipt['compiler_sha256']
	assert all(sha(ROOT/path) == digest for path, digest in receipt['sources'].items())
	receipt['status'] = 'PASS'
	(out/'checks.json').write_text(json.dumps(receipt, indent=2)+'\n')
	print(f'PASS: {len(receipt["checks"])} general generic-body checks; {out / "checks.json"}')


if __name__ == '__main__':
	main(*sys.argv[1:])
