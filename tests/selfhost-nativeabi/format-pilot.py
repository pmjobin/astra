#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Actual formatter/parser/ownership pilot; all generated files are external."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import time


def main():
	p = argparse.ArgumentParser()
	for key in ('compiler', 'reference', 'runtime'):
		p.add_argument('--' + key, type=Path, required=True)
	a = p.parse_args()
	root = Path(__file__).resolve().parents[2]
	sys.path.insert(0, str(root/'tests/selfhost-llvm'))
	from oracle import memory
	assert not a.runtime.resolve().is_relative_to(root)
	a.runtime.mkdir(parents=True, exist_ok=False)
	rows = []
	def run(argv, label, expected=0):
		start = time.monotonic()
		r = subprocess.run(list(map(str, argv)), capture_output=True, cwd=a.runtime, timeout=120)
		(a.runtime/(label+'.stdout')).write_bytes(r.stdout)
		(a.runtime/(label+'.stderr')).write_bytes(r.stderr)
		rows.append(dict(argv=list(map(str, argv)), label=label, exit=r.returncode,
			monotonic_start=start, monotonic_end=time.monotonic()))
		(a.runtime/'commands.json').write_text(json.dumps(rows, indent=2)+'\n')
		assert r.returncode == expected, (label, r.returncode, r.stderr.decode())
		return r.stdout
	cases = {
		'controls': 'int step(int x){return x+1;}int main(){int x=0;for(int i=0;i<3;i=i+1){x=step(x);}while(x<5){x=x+1;}if(x!=5){return 1;}return 0;}',
		'ownership': 'int main(){owned int[] a=new int[2];int i=0;while(i<3){if(i==1){i=i+1;continue;}owned int[] b=new int[3];if(i==2){break;}i=i+1;}return 0;}',
		'comments': 'struct A{int x;}\n// next declaration\nstruct B{int y;}\nclass C{int x;init(){this.x=1;}int read(){if(this.x!=0){return this.x;}return 0;}}\nint main(){string s="{ // exact }";/* exact */return 0;}',
		'else-scope': 'int main(){int x=1;if(x==1){if(x!=1){return 1;}}else{x=2;}if(x!=1){int y=3;x=y;}return x-1;}',
	}
	for name, text in cases.items():
		original = a.runtime/(name+'.astra'); original.write_text(text+'\n')
		formatted = a.runtime/(name+'-formatted.astra')
		before = original.read_bytes()
		formatted.write_bytes(run([a.compiler, '--format', original], name+'-format'))
		assert run([a.compiler, '--format', formatted], name+'-repeat') == formatted.read_bytes()
		run([a.compiler, '--format', '--check', formatted], name+'-check')
		assert original.read_bytes() == before
		ast = run([a.reference, '--dump-syntax', original], name+'-reference-AST')
		assert ast == run([a.compiler, '--dump-syntax', original], name+'-candidate-AST')
		assert ast == run([a.compiler, '--dump-syntax', formatted], name+'-formatted-AST')
		for mode in ('O0', 'O2'):
			for label, compiler, source in [('before', a.reference, original), ('after', a.compiler, formatted)]:
				exe = a.runtime/(name+'-'+mode+'-'+label)
				run([compiler, '-'+mode, source, '-o', exe], exe.name+'-build')
				assert run([exe], exe.name+'-execute') == b''
				if name == 'ownership':
					label = exe.name+'-memory'
					run(['valgrind', '--default-suppressions=no', '--trace-malloc=yes', '--error-exitcode=97', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=definite,indirect,possible', exe], label)
					memory((a.runtime/(label+'.stderr')).read_bytes(), [('A', 2), ('A', 3), ('F', 3), ('A', 3), ('F', 3), ('F', 2)])
		if name == 'controls':
			assert b'if(x!=5) return 1;' in formatted.read_bytes()
			assert b'while(x<5) x=x+1;' in formatted.read_bytes()
		if name == 'else-scope':
			assert b'}else{' in formatted.read_bytes()
			assert b'\n\t\tint y=3;' in formatted.read_bytes()
	# Neither local declarations nor nested controls can become implicit scopes.
	for i, text in enumerate(['int main(){if(true) int x=1;return 0;}',
		'int main(){if(true) if(false) return 1;else{return 0;}return 0;}']):
		bad = a.runtime/('bad-'+str(i)+'.astra'); bad.write_text(text+'\n')
		run([a.compiler, '--format', bad], 'bad-'+str(i), expected=1)
	(a.runtime/'result.json').write_text(json.dumps(dict(status='PASS', cases=list(cases),
		compiler_sha256=hashlib.sha256(a.compiler.read_bytes()).hexdigest(),
		reference_sha256=hashlib.sha256(a.reference.read_bytes()).hexdigest(),
		checks=len(rows)), indent=2)+'\n')
	print('formatter pilot: AST, execution, ownership and syntax refusal passed')


if __name__ == '__main__':
	main()
