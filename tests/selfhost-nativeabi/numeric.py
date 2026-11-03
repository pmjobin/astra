#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Additional documented NUM-CONV-1 cases, separate from the frozen 39."""
import argparse
import hashlib
import json
from pathlib import Path
import resource
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT/'tests/selfhost-llvm'))
from oracle import memory

NORMAL = {
	'integer-to-FP': 'f32 narrow(u64 x){return x as f32;}f32 signed_narrow(int x){return x as f32;}f64 wide(i64 x){return x as f64;}int main(){if(narrow(9223372586610589697)!=9223373136366403584.0f||signed_narrow(-16777219)!=-16777220.0f||wide(-9007199254740991)!=-9007199254740991.0d){return 1;}return 0;}',
	'FP-to-narrow': 'i8 signed_value(f64 x){return x as i8;}u32 unsigned_value(f64 x){return x as u32;}int from_small(f32 x){return x as int;}int main(){if(signed_value(-128.9d)!=-128||signed_value(127.9d)!=127||unsigned_value(-0.5d)!=0||unsigned_value(4294967295.9d)!=4294967295||from_small(-3.9f)!=-3){return 1;}return 0;}',
	'FP-to-wide': 'i64 signed_value(f64 x){return x as i64;}u64 unsigned_value(f64 x){return x as u64;}int main(){if(signed_value(-9223372036854775808.0d)!=-9223372036854775808||unsigned_value(18446744073709549568.0d)!=18446744073709549568||unsigned_value(-0.0d)!=0||signed_value(1.0e-300d)!=0){return 1;}return 0;}',
}
FATAL = {
	'nan': ('int', 'x/x'), 'infinity': ('int', '1.0d/x'),
	'signed-low': ('i8', '-129.0d'), 'signed-high': ('i8', '128.0d'),
	'unsigned-low': ('u32', '-1.0d'), 'unsigned-high': ('u32', '4294967296.0d'),
	'i64-high': ('i64', '9223372036854775808.0d'),
	'u64-high': ('u64', '18446744073709551616.0d'),
}
REPRODUCER = '''#include <stdint.h>
#include <inttypes.h>
#include <stdio.h>
#include <string.h>
volatile uint64_t source=UINT64_C(9223372586610589697);
int main(void){float x=(float)source;uint32_t bits;memcpy(&bits,&x,sizeof bits);printf("%08" PRIx32 "\\n",bits);return bits==UINT32_C(0x5f000001)?0:1;}
'''


