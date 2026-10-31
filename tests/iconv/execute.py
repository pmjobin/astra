# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Compare native scalar/vector conversions with the exact integer value oracle."""
from pathlib import Path
import json
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ['scalar', 'vector', 'control', 'fields', 'ownership', 'values']


def bindings():
	return [arg for name in ['types', 'api'] for arg in ['--vapi', ROOT / f'tests/resource/fixtures/resource-{name}.vapi']]


def run(argv):
	result = subprocess.run([str(arg) for arg in argv], cwd=ROOT, capture_output=True, text=True)
	assert result.returncode == 0 and result.stdout == result.stderr == '', (argv, result)


def main(compiler, companion, oracle, out):
	out.mkdir(parents=True, exist_ok=True)
	for name in FIXTURES:
		source = ROOT / f'tests/iconv/fixtures/iconv-{name}.astra'
		options = [*bindings(), '--link-object', companion] if name == 'ownership' else []
		run([compiler, source, *options, '-o', out / name])
		run([out / name])
	result = subprocess.run([str(oracle), '--emit-runtime'], capture_output=True, text=True, check=True)
	assert result.stderr == ''
	match = re.search(r'oracle scalar_checks=(\d+) vector_shapes=(\d+) vector_cases=(\d+) vector_lane_checks=(\d+)', result.stdout)
	assert match
	counts = dict(zip(['scalar_checks', 'vector_shapes', 'vector_cases', 'vector_lane_checks'], map(int, match.groups())))
	source = out / 'oracle.astra'
	source.write_text(result.stdout)
	run([compiler, source, '-o', out / 'oracle'])
	run([out / 'oracle'])
	# The conversion is total, but operand division retains its earlier trap
	# and may not be moved after the next argument's observable abort call.
	traps = {
		'operand-before-next-argument': 'consume((1/z) as u8,effect())',
		'previous-argument-before-conversion': 'consume((1/z) as u8,effect() as i16 as int)',
	}
	for name, expression in traps.items():
		source = out / (name + '.astra')
		source.write_text('extern(C) void abort(); int effect(){abort();return 1;} int consume(u8 x,int y){return 0;} int main(){int z=0;return ' + expression + ';}\n')
		run([compiler, source, '-o', out / name])
		result = subprocess.run([str(out / name)], capture_output=True)
		assert result.returncode == -4 and result.stdout == result.stderr == b'', (name, result)
	results = {'fixtures': len(FIXTURES), 'oracle': counts, 'trap_order': list(traps), 'shuffle_commutation_cases': counts['vector_cases'], 'select_commutation_cases': counts['vector_cases']}
	(out / 'results.json').write_text(json.dumps(results, indent='\t') + '\n')
	print(json.dumps(results), flush=True)


if __name__ == '__main__':
	main(*(Path(arg).resolve() for arg in sys.argv[1:]))
