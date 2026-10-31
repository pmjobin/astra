# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Opt-in checked declaration metadata, typed inspection and a metadata-free peer."""
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
	out = Path(tempfile.mkdtemp(prefix='descriptors-', dir=output))
	sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
	model, client, free = [HERE/name for name in ['descriptor-model.astra', 'descriptor-client.astra', 'descriptor-free.astra']]
	qualified = HERE/'descriptor-qualified.astra'
	errors = ROOT/'lib/astra/base/errors.astra'
	text = ROOT/'lib/astra/hosted/text.astra'
	providers = [ROOT/'lib/runtime/platform/args-posix.c', ROOT/'lib/runtime/platform/text-posix.c', HERE/'descriptor-observer.c']
	receipt = dict(compiler=str(compiler), compiler_sha256=sha(compiler),
		sources={str(path.relative_to(ROOT)): sha(path) for path in [model, client, free, qualified, errors, text, *providers, Path(__file__).resolve()]}, checks=[], products={})

	def run(argv, expected=0, diagnostic=None, memory=False, stdout=b''):
		argv = list(map(str, argv))
		result = subprocess.run(argv, cwd=ROOT, capture_output=True, timeout=90,
			env=dict(os.environ, CCACHE_DISABLE='1', PYTHONDONTWRITEBYTECODE='1'))
		passed = result.returncode == expected and (stdout is None or result.stdout == stdout)
		if diagnostic:
			passed &= diagnostic.encode() in result.stderr
			passed &= all(word not in result.stderr for word in [b'internal ', b'assertion', b'CRITICAL'])
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

	module = out/'metadata.astra'
	selection = ['--describe', 'MetaReading', '--describe', 'MetaPoint', '--describe', 'MetaTransform']
	generate = [compiler, '--emit-native-descriptors', '--descriptor-module', 'Witness', *selection, errors, model, '-o', module]
	run(generate)
	generated = module.read_bytes()
	assert b'hidden' not in generated and b'UnselectedNativeValue' not in generated
	run([compiler, '--emit-native-descriptors', '--descriptor-module', 'Witness', '--describe', 'MetaTransform', '--describe', 'MetaReading', '--describe', 'MetaPoint', model, errors, '-o', module])
	assert module.read_bytes() == generated, 'descriptor selection order changed its nominal identities or source'
	receipt['products'][str(module)] = sha(module)
	run([compiler, '--format', '--check', module])
	inputs = [errors, text, model, client, module]
	for stage in ['--check', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-llvm']:
		run([compiler, stage, *inputs], stdout=None)
	objects = []
	for provider in providers:
		obj = out/(provider.stem+'.o'); objects.append(obj)
		run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-c', provider, '-o', obj])
	links = [item for obj in objects for item in ['--link-object', obj]]
	members = {
		'MetaReading': ['class', 'amount', 'field', 'int', 'doubled', 'property', 'int', 'offset', 'method', 'int(int)'],
		'MetaPoint': ['record', 'x', 'field', 'int', 'y', 'field', 'int'],
		'MetaTransform': ['interface', 'invoke', 'method', 'int(int)'],
	}
	for level in ['-O0', '-O1', '-O2']:
		executable = out/('descriptor-client'+level)
		run([compiler, level, *inputs, *links, '-o', executable]); receipt['products'][str(executable)] = sha(executable)
		for wanted, payload in [('MetaReading', 'abc'), ('MetaPoint', 'λ🙂'), ('MetaTransform', 'e\u0301')]:
			seed = len(payload.encode())
			values = [seed, seed*2, seed+5, seed+3, seed+2, seed+11]
			expected = ('\n'.join([wanted, *members[wanted], *map(str, values)])+'\n').encode()
			run([executable, wanted, payload], stdout=expected)
			run(['valgrind', '--default-suppressions=no', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', '--error-exitcode=99', executable, wanted, payload], memory=True, stdout=expected)
		run([executable, 'unknown', 'abc'], expected=98, stdout=b'unknown native type name\n')
		minimal = out/('descriptor-free'+level)
		run([compiler, level, errors, model, free, '-o', minimal]); receipt['products'][str(minimal)] = sha(minimal)
		run([minimal])
		run(['valgrind', '--default-suppressions=no', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', '--error-exitcode=99', minimal], memory=True)
		strings = run(['strings', minimal], stdout=None)
		assert all(name not in strings for name in [b'MetaReading', b'MetaPoint', b'MetaTransform', b'NativeMetadata_', b'descriptor receiver', b'unknown native type'])
		dependencies = run(['readelf', '-d', minimal], stdout=None)
		assert all(name not in dependencies.lower() for name in [b'glib', b'gobject', b'uring', b'pcre', b'regex'])
	for name, replacement, diagnostic in [
		('wrong-native-receiver', 'call_MetaTransform_int(value, amount, 1)', 'type'),
		('private-native-field', 'value.hidden', 'private'),
	]:
		invalid = out/(name+'.astra'); invalid.write_text(client.read_text().replace('read_MetaReading_int(value, amount)', replacement, 1))
		for stage in ['--check', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-llvm']:
			run([compiler, stage, errors, text, model, invalid, module], expected=1, diagnostic=diagnostic)
	for name, options, diagnostic in [
		('unknown-selection', ['--describe', 'MissingType'], 'unknown native descriptor type'),
		('duplicate-selection', ['--describe', 'MetaPoint', '--describe', 'Other=MetaPoint'], 'duplicate selection'),
		('alias-conflict', ['--describe', 'Same=MetaReading', '--describe', 'Same=MetaPoint'], 'distinct identifiers'),
	]:
		run([compiler, '--emit-native-descriptors', '--descriptor-module', 'Witness', *options, errors, model, '-o', module], expected=1, diagnostic=diagnostic)
		assert module.read_bytes() == generated, 'failed descriptor generation changed an existing artifact'
	for options, diagnostic in [
		(['--describe', 'MetaPoint'], 'require --emit-native-descriptors'),
		(['--emit-native-descriptors', '--describe', 'MetaPoint', '-o', module], 'requires --descriptor-module'),
		(['--emit-native-descriptors', '--descriptor-module', 'Witness', '--describe', 'MetaPoint', '-c', '-o', module], '-c requires compilation'),
		(['--help', '--descriptor-module', 'Witness'], '--help/--version cannot'),
	]:
		run([compiler, *options, errors, model], expected=2, diagnostic=diagnostic)
		assert module.read_bytes() == generated
	run([compiler, '--emit-native-descriptors', '--descriptor-module', 'Bad.Name', '--describe', 'MetaPoint', errors, model, '-o', module], expected=1, diagnostic='one identifier module')
	assert module.read_bytes() == generated
	model_hash = sha(model)
	run([*generate[:-2], '-o', model], expected=1, diagnostic='cannot overwrite a source input')
	assert sha(model) == model_hash
	# This independent pair collides under the documented FNV-1a/31 identity.
	collision_names = ['Collision52fdbbe8ee4a', 'Collision55c67e0fe92d']
	def descriptor_id(name):
		value = 2166136261
		for byte in ('Witness::class::'+name).encode():
			value = ((value ^ byte)*16777619) & 0xffffffff
		return (value & 0x7fffffff) or 1
	assert descriptor_id(collision_names[0]) == descriptor_id(collision_names[1]) == 1690213921
	collision = out/'collision.astra'
	collision.write_text('\n'.join('class '+name+' {}' for name in collision_names)+'\n')
	run([compiler, '--emit-native-descriptors', '--descriptor-module', 'Witness',
		'--describe', collision_names[0], '--describe', collision_names[1], errors, collision, '-o', module], expected=1, diagnostic='ID collision')
	assert module.read_bytes() == generated
	# Emission must finish ordinary ownership/liveness checks before publishing.
	invalid_owner = out/'moved-source.astra'
	invalid_owner.write_text('int invalid_owner(){var first=new MetaReading(1); owned MetaReading second=first; return first.amount;}\n')
	run([*generate[:-2], invalid_owner, '-o', module], expected=1, diagnostic='moved')
	assert module.read_bytes() == generated
	for name, declaration in [
		('record', 'struct TypeDescriptor {int fake;}'),
		('enum', 'enum TypeDescriptor {Fake}'),
		('constant', 'const int descriptor_constant=1;'),
		('function', 'int descriptor_function(){return 1;}'),
	]:
		conflict = out/('namespace-'+name+'.astra')
		conflict.write_text('namespace NativeMetadata_Witness;\n'+declaration+'\n')
		run([*generate[:-2], conflict, '-o', module], expected=1, diagnostic='namespace already contains')
		assert module.read_bytes() == generated
	qualified_module = out/'qualified-metadata.astra'
	run([compiler, '--emit-native-descriptors', '--descriptor-module', 'Qualified',
		'--describe', 'Point=DescriptorModels.QualifiedPoint', '--describe', 'Reading=DescriptorModels.QualifiedReading',
		errors, qualified, '-o', qualified_module])
	qualified_client = out/'qualified-client.astra'
	qualified_client.write_text('''using NativeMetadata_Qualified;
int main(){
	try {
		DescriptorModels.QualifiedPoint point={x=17,y=23};
		var value=new DescriptorModels.QualifiedReading(31);
		var pd=lookup("DescriptorModels.QualifiedPoint");
		var rd=lookup("DescriptorModels.QualifiedReading");
		if(read_Point_int(point,member(pd,1))+read_Reading_int(value,member(rd,0))!=54){return 81;}
	} catch(Error error){return 82;}
	return 0;
}
''')
	for level in ['-O0', '-O1', '-O2']:
		executable = out/('qualified'+level)
		run([compiler, level, errors, qualified, qualified_module, qualified_client, '-o', executable])
		run([executable])
		run(['valgrind', '--default-suppressions=no', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', '--error-exitcode=99', executable], memory=True)
		receipt['products'][str(executable)] = sha(executable)
	receipt['status'] = 'PASS'
	(out/'checks.json').write_text(json.dumps(receipt, indent=2)+'\n')
	print(f'PASS {len(receipt["checks"])} public descriptor commands; receipt {out / "checks.json"}')


if __name__ == '__main__':
	main(*sys.argv[1:])
