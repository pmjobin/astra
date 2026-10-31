# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Instrument actual emitted Astra memory operations and every C provider."""
from pathlib import Path
import re
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence


def instrument(e, name, astra, providers, expected, sanitizer, link_flags=(), vapis=(), entry_symbol='main', execute=None):
	target = dict(line.split('=', 1) for line in e.run([e.compiler, '--target-info']).stdout.splitlines() if '=' in line)
	imports = [argument for path in vapis for argument in ['--vapi', path]]
	text = e.run([e.compiler, '-O1', '--dump-llvm', *astra, *imports]).stdout
	assert re.search(r'^define .*?@' + re.escape(entry_symbol) + r'\(', text, flags=re.M)
	text = f'target datalayout = "{target["data-layout"]}"\ntarget triple = "{target["target"]}"\n' + text
	attribute = 'sanitize_thread' if sanitizer == 'thread' else 'sanitize_address'
	text = re.sub(r'^(define .*?)\s*\{\s*$', rf'\1 {attribute} {{', text, flags=re.M)
	stem = name + '-' + sanitizer
	raw, modified, obj, product = [e.output / (stem + suffix) for suffix in ['.ll', '-instrumented.ll', '.o', '']]
	raw.write_text(text)
	passes = 'default<O1>,tsan-module,function(tsan)' if sanitizer == 'thread' else 'default<O1>,asan'
	e.run(['opt', '-passes=' + passes, '-S', raw, '-o', modified])
	code = modified.read_text()
	assert ('__tsan_read' in code and '__tsan_write' in code) if sanitizer == 'thread' else '__asan_report' in code
	e.run(['llc', '-O1', '-filetype=obj', '-relocation-model=pic', modified, '-o', obj])
	e.run(['clang', '-O1', '-g', '-std=c11', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread',
		'-fsanitize=' + ('thread' if sanitizer == 'thread' else 'address,undefined'), obj, *providers, *link_flags, '-o', product])
	environment = {'TSAN_OPTIONS': 'halt_on_error=1', 'ASAN_OPTIONS': 'detect_leaks=1:halt_on_error=1', 'UBSAN_OPTIONS': 'halt_on_error=1'}
	if execute is None:
		e.run([product], stdout=expected, timeout=45, env=environment)
	else:
		execute(product, environment)
	e.files(*astra, *providers, *vapis, raw, modified, obj, product)


def main(compiler, output):
	e = Evidence(compiler, output, 'concurrency-emitted-sanitizers')
	here = Path(__file__).parent
	runtime = ROOT / 'lib/runtime/runtime'
	thread = runtime / 'threads-13.c'
	monitor = runtime / 'monitors-13.c'
	cases = [
		('monitor', [here / 'monitor.astra'], [thread, monitor, here / 'thread-oracle.c'],
		'native threads: 4 simultaneous identities, 4 exact environment destructions\n'),
		('weak-race', [here / 'weak-race.astra'], [thread, monitor, here / 'weak-race-oracle.c'],
		'weak race: four native workers, one payload destruction, expired upgrade\n'),
		('singleton', [here / 'singleton.astra', ROOT / 'lib/astra/base/errors.astra'],
		[thread, monitor, runtime / 'singletons-13.c', here / 'singleton-oracle.c', here / 'thread-oracle.c'],
		'singleton: failed initialization retried, one racing publication, quiescent shutdown\nnative threads: 4 simultaneous identities, 4 exact environment destructions\n'),
		('threaded', [here / 'threaded.astra', ROOT / 'lib/astra/async/threaded.astra', ROOT / 'lib/astra/base/errors.astra'],
		[ROOT / 'lib/runtime/async/threaded.c', ROOT / 'lib/runtime/platform/text-posix.c', here / 'task-oracle.c'],
		'executor: four concurrent native frames, eight observed steps, joined shutdown\n'),
	]
	for name, astra, providers, expected in cases:
		for sanitizer in ['address', 'thread']:
			instrument(e, name, astra, providers, expected, sanitizer)
	e.files(Path(__file__))
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
