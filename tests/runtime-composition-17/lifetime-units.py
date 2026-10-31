#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Opaque native lifetime effects, ABI binding and mixed optimization execution."""
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
	e = Evidence(compiler, output, 'runtime-composition-17-lifetime-units')
	here = Path(__file__).resolve().parent
	leaf, middle, consumer = [here / ('lifetime-unit-' + name + '.astra') for name in ['leaf', 'middle', 'consumer']]
	helper = ROOT / 'tests/structural-generics-15/units.py'
	metadata = runpy.run_path(str(helper))
	e.files(leaf, middle, consumer, helper, Path(__file__))
	for levels in [*itertools.product('02', repeat=3), ('1', '1', '1')]:
		case = e.output / ('units-' + ''.join(levels))
		case.mkdir(exist_ok=True)
		e.run([e.compiler, '-O' + levels[0], '-c', leaf, '--module', 'LifetimeLeaf', '--native-export', 'LifetimeLeaf.Leaf', '--native-export', 'LifetimeLeaf.Box', '--native-export', 'LifetimeLeaf.create', '--native-export', 'LifetimeLeaf.wrap', '--emit-interface', case / 'leaf.asti', '-o', case / 'leaf.o'])
		e.run([e.compiler, '-O' + levels[1], '-c', middle, '--module', 'LifetimeMiddle', '--native-export', 'LifetimeMiddle.relay', '--import-module', case / 'leaf.asti', '--emit-interface', case / 'middle.asti', '-o', case / 'middle.o'])
		sdk = case / 'sdk'
		sdk.mkdir(exist_ok=True)
		for name in ['leaf.asti', 'leaf.o', 'middle.asti', 'middle.o']:
			shutil.copyfile(case / name, sdk / name)
		shutil.copyfile(e.compiler, sdk / 'astrac')
		(sdk / 'astrac').chmod(0o755)
		shutil.copyfile(consumer, sdk / 'consumer.astra')
		command = [sdk / 'astrac', '-O' + levels[2], sdk / 'consumer.astra', '--import-module', sdk / 'middle.asti', '-o', sdk / 'consumer']
		assert sorted(p.name for p in sdk.glob('*.astra')) == ['consumer.astra']
		for interface in [sdk / 'leaf.asti', sdk / 'middle.asti']:
			groups = metadata['metadata'](interface.read_text())
			assert groups['abi']['schema'] == 'gnu-x86_64-lp64-runtime-units/6'
			functions = [value for name, value in groups.items() if name.startswith('function ')]
			assert functions and all(value['lifetimes'].startswith('runtime-lifetime-logical/1\\nruntime-lifetime-summary/1\\n') for value in functions)
			key = 'function F:' + ('LifetimeLeaf.wrap' if interface.name == 'leaf.asti' else 'LifetimeMiddle.relay')
			assert groups[key]['lifetimes'].startswith('runtime-lifetime-logical/1\\nruntime-lifetime-summary/1\\n')
			assert 'i|0' in groups[key]['lifetimes']
		e.run(command, cwd=sdk)
		e.run([sdk / 'consumer'], stdout='', cwd=sdk)
		if levels == ('2', '2', '2'):
			e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', sdk / 'consumer'], stdout='', contains='ERROR SUMMARY: 0 errors', cwd=sdk)
			trace = sdk / 'opens.log'
			e.run(['strace', '-f', '-e', 'trace=openat,openat2', '-o', trace, *command], cwd=sdk)
			opened = trace.read_text()
			assert str(leaf) not in opened and str(middle) not in opened
			assert str(sdk / 'leaf.asti') in opened and str(sdk / 'middle.asti') in opened
			for name, diagnostic in [('version', 'invalid versioned lifetime contract'), ('removed', 'missing/unknown interface field'), ('weakened', 'exported symbol fingerprint mismatch')]:
				bad = sdk / ('mutant-' + name)
				bad.mkdir(exist_ok=True)
				shutil.copyfile(sdk / 'leaf.o', bad / 'leaf.o')
				groups = metadata['metadata']((sdk / 'leaf.asti').read_text())
				function = groups['function F:LifetimeLeaf.wrap']
				if name == 'version': function['lifetimes'] = function['lifetimes'].replace('summary/1', 'summary/9')
				elif name == 'removed': del function['lifetimes']
				else: function['lifetimes'] = 'runtime-lifetime-summary/1:incomplete'
				(bad / 'leaf.asti').write_text(metadata['reseal'](groups))
				e.run([sdk / 'astrac', '-c', sdk / 'consumer.astra', '--import-module', bad / 'leaf.asti', '-o', bad / 'refused.o'], expected=1, contains=diagnostic, cwd=sdk)
				e.files(bad / 'leaf.asti', bad / 'leaf.o')
			e.files(trace)
		e.files(*[sdk / name for name in ['leaf.asti', 'leaf.o', 'middle.asti', 'middle.o', 'consumer', 'consumer.astra']])
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
