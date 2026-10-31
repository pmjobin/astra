#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Opaque checked constructors preserve complete caller buffer ownership."""
from pathlib import Path
import re
import shutil
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence


def main(compiler, output, profile="buffers"):
	assert profile in ["buffers", "records"]
	e = Evidence(compiler, output, 'runtime-composition-17-constructor-' + ('record' if profile == 'records' else 'buffer') + '-units')
	here = Path(__file__).resolve().parent
	fixture = here / ('context-fallible-' + profile + '.astra')
	producer, consumer = fixture.read_text().split('int main()', 1)
	producer = 'namespace ConstructorBuffers;\n' + producer
	consumer = 'extern(C) int admission_finish();\nint main()' + consumer
	names = ['AdmissionFault', 'AdmissionChild', 'AdmissionOwner', 'retained_input'] if profile == 'buffers' else ['AdmissionFault', 'AdmissionChild', 'AdmissionOwner', 'AdmissionRecord', 'AdmissionEnvelope', 'admission_record', 'admission_record_probe', 'AdmissionCopyTag', 'AdmissionCopyOwner']
	for name in names:
		consumer = re.sub(r'\b' + name + r'\b', 'ConstructorBuffers.' + name, consumer)
	vapis = [ROOT / 'lib/bindings/memory/contexts.vapi', here / 'context-fallible-inputs.vapi']
	providers = [ROOT / 'lib/runtime/runtime/context-17.c', ROOT / 'lib/runtime/platform/text-posix.c', here / 'context-fallible-inputs-oracle.c']
	objects = []
	for source in providers:
		obj = e.output / (source.stem + '.o'); objects.append(obj)
		e.run(['cc', '-std=c11', '-O2', '-g', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', '-c', source, '-o', obj]); e.files(obj)
	expected = 'fallible inputs: refusal preserves caller owners, admission empties slots and rollback retires each input once\n'
	selectors = ['AdmissionFault', 'AdmissionChild', 'AdmissionOwner']
	selectors += ['AdmissionOnly<ConstructorBuffers.AdmissionChild>', 'retained_input'] if profile == 'buffers' else ['AdmissionRecord<ConstructorBuffers.AdmissionChild>', 'AdmissionEnvelope<ConstructorBuffers.AdmissionChild>', 'admission_record', 'admission_record_probe', 'AdmissionCopyTag', 'AdmissionCopyOwner']
	exports = [arg for name in selectors for arg in ['--native-export', 'ConstructorBuffers.' + name]]
	for levels in ['00', '02', '20', '22', '11']:
		case = e.output / ('units-' + levels); case.mkdir(exist_ok=True)
		source = case / 'implementation.astra'; source.write_text(producer)
		e.run([e.compiler, '-O' + levels[0], '-c', source, *[arg for path in vapis for arg in ['--vapi', path]], '--module', 'ConstructorBuffers', *exports, '--emit-interface', case / 'producer.asti', '-o', case / 'producer.o'])
		sdk = case / 'sdk'; sdk.mkdir(exist_ok=True)
		for path in [case / 'producer.asti', case / 'producer.o', *vapis, *objects]: shutil.copyfile(path, sdk / path.name)
		shutil.copyfile(e.compiler, sdk / 'astrac'); (sdk / 'astrac').chmod(0o755)
		(sdk / 'consumer.astra').write_text(consumer)
		assert [path.name for path in sdk.glob('*.astra')] == ['consumer.astra']
		command = [sdk / 'astrac', '-O' + levels[1], '--entry-object', sdk / 'consumer.astra', *[arg for path in vapis for arg in ['--vapi', sdk / path.name]], '--import-module', sdk / 'producer.asti', '-o', sdk / 'consumer.o']
		e.run(command, cwd=sdk)
		e.run(['cc', '-pthread', sdk / 'consumer.o', sdk / 'producer.o', *[sdk / path.name for path in objects], '-o', sdk / 'consumer'], cwd=sdk)
		e.run([sdk / 'consumer'], stdout=expected, cwd=sdk)
		if levels == '22':
			e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', sdk / 'consumer'], stdout=expected, contains='ERROR SUMMARY: 0 errors', timeout=45, cwd=sdk)
			trace = sdk / 'opens.log'; e.run(['strace', '-f', '-e', 'trace=openat,openat2', '-o', trace, *command], cwd=sdk)
			assert str(source) not in trace.read_text() and str(sdk / 'producer.asti') in trace.read_text()
		e.files(source, *[path for path in sdk.iterdir() if path.is_file()])
	e.files(*providers, *vapis, fixture, Path(__file__))
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
