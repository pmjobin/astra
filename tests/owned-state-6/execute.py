# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Public O0/O1/O2 app execution. Includes field-owned record construction and checked rollback."""
from pathlib import Path
import hashlib
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
APPS = ROOT / 'examples/owned-state-6'
LIBS = [ROOT / p for p in ['lib/astra/base/errors.astra', 'lib/astra/text/utf8-message.astra',
	'lib/astra/hosted/text.astra', 'lib/astra/hosted/files.astra',
	'lib/astra/collections/bag.astra', 'lib/astra/memory/byte-arena.astra']]
NAMES = ['lazy-diagnostic-card', 'retryable-settings-reader', 'bounded-spool-allocator',
	'scoped-buffer-index', 'diagnostic-queue-editor', 'cached-diagnostic-rewriter',
	'nested-resource-event', 'record-batch-rollback']


def main(compiler_path, output_path):
	compiler, output = Path(compiler_path).resolve(), Path(output_path).resolve()
	assert not output.is_relative_to(ROOT)
	output.mkdir(parents=True, exist_ok=True)
	out = Path(tempfile.mkdtemp(prefix='run-', dir=output))
	rows = []
	sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
	receipt = dict(compiler=str(compiler), compiler_sha256=sha(compiler), checks=rows,
		source_sha256={str(p.relative_to(ROOT)): sha(p) for p in [*LIBS, APPS/'model.astra',
		*[APPS/(n+'.astra') for n in NAMES], HERE/'observer.c', HERE/'execute.py', HERE/'arena-edges.astra', HERE/'allocation-accounting.astra', HERE/'allocation-accounting.c', HERE/'direct-slots.astra', HERE/'record-resources.c', ROOT/'tests/own-field/fixtures/resources.vapi', HERE/'owning-lazy.astra', HERE/'owning-checked-lazy.astra', HERE/'owning-lazy-lifecycle.astra']}, products={})
	def save():
		(out/'checks.json').write_text(json.dumps(receipt, indent=2)+'\n')
	def run(command, expected=0, stdout=None, memory=False, target=None, env=None):
		start = time.monotonic()
		p = subprocess.run(list(map(str, command)), cwd=ROOT, capture_output=True, timeout=120,
			env=dict(os.environ, CCACHE_DISABLE='1', **(env or {})))
		valid = p.returncode == expected and (stdout is None or p.stdout == stdout)
		if memory:
			valid &= all(x in p.stderr for x in [b'ERROR SUMMARY: 0 errors',
				b'in use at exit: 0 bytes in 0 blocks', b'(suppressed: 0 from 0)'])
		else:
			valid &= not p.stderr
		row = dict(command=list(map(str, command)), expected=expected, actual=p.returncode,
			seconds=round(time.monotonic()-start, 4), memory=memory, passed=bool(valid))
		if target:
			target.write_bytes(p.stdout); row['stdout_file'] = str(target); row['stdout_sha256'] = sha(target)
		else:
			row.update(stdout=p.stdout.decode(errors='replace'), stderr=p.stderr.decode(errors='replace'))
		rows.append(row); save()
		assert valid, row
		return p
	providers = []
	for name in ['text', 'files', 'args']:
		obj = out/(name+'.o'); providers += ['--link-object', obj]
		run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-c',
			ROOT/f'lib/astra/platform/{name}-posix.c', '-o', obj], stdout=b'')
	resource = out/'resources.o'; providers += ['--link-object', resource]
	run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-c', HERE/'record-resources.c', '-o', resource], stdout=b'')
	observer = out/'observer.o'; providers += ['--link-object', observer]
	run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-c', HERE/'observer.c', '-o', observer], stdout=b'')
	vg = ['valgrind', '--default-suppressions=no', '--leak-check=full', '--show-leak-kinds=all',
		'--errors-for-leak-kinds=all', '--error-exitcode=99']
	assert shutil.which('valgrind'), 'Valgrind required for this host qualification'
	accountant = out/'accountant.o'
	run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-c', HERE/'allocation-accounting.c', '-o', accountant], stdout=b'')
	expected = {
		NAMES[0]: b'event 1 65\nevent 1 65\nA41 cached embedded NUL and Unicode; moved; independent receiver\nevent 2 65\nevent 2 65\n',
		NAMES[1]: b'event 3 101\ninvalid record; retry\nevent 3 101\nevent 1 101\nevent 3 102\nevent 3 102\nevent 1 102\nA42 two attempts; warm read skipped changed file\nevent 2 102\nevent 2 101\n',
		NAMES[2]: b'spool full; recovered\nA45 wrote 5 binary bytes; arena empty\n',
		NAMES[3]: b'A46 UTF-8 starts 0,1,3; expired index rejected\n',
		NAMES[4]: b'event 4 1\nevent 4 2\nevent 4 3\nevent 4 4\nevent 5 1\nevent 4 5\nevent 5 2\nA47 order 4,3,5; first/middle/last extracted; append reused slot\nevent 5 3\nevent 5 5\nevent 5 4\n',
	}
	expected[NAMES[6]] = b'+1\n+2\n+4\n+3\n-2\n-1\n-3\n-4\n+0\n+5\n-5\nD43\n'
	expected[NAMES[7]] = b'+1\n+2\n-2\n-1\nD1\n+3\n+2\n-2\n-3\n+4\n+2\n-2\n-4\nD2\nD44\n'
	for opt in ['-O0', '-O1', '-O2']:
		obj, accounting = out/('accounting'+opt+'.o'), out/('accounting'+opt)
		run([compiler, opt, '-c', HERE/'allocation-accounting.astra', ROOT/'lib/astra/memory/byte-arena.astra',
			ROOT/'lib/astra/base/errors.astra', '-o', obj], stdout=b'')
		run(['cc', obj, accountant, '-Wl,--wrap=calloc', '-Wl,--wrap=free', '-o', accounting], stdout=b'')
		run([accounting]); run([*vg, accounting], memory=True)
		receipt['products'][obj.name] = sha(obj); receipt['products'][accounting.name] = sha(accounting); save()
		edge = out/('arena-edges'+opt)
		run([compiler, opt, HERE/'arena-edges.astra', ROOT/'lib/astra/memory/byte-arena.astra',
			ROOT/'lib/astra/base/errors.astra', '-o', edge], stdout=b'')
		run([edge], stdout=b''); run([*vg, edge], stdout=b'', memory=True)
		receipt['products'][edge.name] = sha(edge); save()
		direct = out/('direct-slots'+opt)
		run([compiler, opt, HERE/'direct-slots.astra', '-o', direct], stdout=b'')
		run([direct], stdout=b''); run([*vg, direct], stdout=b'', memory=True)
		receipt['products'][direct.name] = sha(direct); save()
		for unit in ['owning-lazy', 'owning-checked-lazy', 'owning-lazy-lifecycle']:
			exe = out/(unit+opt)
			run([compiler, opt, HERE/(unit+'.astra'), LIBS[0], '--link-object', observer, '-o', exe], stdout=b'')
			trace = b'' if unit != 'owning-lazy-lifecycle' else b'event 7 5\nevent 7 6\nevent 8 105\nevent 9 6\nevent 8 5\nevent 9 5\nevent 8 108\nevent 8 8\nevent 7 12\nevent 7 13\nevent 8 12\nevent 9 13\nevent 9 12\nevent 7 20\nevent 8 20\nevent 9 20\nevent 6 1\nevent 7 30\nevent 8 30\nevent 9 30\n'
			run([exe], stdout=trace); run([*vg, exe], stdout=trace, memory=True)
			receipt['products'][exe.name] = sha(exe); save()
		for name in NAMES:
			sources = [APPS/(name+'.astra'), APPS/'model.astra', *LIBS]
			if name in NAMES[6:]:
				sources = [APPS/(name+'.astra'), LIBS[0], '--vapi', ROOT/'tests/own-field/fixtures/resources.vapi']
			exe = out/(name+opt)
			run([compiler, opt, *sources, *providers, '-o', exe], stdout=b'')
			receipt['products'][exe.name] = sha(exe); save()
			if opt == '-O0':
				for stage in ['semantics', 'core', 'cfg', 'ssa', 'nabi', 'llvm']:
					run([compiler, '--dump-'+stage, *sources], target=out/(name+'.'+stage))
			cases = [(None, None)] if name != NAMES[5] else [
				(b'input=\xc3\xa9\0row', b'input=\xc3\xa9\0rowOK\0\n'),
				(b'', b'repaired=\xc3\xa9\0recordOK\0\n'),
				(b'\xff', b'repaired=\xc3\xa9\0recordOK\0\n')]
			for data, written in cases:
				for memory in [False, True]:
					args = []
					dest = out/(name+'.output')
					if name in [NAMES[1], NAMES[2]]:
						args = [dest]
					if name == NAMES[5]:
						source = out/'rewriter.input'; source.write_bytes(data)
						args = [source, dest]
						attempts = 1 if data and data != b'\xff' else 2
						trace = b'event 3 201\n'*attempts + b'event 1 201\nA48 rewritten exact bytes; cached source retained\nevent 2 201\n'
					else:
						trace = expected[name]
					run([*vg, exe, *args] if memory else [exe, *args], stdout=trace, memory=memory)
					if name == NAMES[2]:
						assert dest.read_bytes() == b'A\0\xff\xc3\xa9'
					if written is not None:
						assert dest.read_bytes() == written, (name, dest.read_bytes(), written)
	print(f'{len(rows)} checks; eight executed sources at public O0/O1/O2; receipts: {out}')

if __name__ == '__main__':
	main(*sys.argv[1:])
