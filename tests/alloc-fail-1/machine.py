# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Physical rejection, actual phi predecessors and bounded cold-path costs."""
from pathlib import Path
import hashlib
import json
import os
import re
import resource
import signal
import subprocess
import sys


def qualify(build, out):
	out.mkdir(parents=True, exist_ok=False)
	(out / 'tmp').mkdir()
	resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
	env = dict(os.environ, TMPDIR=str(out / 'tmp'), CCACHE_DISABLE='1')
	rows = []
	def run(argv, label, status=0):
		p = subprocess.run(list(map(str, argv)), cwd=out, env=env, capture_output=True)
		(out / (label + '.stdout')).write_bytes(p.stdout)
		(out / (label + '.stderr')).write_bytes(p.stderr)
		rows.append(dict(label=label, argv=list(map(str, argv)), status=p.returncode, stdout_sha256=hashlib.sha256(p.stdout).hexdigest()))
		assert p.returncode == status and not p.stderr, (label, p)
		return p.stdout
	try:
		(out / 'unexpected.c').write_text('#include <stdlib.h>\n#include <stdio.h>\n#include <stddef.h>\nvoid unexpected_failure_action(void){puts("UNEXPECTED ACTION");fflush(stdout);_Exit(91);}\nvoid *__wrap_calloc(size_t n,size_t s){(void)n;(void)s;puts("UNEXPECTED ALLOCATOR");fflush(stdout);_Exit(92);}\n')
		for cc in ['gcc', 'clang']:
			run([cc, '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-c', 'unexpected.c', '-o', cc + '.o'], cc + '-observer')
		for mode in ['empty', 'negative', 'address', 'unsigned']:
			ir = run([build / 'tests/alloc-fail-1/astra-alloc-fail-llvm', '--physical', mode], mode + '-emit')
			assert b'allocator.null.action' in ir and b'call void @unexpected_failure_action()' in ir and b'call void @llvm.trap()' in ir
			(out / (mode + '.ll')).write_bytes(ir)
			for optimization in ['O0', 'O2', 'O2-fma']:
				stem = mode + '-' + optimization
				run(['opt', '-passes=verify' if optimization == 'O0' else '-passes=default<O2>', '-S', mode + '.ll', '-o', stem + '.ll'], stem + '-opt')
				run(['llc', '-O0' if optimization == 'O0' else '-O2', '-filetype=obj', '-relocation-model=pic', *(['-mattr=+fma'] if optimization == 'O2-fma' else []), stem + '.ll', '-o', stem + '.o'], stem + '-llc')
				for cc in ['gcc', 'clang']:
					exe = out / (stem + '-' + cc)
					run([cc, stem + '.o', cc + '.o', '-Wl,--wrap=calloc', '-o', exe], exe.name + '-link')
					assert run([exe], exe.name, 0 if mode == 'empty' else -signal.SIGILL) == b''
				run(['objdump', '-dr', stem + '.o'], stem + '-machine')
				# Retain the actual unused-payload null branch at every optimization level.
		(out / 'action.c').write_text('#include <stddef.h>\n#include <stdio.h>\nvoid cold_action(int n){printf("action %d\\n",n);fflush(stdout);}\nvoid *__wrap_calloc(size_t n,size_t s){(void)n;(void)s;return NULL;}\n')
		run(['gcc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-c', 'action.c', '-o', 'action.o'], 'action-provider')
		costs = {}
		for name, body in [('default', 'int main(){var a=new int[2];return 0;}'), ('annotated', 'extern(C) void cold_action(int n);int main(){var a=new int[2] else cold_action(2);return 0;}'), ('array-free', 'int main(){return 0;}')]:
			(out / (name + '.astra')).write_text(body + '\n')
			ssa = run([build / 'astrac', '--dump-ssa', name + '.astra'], name + '-ssa').decode()
			ordinal = re.search(r'\(function #(\d+) "main" -> int', ssa)[1]
			ir = run([build / 'astrac', '--dump-llvm', name + '.astra'], name + '-llvm').decode()
			if name != 'annotated':
				assert 'cold_action' not in ir and 'allocation-action' not in ir
			if name == 'array-free':
				assert '@calloc' not in ir and '@free' not in ir
			(out / (name + '.ll')).write_text(ir + '\ndefine i32 @main(){\n\t%r=call fastcc i32 @astra.fn.' + ordinal + '()\n\tret i32 %r\n}\n')
			for optimization in ['O0', 'O2', 'O2-fma']:
				stem = name + '-' + optimization
				run(['opt', '-passes=verify' if optimization == 'O0' else '-passes=default<O2>', '-S', name + '.ll', '-o', stem + '.ll'], stem + '-opt')
				run(['llc', '-O0' if optimization == 'O0' else '-O2', '-filetype=obj', '-relocation-model=pic', *(['-mattr=+fma'] if optimization == 'O2-fma' else []), stem + '.ll', '-o', stem + '.o'], stem + '-llc')
				symbols = run(['nm', '-u', stem + '.o'], stem + '-symbols')
				assert (b'cold_action' in symbols) == (name == 'annotated')
				costs[stem] = dict(object_bytes=(out / (stem + '.o')).stat().st_size, sections=run(['size', '-A', stem + '.o'], stem + '-size').decode(), undefined=symbols.decode())
				run(['objdump', '-dr', stem + '.o'], stem + '-machine')
				exe = out / stem
				run(['gcc', stem + '.o', 'action.o', '-Wl,--wrap=calloc', '-o', exe], stem + '-link')
				assert run([exe], stem, 0 if name == 'array-free' else -signal.SIGILL) == (b'action 2\n' if name == 'annotated' else b'')
		(out / 'result.json').write_text(json.dumps(dict(physical_runs=24, unused_payload_runs=9, costs=costs, llvm_verifies_actual_predecessors=True), indent='\t') + '\n')
	finally:
		(out / 'commands.json').write_text(json.dumps(rows, indent='\t') + '\n')
	print('24 physical rejection controls; 9 unused-payload/dependency/cost witnesses')


if __name__ == '__main__':
	sys.dont_write_bytecode = True
	sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tools/qualification'))
	from output_paths import fresh_output
	sys.argv[-1] = str(fresh_output(sys.argv[-1]))
	qualify(Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve())
