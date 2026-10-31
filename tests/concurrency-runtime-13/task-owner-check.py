# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Owned native Classes captured by cold, failed and cancelled migrated frames."""
from pathlib import Path
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence
from sanitizers import instrument


def main(compiler, output):
	e = Evidence(compiler, output, 'concurrency-task-owners')
	here = Path(__file__).parent
	astra = [here / 'task-owners.astra', ROOT / 'lib/astra/async/threaded.astra', ROOT / 'lib/astra/base/errors.astra']
	providers = [ROOT / 'lib/runtime/async/threaded.c', ROOT / 'lib/runtime/platform/text-posix.c', here / 'task-owner-oracle.c']
	links = []
	for source in providers:
		obj = e.output / (source.stem + '.o')
		e.run(['cc', '-std=c11', '-O2', '-g', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', '-c', source, '-o', obj])
		links += ['--link-object', obj]
	expected = 'task owners: 4 exact acquisitions and destructions after join\n'
	for level in ['O0', 'O1', 'O2']:
		product = e.output / level
		e.run([e.compiler, '-' + level, *astra, *links, '--link-library', 'pthread', '-o', product])
		e.run([product], stdout=expected, timeout=30)
		e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', product], stdout=expected, contains='ERROR SUMMARY: 0 errors', timeout=60)
	for sanitizer in ['address', 'thread']:
		instrument(e, 'owners', astra, providers, expected, sanitizer)
	negative = e.output / 'lexical-forward.astra'
	text = astra[0].read_text()
	assert text.count('var wa = new Work(1)') == 1
	negative.write_text(text.replace('var wa = new Work(1)', 'var wa = Work.init(1)'))
	refusal = e.run([e.compiler, '--check', negative, *astra[1:]], expected=1, contains='owned Class parameter joins incompatible heap and lexical storage origins')
	assert ': error:' in refusal.stderr and 'internal' not in refusal.stderr.lower()
	e.files(negative)
	e.files(*astra, *providers, Path(__file__))
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
