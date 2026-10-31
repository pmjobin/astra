# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Authentic wrapper lowering with instrumented provider and native cleanup."""
from pathlib import Path
import json
import re
import subprocess
import sys
sys.dont_write_bytecode = True
from qualify import HERE, LIB, run, process, cc, sha, launch


def qualify(build, out):
	build = build.resolve(); out = out.resolve(); out.mkdir(parents=True, exist_ok=True)
	source = HERE / 'fixtures/effects.astra'; sources = [source, LIB / 'hosted/text.astra', LIB / 'base/contracts.astra']
	input_file = out / 'effects.input.ll'
	run([build / 'tests/args/astra-args-llvm', '--emit', input_file, *sources, '--vapi', HERE / 'fixtures/effects.vapi'])
	ir = input_file.read_bytes()
	assert b'define i32 @main(i32' in ir and b'args.valid' in ir and b'@astra_host_args_dispose_v0' in ir
	assert ir.index(b'args.ready:') < ir.rindex(b'@astra_host_args_dispose_v0')
	launcher = out / 'launcher'; cc('/usr/bin/gcc', HERE / 'launcher.c', launcher)
	text = out / 'text.o'; cc('/usr/bin/gcc', LIB / 'platform/text-posix.c', text, ['-c'])
	failure = out / 'failure.o'; cc('/usr/bin/gcc', LIB / 'platform/failure-trap.c', failure, ['-c'])
	rows = []
	for mode in ['O0', 'O2', 'fma', 'preserved']:
		input_ir = ir if mode != 'preserved' else re.sub(rb'(define internal fastcc [^\n]+) \{', rb'\1 noinline {', ir)
		path = out / (mode + '.input.ll'); path.write_bytes(input_ir); lowered = out / (mode + '.ll'); obj = out / (mode + '.o')
		run(['opt', '-passes=verify' if mode == 'O0' else '-passes=default<O2>', '-S', path, '-o', lowered])
		run(['llc', '-filetype=obj', '-relocation-model=pic', '-O0' if mode == 'O0' else '-O2', *(['-mattr=+fma'] if mode == 'fma' else []), lowered, '-o', obj])
		for host in ['gcc', 'clang']:
			provider = out / ('provider-' + host + '.o'); cc('/usr/bin/' + host, LIB / 'platform/args-posix.c', provider, ['-c', '-Dmalloc=args_snapshot_alloc', '-Dfree=args_snapshot_free'])
			for kind in ['normal', 'allocation-failure', 'trap']:
				exe = out / ('effects-' + mode + '-' + host + '-' + kind)
				cc('/usr/bin/' + host, HERE / 'effects.c', exe, [*(['-DFAIL_SNAPSHOT'] if kind == 'allocation-failure' else ['-DTRAP_INDEX'] if kind == 'trap' else []), obj, provider, text, failure, '-Wl,--wrap=calloc', '-Wl,--wrap=free'])
				p = launch(launcher, exe, [b'invocation', b'a\xc3\xa9'], out)
				if kind == 'normal':
					assert p.returncode == 0 and p.stdout == b'a\xc3\xa9\n' and p.stderr == b'AERBCBIUbMcbrD', (mode, host, p)
					with open('/dev/full', 'wb') as full:
						failed = subprocess.run([str(exe), 'aé'], stdout=full, stderr=subprocess.PIPE, timeout=30)
					assert failed.returncode == 1 and failed.stderr == b'AERBCBIUbMOcbrD', (mode, host, failed)
					invalid = launch(launcher, exe, [b'invocation', b'\xff'], out)
					assert invalid.returncode == 2 and invalid.stdout == b'' and invalid.stderr == b'AD'
				elif kind == 'allocation-failure':
					assert p.returncode == 3 and not p.stdout and p.stderr == b'F'
				else:
					assert p.returncode < 0 and not p.stdout and p.stderr == b'AERBCBI', p
				rows.append(dict(mode=mode, host=host, kind=kind, executable=str(exe), status=p.returncode, trace=p.stderr.decode(), llvm_sha256=sha(lowered.read_bytes())))
				# Call the authentic private host wrapper with argc=0, independently of exec.
	zero_source = out / 'zero.astra'; zero_source.write_text('int main(string[] a){return len(a)+7;}')
	zero_ir = out / 'zero.ll'; run([build / 'tests/args/astra-args-llvm', '--emit', zero_ir, zero_source])
	zero_ir.write_bytes(zero_ir.read_bytes().replace(b'define i32 @main(', b'define i32 @args_host_main('))
	zero_obj = out / 'zero.o'; run(['llc', '-filetype=obj', '-relocation-model=pic', zero_ir, '-o', zero_obj])
	zero_c = out / 'zero.c'; zero_c.write_text('#include <assert.h>\n#include <stdint.h>\nextern int args_host_main(int argc,char **argv);\nint main(void){char a[]="ok";char bad[]={-1,0};char *v[]={a,0};assert(args_host_main(0,(char **)(uintptr_t)1)==7);assert(args_host_main(1,v)==8);v[0]=bad;assert(args_host_main(1,v)==2);return 0;}\n')
	for host in ['gcc', 'clang']:
		provider = out / ('zero-provider-' + host + '.o'); cc('/usr/bin/' + host, LIB / 'platform/args-posix.c', provider, ['-c'])
		exe = out / ('zero-wrapper-' + host); cc('/usr/bin/' + host, zero_c, exe, [zero_obj, provider]); run([exe])
		rows.append(dict(kind='true-zero-wrapper-and-status', host=host, executable=str(exe), status=0))
	(out / 'effects.json').write_text(json.dumps(rows, indent='\t') + '\n'); print('ARGS-1 effects/cleanup PASS')


if __name__ == '__main__':
	qualify(Path(sys.argv[1]), Path(sys.argv[2]))
