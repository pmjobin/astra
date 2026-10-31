#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Schema /5 context transport, opaque SDK, mixed optimization and ABI refusals."""
from pathlib import Path
import itertools
import runpy
import shutil
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence


def main(compiler, output):
	e = Evidence(compiler, output, 'runtime-composition-17-context-units')
	here = Path(__file__).resolve().parent
	sources = [here / ('context-unit-' + part + '.astra') for part in ['leaf', 'middle', 'consumer']]
	vapis = [ROOT / 'lib/bindings/memory/contexts.vapi', here / 'context-custom.vapi']
	providers = [ROOT / 'lib/runtime/runtime/context-17.c', here / 'context-provider.c', here / 'context-unit-oracle.c']
	e.files(*sources, *vapis, *providers, ROOT / 'lib/runtime/runtime/context-17.h', here / 'context-provider.h', Path(__file__))
	objects = []
	for source in providers:
		obj = e.output / (source.stem + '.o')
		e.run(['cc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', '-c', source, '-o', obj])
		objects.append(obj)
		e.files(obj)
	helper = ROOT / 'tests/structural-generics-15/units.py'
	metadata = runpy.run_path(str(helper))
	e.files(helper)
	expected = 'context native SDK: opaque leaf/middle, four exact origins and escaping backing\n'
	for levels in [*itertools.product('02', repeat=3), ('1', '1', '1')]:
		case = e.output / ('units-' + ''.join(levels))
		case.mkdir(exist_ok=True)
		imports = [arg for path in vapis for arg in ['--vapi', path]]
		e.run([e.compiler, '-O' + levels[0], '-c', sources[0], *imports, '--module', 'ContextLeaf', '--native-export', 'ContextLeaf.Entry', '--native-export', 'ContextLeaf.Keeper', '--native-export', 'ContextLeaf.create', '--emit-interface', case / 'leaf.asti', '-o', case / 'leaf.o'])
		e.run([e.compiler, '-O' + levels[1], '-c', sources[1], *imports, '--module', 'ContextMiddle', '--native-export', 'ContextMiddle.relay', '--native-export', 'ContextMiddle.escaping', '--import-module', case / 'leaf.asti', '--emit-interface', case / 'middle.asti', '-o', case / 'middle.o'])
		sdk = case / 'sdk'
		sdk.mkdir(exist_ok=True)
		for path in [case / name for name in ['leaf.asti', 'leaf.o', 'middle.asti', 'middle.o']]:
			shutil.copyfile(path, sdk / path.name)
		for path in [*vapis, *objects]:
			shutil.copyfile(path, sdk / path.name)
		shutil.copyfile(e.compiler, sdk / 'astrac')
		(sdk / 'astrac').chmod(0o755)
		shutil.copyfile(sources[2], sdk / 'consumer.astra')
		links = [arg for obj in objects for arg in ['--link-object', sdk / obj.name]]
		public_imports = [arg for path in vapis for arg in ['--vapi', sdk / path.name]]
		command = [sdk / 'astrac', '-O' + levels[2], sdk / 'consumer.astra', *public_imports, '--import-module', sdk / 'middle.asti', *links, '--link-library', 'pthread', '-o', sdk / 'consumer']
		assert sorted(p.name for p in sdk.glob('*.astra')) == ['consumer.astra']
		for path in sdk.glob('*.asti'):
			text = path.read_text()
			assert 'schema=gnu-x86_64-lp64-runtime-units/6' in text and 'runtime=runtime-contexts/1;tasks/17;endpoints/1;effects/1' in text
			assert 'this.value = value' not in text and 'value + 2' not in text
			if path.name == 'leaf.asti':
				assert 'context-field=CONTEXT(runtime-contexts/1;ConcurrentAllocator;owned-concurrent;astra_context17_destroy)' in text
		e.run(command, cwd=sdk)
		e.run([sdk / 'consumer'], stdout=expected, cwd=sdk)
		if levels == ('2', '2', '2'):
			e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', sdk / 'consumer'], stdout=expected, contains='ERROR SUMMARY: 0 errors', cwd=sdk)
			trace = sdk / 'opens.log'
			e.run(['strace', '-f', '-e', 'trace=openat,openat2', '-o', trace, *command], cwd=sdk)
			opened = trace.read_text()
			assert all(str(path) not in opened for path in sources[:2])
			assert str(sdk / 'leaf.asti') in opened and str(sdk / 'middle.asti') in opened
			for field, value in [('runtime', 'runtime-contexts/0;tasks/13;endpoints/1;effects/1'), ('compiler', '0' * 64)]:
				bad = sdk / ('mutant-' + field)
				bad.mkdir(exist_ok=True)
				shutil.copyfile(sdk / 'leaf.o', bad / 'leaf.o')
				groups = metadata['metadata']((sdk / 'leaf.asti').read_text())
				groups['abi'][field] = value
				(bad / 'leaf.asti').write_text(metadata['reseal'](groups))
				e.run([sdk / 'astrac', '-c', sdk / 'consumer.astra', *public_imports, '--import-module', bad / 'leaf.asti', '-o', bad / 'consumer.o'], expected=1, contains='mismatch', cwd=sdk)
			for label, old, new in [
				('capability', 'context = "owned-concurrent"', 'context = "owned-affine"'),
				('release', 'destroy_function = "astra_context17_destroy"', 'destroy_function = "wrong_context_release"')]:
				bad_api = sdk / ('mutant-' + label + '.vapi')
				bad_api.write_text((sdk / vapis[0].name).read_text().replace(old, new, 1))
				e.run([sdk / 'astrac', '-c', sdk / 'consumer.astra', '--vapi', bad_api, '--vapi', sdk / vapis[1].name,
					'--import-module', sdk / 'middle.asti', '-o', sdk / ('mutant-' + label + '.o')], expected=1, contains='native', cwd=sdk)
			e.files(trace)
		e.files(*[path for path in sdk.iterdir() if path.is_file()])
	e.run([e.compiler, '--target=x86_64-w64-windows-gnu', '--foreign-personalities=none', '-c', sources[0],
		*imports, '--module', 'ContextLeaf', '--native-export', 'ContextLeaf.Entry', '--native-export', 'ContextLeaf.create',
		'--emit-interface', e.output / 'unsupported-windows.asti', '-o', e.output / 'unsupported-windows.o'], expected=1, contains='Windows interop object profile')
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
