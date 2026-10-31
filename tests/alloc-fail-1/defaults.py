# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Exact old-stage, object and dependency compatibility when the clause is absent."""
from pathlib import Path
import hashlib
import json
import os
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
CASES = {
	'array-free': 'int main(){return 0;}',
	'scalar': 'int main(){var a=new int[2];a[1]=7;return a[1]-7;}',
	'floating': 'int main(){var a=new f64[2];a[1]=3.5d;if(a[0]!=0.0d||a[1]!=3.5d){return 1;}return 0;}',
	'vector': 'int main(){var a=new f32<4>[2];f32<4> x={1.0f,2.0f,3.0f,4.0f};a[1]=x;var saved=a[1];if(saved[3]!=4.0f){return 1;}return 0;}',
	'mask': 'int main(){var a=new bool<16>[2];var x=a[1];if(any(x)){return 1;}return 0;}',
	'record': 'struct R{u8 x;f64 y;}int main(){var a=new R[2];a[1].x=7;var saved=a[1];release a;return (saved.x as int)-7;}',
	'field': 'class C{owned int[] a;init(){this.a=new int[2];}void replace(){this.a=new int[3];}}int main(){var c=C.init();c.replace();return len(c.a)-3;}',
	'return': 'owned int[] make(int n){return new int[n];}owned int[] forward(int n){return make(n);}int main(){var a=forward(2);release a;a=new int[0];return len(a);}',
	'generic': 'owned T[] make<T>(int n){return new T[n];}int main(){var a=make<int>(2);var b=make<int>(3);return len(a)+len(b)-5;}',
	'clone': 'int main(){var a=new int[2];a[0]=7;a=clone_array(a);var b=filled_array(2,9);var c=clone_array(b);return a[0]+c[1]-16;}',
}
STAGES = ['syntax', 'semantics', 'core', 'instances', 'cfg', 'ssa', 'nabi', 'cabi', 'llvm']


def qualify(baseline, candidate, out):
	out.mkdir(parents=True, exist_ok=False)
	(out / 'tmp').mkdir()
	env = dict(os.environ, TMPDIR=str(out / 'tmp'), CCACHE_DISABLE='1')
	rows = []
	def run(argv):
		p = subprocess.run(list(map(str, argv)), cwd=out, env=env, capture_output=True)
		assert p.returncode == 0 and not p.stderr, p
		return p.stdout
	for name in ['slices', 'buffers']:
		(out / (name + '.astra')).write_bytes((ROOT / 'lib/astra/base' / (name + '.astra')).read_bytes())
	for name, source in CASES.items():
		(out / (name + '.astra')).write_text(source + '\n')
		files = (['slices.astra', 'buffers.astra'] if name == 'clone' else []) + [name + '.astra']
		for stage in STAGES:
			a = run([baseline, '--dump-' + stage, *files])
			b = run([candidate, '--dump-' + stage, *files])
			(out / (name + '.' + stage)).write_bytes(a)
			assert a == b, (name, stage)
			rows.append(dict(case=name, stage=stage, sha256=hashlib.sha256(a).hexdigest()))
		for label, compiler in [('baseline', baseline), ('candidate', candidate)]:
			run([compiler, *files, '-o', name + '-' + label])
			assert run([out / (name + '-' + label)]) == b''
		assert (out / (name + '-baseline')).read_bytes() == (out / (name + '-candidate')).read_bytes(), name
		(out / (name + '.symbols')).write_bytes(run(['nm', '-u', out / (name + '-candidate')]))
	(out / 'results.json').write_text(json.dumps(dict(stages=rows, exact_executables=list(CASES), baseline_sha256=hashlib.sha256(baseline.read_bytes()).hexdigest(), candidate_sha256=hashlib.sha256(candidate.read_bytes()).hexdigest()), indent='\t') + '\n')
	print('90 byte-identical default stages and 10 byte-identical executables; normal runs agree')


if __name__ == '__main__':
	sys.dont_write_bytecode = True
	sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tools/qualification'))
	from output_paths import fresh_output
	sys.argv[-1] = str(fresh_output(sys.argv[-1]))
	qualify(*[Path(arg).resolve() for arg in sys.argv[1:]])
