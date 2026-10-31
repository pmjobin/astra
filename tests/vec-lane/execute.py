# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Exact vector value oracle and observable evaluation-order execution."""
from pathlib import Path
import json
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ['splat', 'extract', 'insert', 'shuffle', 'select', 'lane-f32', 'lane-loop', 'lane-ownership', 'lane-values']


def bindings():
	return [arg for name in ['types', 'api'] for arg in ['--vapi', ROOT / f'tests/resource/fixtures/resource-{name}.vapi']]


def run(argv):
	result = subprocess.run([str(arg) for arg in argv], cwd=ROOT, capture_output=True, text=True)
	assert result.returncode == 0 and result.stdout == result.stderr == '', (argv, result)


def main(compiler, companion, oracle, out):
	out.mkdir(parents=True, exist_ok=True)
	for name in FIXTURES:
		source = ROOT / f'tests/vec-lane/fixtures/vec-{name}.astra'
		options = [*bindings(), '--link-object', companion] if name == 'lane-ownership' else []
		run([compiler, source, *options, '-o', out / name])
		run([out / name])
	result = subprocess.run([str(oracle)], capture_output=True, text=True, check=True)
	assert result.stderr == ''
	match = re.search(r'oracle shapes=(\d+) cases=(\d+) lane_checks=(\d+) identity_checks=(\d+)', result.stdout)
	assert match
	counts = dict(zip(['shapes', 'cases', 'lane_checks', 'identity_checks'], map(int, match.groups())))
	source = out / 'oracle.astra'
	source.write_text(result.stdout)
	run([compiler, source, '-o', out / 'oracle'])
	run([out / 'oracle'])
	barriers = '''struct Log{int x;}
int touch(Log* log,int n){log->x=n;return n;}
int main(){
	Log log={x=7};
	int<4> v=insert(splat(log.x,4),2,touch(&log,9));
	if(v[0]!=7 || v[1]!=7 || v[2]!=9 || v[3]!=7 || log.x!=9){return 1;}
	log.x=0;
	int<4> a=select(splat(log.x==0,4),splat(touch(&log,2),4),splat(touch(&log,3),4));
	if(a[0]!=2 || a[3]!=2 || log.x!=3){return 2;}
	log.x=4;
	int<4> b=select(splat(true,4),splat(log.x,4),splat(touch(&log,5),4));
	if(b[0]!=4 || b[3]!=4 || log.x!=5){return 3;}
	return 0;
}
'''
	source = out / 'order-barriers.astra'
	source.write_text(barriers)
	run([compiler, source, '-o', out / 'order-barriers'])
	run([out / 'order-barriers'])
	traps = {
		'splat-before-effect': 'select(splat(1/z==0,4),splat(effect(),4),splat(1,4))',
		'insert-before-replacement': 'insert(splat(1/z,4),0,effect())',
		'shuffle-source': 'shuffle(splat(1/z,4),3,2,1,0)',
		'select-true-before-false': 'select(splat(true,4),splat(1/z,4),splat(effect(),4))',
		'select-eager-false': 'select(splat(true,4),splat(1,4),splat(1/z,4))',
	}
	for name, expression in traps.items():
		source = out / (name + '.astra')
		source.write_text('extern(C) void abort(); int effect(){abort();return 1;} int main(){int z=0;int<4> v=' + expression + ';return 0;}\n')
		run([compiler, source, '-o', out / name])
		result = subprocess.run([str(out / name)], capture_output=True)
		assert result.returncode == -4 and result.stdout == result.stderr == b'', (name, result)
	results = {'fixtures': len(FIXTURES), 'oracle': counts, 'operand_capture_barriers': 3, 'trap_order_and_eager_false': list(traps)}
	(out / 'results.json').write_text(json.dumps(results, indent='\t') + '\n')
	print(json.dumps(results), flush=True)


if __name__ == '__main__':
	main(*(Path(arg).resolve() for arg in sys.argv[1:]))