def sha(path):
	return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
	resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
	p = argparse.ArgumentParser()
	for key in ('component', 'compiler', 'runtime', 'build'):
		p.add_argument('--'+key, type=Path, required=True)
	p.add_argument('--mode', choices=('O0', 'O2'), required=True)
	p.add_argument('--inputs', type=Path, required=True)
	a = p.parse_args()
	assert all(not path.resolve().is_relative_to(ROOT) for path in (a.runtime, a.build))
	a.runtime.mkdir(parents=True, exist_ok=False); a.build.mkdir(parents=True, exist_ok=True)
	assert not a.inputs.resolve().is_relative_to(ROOT)
	a.inputs.mkdir(parents=True, exist_ok=True)
	identity = json.loads(a.component.with_suffix('.identity.json').read_text())
	assert sha(a.component) == identity['sha256']
	assert all(sha(path) == digest for path, digest in identity['identity']['sources'].items())
	assert sha(a.compiler) == '30865ad8a9d1652b63ad882f1e29031c76ac13204212f822b44235cb07df10de'
	commands, results, instrumented = [], [], []
	def run(argv, name, expected=0):
		start = time.monotonic()
		r = subprocess.run(list(map(str, argv)), capture_output=True, cwd=a.build, timeout=180)
		(a.runtime/(name+'.stdout')).write_bytes(r.stdout); (a.runtime/(name+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(name=name, argv=list(map(str, argv)), exit=r.returncode,
			monotonic_start=start, monotonic_end=time.monotonic()))
		(a.runtime/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
		assert r.returncode in (expected if isinstance(expected, tuple) else (expected,)), (name, r.returncode, r.stderr[-2000:])
		return r
		# Keep host arithmetic qualification distinct from this measured emulator
		# limitation. Both independent C compilers must reproduce its exact bits.
	repro = a.inputs/'instrumentation-reproducer.c'
	if repro.exists():
		assert repro.read_text() == REPRODUCER
	else:
		repro.write_text(REPRODUCER)
	deviations = []
	for compiler in ('gcc', 'clang'):
		exe = a.build/('instrumentation-'+compiler)
		run([compiler, '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', repro, '-o', exe], compiler+'-reproducer-build')
		r = run([exe], compiler+'-reproducer-host'); assert r.stdout == b'5f000001\n'
		v = run(['valgrind', '--default-suppressions=no', '--error-exitcode=97', '--leak-check=full', exe], compiler+'-reproducer-instrumented', (0, 1))
		assert (v.returncode, v.stdout) in ((0, b'5f000001\n'), (1, b'5f000000\n'))
		memory(v.stderr); deviations.append(v.returncode == 1)
	shared_emulator_deviation = all(deviations)
	cases = [(name, source, 0) for name, source in NORMAL.items()]
	for name, (type_name, expression) in FATAL.items():
		source = type_name+' convert(f64 value){return value as '+type_name+';}int main(){f64 x=0.0d;var converted=convert('+expression+');return 0;}'
		cases.append((name, source, -4))
	for name, text, expected in cases:
		source = a.inputs/(name+'.astra')
		if source.exists():
			assert source.read_bytes() == (text+'\n').encode()
		else:
			source.write_text(text+'\n')
		obj = a.build/(name+'.o'); exe = obj.with_suffix('.native'); c0 = obj.with_suffix('.c0')
		run([a.compiler, '--check', source], name+'-C0-check')
		run([a.component, '--emit-obj', a.mode, obj, source], name+'-emit')
		run(['gcc', obj, '-o', exe], name+'-link')
		run([a.compiler, '-'+a.mode, source, '-o', c0], name+'-C0-build')
		for label, product in [('native', exe), ('C0', c0)]:
			r = run([product], name+'-'+label, expected)
			assert not r.stdout and not r.stderr
			if expected == 0:
				allowed = (0, 1) if name == 'integer-to-FP' and shared_emulator_deviation else 0
				v = run(['valgrind', '--default-suppressions=no', '--error-exitcode=97', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=definite,indirect,possible', product], name+'-memory-'+label, allowed)
				instrumented.append(dict(case=name, producer=label, exit=v.returncode, memory=memory(v.stderr),
					numeric_conformance='DEFERRED: exact GCC/Clang emulator discrepancy' if v.returncode else 'PASS'))
		if name == 'FP-to-narrow':
			forbidden = a.runtime/'numeric.forbidden.o'
			r = run([a.component, '--nativeabi-mutations', a.mode, forbidden, source], 'numeric-guard-mutation')
			proof = []
			for line in r.stdout.splitlines():
				parts = line.split()
				if int(parts[1]) == 38:
					assert int(parts[2]) == 3 and len(parts) == 9
					assert parts[3:5] == parts[7:9] and parts[3:5] != parts[5:7]
					proof.append(hashlib.sha256(line).hexdigest())
			assert len(proof) == 1 and not forbidden.exists()
			(a.runtime/'numeric-mutation.json').write_text(json.dumps(dict(category=38,
				name='unguarded-FP-to-integer', independent_stage=3, seal_independent=True,
				proof_line_sha256=proof[0]), indent=2)+'\n')
			v = run(['valgrind', '--default-suppressions=no', '--error-exitcode=97', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=definite,indirect,possible', a.component, '--nativeabi-mutations', a.mode, forbidden, source], 'numeric-guard-mutation-memory')
			memory(v.stderr)
		results.append(dict(name=name, source_sha256=sha(source), expected_exit=expected,
			native_sha256=sha(exe), C0_sha256=sha(c0), normal_leak_claim=expected == 0))
	(a.runtime/'result.json').write_text(json.dumps(dict(status='PASS', mode=a.mode,
		component_sha256=sha(a.component), cases=results, normal=3, fatal=8, counted_in_39=False,
		instrumented=instrumented, shared_emulator_deviation=shared_emulator_deviation,
		limits='Native host executions remain exact. Valgrind wide-u64-to-f32 numerical agreement is a named instrumentation deferral, independently reproduced with GCC and Clang; memory errors/lost bytes remain zero.'), indent=2)+'\n')
	print(a.mode, '3 explicit-conversion executions and 8 independent SIGILL edges passed')


if __name__ == '__main__':
	main()
