#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Execute genuine preserved M16 /4 objects through explicit ABI compatibility."""
from pathlib import Path
import runpy
import shutil
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence


def main(compiler, old_directory, output):
	e = Evidence(compiler, output, 'runtime-composition-17-legacy-units')
	old_directory = Path(old_directory).resolve()
	here = ROOT / 'tests/declaration-interop-16'
	helper = ROOT / 'tests/structural-generics-15/units.py'
	metadata = runpy.run_path(str(helper))
	sdk = e.output / 'sdk'
	sdk.mkdir(exist_ok=True)
	for name in ['leaf.asti', 'leaf.o', 'middle.asti', 'middle.o']:
		original = old_directory / name
		assert original.is_file() and not original.is_symlink()
		if original.suffix == '.asti':
			groups = metadata['metadata'](original.read_text())
			assert groups['abi']['schema'] == 'gnu-x86_64-lp64-foreign-units/4'
			assert groups['abi']['compiler'] != e.data['compiler']['sha256']
		e.files(original)
		shutil.copyfile(original, sdk / name)
	shutil.copyfile(e.compiler, sdk / 'astrac')
	(sdk / 'astrac').chmod(0o755)
	# The preserved consumer belongs to this exact historical SDK surface.
	legacy_consumer = old_directory / 'consumer.astra'
	assert legacy_consumer.is_file() and not legacy_consumer.is_symlink()
	shutil.copyfile(legacy_consumer, sdk / 'consumer.astra')
	e.files(legacy_consumer, here / 'foreign-unit-native-client.c', ROOT / 'lib/runtime/interop/foreign-14.c', helper, Path(__file__))
	e.run([sdk / 'astrac', '-c', sdk / 'consumer.astra', '--import-module', sdk / 'middle.asti', '-o', sdk / 'default.o'], expected=1, contains='version/schema/compiler fingerprint', cwd=sdk)
	for level in ['0', '1', '2']:
		obj = sdk / ('consumer-O' + level + '.o')
		product = sdk / ('legacy-O' + level)
		e.run([sdk / 'astrac', '-O' + level, '-c', sdk / 'consumer.astra', '--import-legacy-module', sdk / 'middle.asti', '-o', obj], cwd=sdk)
		e.run(['cc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', here / 'foreign-unit-native-client.c', obj, sdk / 'leaf.o', sdk / 'middle.o', ROOT / 'lib/runtime/interop/foreign-14.c', '-o', product], cwd=sdk)
		e.run([product], contains='PASS native-only opaque foreign declarations', cwd=sdk)
	e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', sdk / 'legacy-O2'], contains='ERROR SUMMARY: 0 errors', cwd=sdk)
	bad = sdk / 'stale-task'
	bad.mkdir(exist_ok=True)
	shutil.copyfile(sdk / 'leaf.o', bad / 'leaf.o')
	groups = metadata['metadata']((sdk / 'leaf.asti').read_text())
	key = next(group[9:] for group in groups if group.startswith('function '))
	groups['task ' + key] = dict(contract='native-tasks-v13', frame='0' * 64)
	(bad / 'leaf.asti').write_text(metadata['reseal'](groups))
	e.run([sdk / 'astrac', '-c', sdk / 'consumer.astra', '--import-legacy-module', bad / 'leaf.asti', '-o', bad / 'consumer.o'], expected=1, contains='legacy task/frame ABI changed', cwd=sdk)
	# A new /5 unit records its explicitly checked unchanged legacy dependency.
	wrapper = sdk / 'wrapper.astra'
	wrapper.write_text('''namespace LegacyWrapper;
public int run() {
	var facade = new Adapter16.Facade(9);
	Hidden16.Sample sample = {enabled = false, count = 5, weight = 2.0};
	var result = facade.amend(sample, 4);
	return result.count - 18;
}
''')
	e.run([sdk / 'astrac', '-O2', '-c', wrapper, '--import-legacy-module', sdk / 'middle.asti', '--module', 'LegacyWrapper', '--native-export', 'LegacyWrapper.run', '--emit-interface', sdk / 'wrapper.asti', '-o', sdk / 'wrapper.o'], cwd=sdk)
	assert 'compatibility=legacy-unchanged/1' in (sdk / 'wrapper.asti').read_text()
	consumer = sdk / 'wrapper-consumer.astra'
	consumer.write_text('extern(C) int legacy_finish(); int main(){int result=LegacyWrapper.run();return result+legacy_finish();}\n')
	oracle = sdk / 'legacy-events.c'
	oracle.write_text('''#include <assert.h>
static int sessions, facades;
int opaque16_retired(void) { ++sessions; return 0; }
int opaque16_facade_retired(void) { ++facades; return 0; }
int legacy_finish(void) { assert(sessions == 1 && facades == 1); return 0; }
''')
	for source in [oracle, ROOT / 'lib/runtime/interop/foreign-14.c']:
		e.run(['cc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', '-c', source, '-o', sdk / (source.stem + '.o')], cwd=sdk)
	e.run([sdk / 'astrac', '-O1', consumer, '--import-module', sdk / 'wrapper.asti', '--link-object', sdk / 'legacy-events.o', '--link-object', sdk / 'foreign-14.o', '--link-library', 'pthread', '-o', sdk / 'mixed'], cwd=sdk)
	e.run([sdk / 'mixed'], stdout='', cwd=sdk)
	# Removing the explicit legacy edge must restore strict current validation.
	original = (sdk / 'wrapper.asti').read_text()
	groups = metadata['metadata'](original)
	groups['dependency Adapter16'].pop('compatibility')
	(sdk / 'wrapper.asti').write_text(metadata['reseal'](groups))
	e.run([sdk / 'astrac', '-c', consumer, '--import-module', sdk / 'wrapper.asti', '-o', sdk / 'unmarked-legacy.o'], expected=1, contains='version/schema/compiler fingerprint', cwd=sdk)
	(sdk / 'wrapper.asti').write_text(original)
	e.files(*[path for path in sdk.iterdir() if path.is_file()])
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
