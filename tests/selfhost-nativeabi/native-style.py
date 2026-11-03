#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Run formatter-produced implicit scopes through the independent native stages."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT/'tests/selfhost-llvm'))
from oracle import memory

CASES = {
	'single-while': ('int step(int x){return x+1;}int main(){int x=0;while(x<5){x=step(x);}if(x!=5){return 1;}return 0;}\n', []),
	'owner-exits': ('int main(){owned int[] a=new int[2];int i=0;while(i<3){if(i==1){i=i+1;continue;}owned int[] b=new int[3];if(i==2){break;}i=i+1;}return 0;}\n', [('A', 2), ('A', 3), ('F', 3), ('A', 3), ('F', 3), ('F', 2)]),
	'floating-if': ('f64 absolute(f64 x){if(x<0.0d){return -x;}return x;}int main(){if(absolute(-1.25d)!=1.25d){return 1;}return 0;}\n', []),
}


def sha(path):
	return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
	p = argparse.ArgumentParser()
	for key in ('component', 'compiler', 'reference', 'binder', 'build', 'runtime', 'inputs'):
		p.add_argument('--'+key, type=Path, required=True)
	p.add_argument('--mode', choices=('O0', 'O2'), required=True)
	p.add_argument('--component-source-commit', help='explicit historical component source, when observing the pre-format binary')
	a = p.parse_args()
	assert all(not path.resolve().is_relative_to(ROOT) for path in (a.build, a.runtime, a.inputs))
	a.runtime.mkdir(parents=True, exist_ok=False); a.build.mkdir(parents=True, exist_ok=True); a.inputs.mkdir(parents=True, exist_ok=True)
	identity = json.loads(a.component.with_suffix('.identity.json').read_text()); assert sha(a.component) == identity['sha256']
	for name, digest in identity['identity']['sources'].items():
		path = Path(name)
		if a.component_source_commit and path.is_relative_to(ROOT):
			data = subprocess.check_output(['git', '-C', str(ROOT), 'show', a.component_source_commit+':'+path.relative_to(ROOT).as_posix()])
			assert hashlib.sha256(data).hexdigest() == digest
		else:
			assert sha(path) == digest
	assert sha(a.reference) == '30865ad8a9d1652b63ad882f1e29031c76ac13204212f822b44235cb07df10de'
	commands, results = [], []
	def frozen(name, data):
		path = a.inputs/name
		if path.exists():
			assert path.read_bytes() == data
		else:
			path.write_bytes(data)
		return path
	def run(argv, name):
		start = time.monotonic(); r = subprocess.run(list(map(str, argv)), capture_output=True, cwd=a.build, timeout=180)
		(a.runtime/(name+'.stdout')).write_bytes(r.stdout); (a.runtime/(name+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(name=name, argv=list(map(str, argv)), exit=r.returncode, monotonic_start=start, monotonic_end=time.monotonic()))
		(a.runtime/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
		assert r.returncode == 0, (name, r.returncode, r.stderr[-2000:])
		return r
	def abi_shape(data):
		rows = bytes.fromhex(data.decode().strip()).decode().splitlines()
		return [line.split()[:12] if line.startswith('FUNCTION ') else line.split() for line in rows]
	for name, (text, trace) in CASES.items():
		products, memories = {}, {}
		original = frozen(name+'.astra', text.encode())
		formatted = frozen(name+'-formatted.astra', run([a.compiler, '--format', original], name+'-format').stdout)
		assert original.read_bytes() != formatted.read_bytes()
		before = run([a.compiler, '--dump-syntax', original], name+'-before-AST').stdout
		assert before == run([a.compiler, '--dump-syntax', formatted], name+'-after-AST').stdout
		for label, source in [('before', original), ('formatted', formatted)]:
			run([a.binder, '--syntax', source], name+'-'+label+'-native-parse')
			obj = a.build/(name+'-'+label+'.o'); exe = obj.with_suffix('.exe')
			run([a.component, '--nativeabi-ssa', a.mode, a.runtime/'unused', source], name+'-'+label+'-SSA')
			run([a.component, '--emit-obj', a.mode, obj, source], name+'-'+label+'-emit')
			run(['gcc', obj, '-o', exe], name+'-'+label+'-link')
			r = run([exe], name+'-'+label+'-execute'); assert not r.stdout and not r.stderr
			v = run(['valgrind', '--default-suppressions=no', '--trace-malloc=yes', '--error-exitcode=97', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=definite,indirect,possible', exe], name+'-'+label+'-memory')
			memories[label] = memory(v.stderr, trace)
			products[label+'-object'] = dict(path=str(obj), sha256=sha(obj))
			products[label+'-executable'] = dict(path=str(exe), sha256=sha(exe))
			plan = run([a.component, '--abi-plan', a.mode, a.runtime/'unused', source], name+'-'+label+'-ABI').stdout
			if label == 'before':
				shape = abi_shape(plan)
			else:
				assert shape == abi_shape(plan), (name, 'physical ABI changed beyond source spans')
		ref = a.build/(name+'.C0')
		run([a.reference, '-'+a.mode, original, '-o', ref], name+'-C0-build')
		r = run([ref], name+'-C0-execute'); assert not r.stdout and not r.stderr
		v = run(['valgrind', '--default-suppressions=no', '--trace-malloc=yes', '--error-exitcode=97', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=definite,indirect,possible', ref], name+'-C0-memory')
		memories['C0'] = memory(v.stderr, trace)
		products['C0-executable'] = dict(path=str(ref), sha256=sha(ref))
		results.append(dict(name=name, original_sha256=sha(original), formatted_sha256=sha(formatted),
			AST_sha256=hashlib.sha256(before).hexdigest(), exact_physical_ABI_except_source_spans=True,
			expected_trace=trace, products=products, memory=memories))
		# Native parser admission for the restricted single-statement for grammar;
		# existing native semantic for-loop deferrals are not changed by this test.
	for_source = frozen('for-syntax.astra', b'int main(){int x=0;for(int i=0;i<3;i=i+1){x=x+1;}return x-3;}\n')
	for_formatted = frozen('for-syntax-formatted.astra', run([a.compiler, '--format', for_source], 'for-format').stdout)
	run([a.binder, '--syntax', for_formatted], 'native-for-parse')
	(a.runtime/'result.json').write_text(json.dumps(dict(status='PASS', mode=a.mode, counted_in_39=False,
		component_sha256=sha(a.component), formatter_sha256=sha(a.compiler), cases=results,
		limits='Only function source-span coordinates are omitted from the explicit ABI comparison; no runtime/ownership or scalar ABI facts are normalized.'), indent=2)+'\n')
	print(a.mode, 'actual native implicit-block parsing, SSA/ABI verification and owner effects matched C0')


if __name__ == '__main__':
	main()
