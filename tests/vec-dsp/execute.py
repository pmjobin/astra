# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Execute the DSP fixtures and compare native operations with scalar authorities."""
from pathlib import Path
import json
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ['sat-scalar', 'sat-vector', 'widen', 'pack-wrap', 'pack-sat', 'interleave', 'f32', 'loop', 'order', 'ownership', 'values']


def bindings():
	return [arg for name in ['types', 'api'] for arg in ['--vapi', ROOT / f'tests/resource/fixtures/resource-{name}.vapi']]


def run(argv):
	result = subprocess.run([str(arg) for arg in argv], cwd=ROOT, capture_output=True, text=True)
	assert result.returncode == 0 and result.stdout == result.stderr == '', (argv, result)


def main(compiler, companion, oracle, out):
	out.mkdir(parents=True, exist_ok=True)
	for name in FIXTURES:
		source = ROOT / f'tests/vec-dsp/fixtures/dsp-{name}.astra'
		options = [*bindings(), '--link-object', companion] if name == 'ownership' else []
		run([compiler, source, *options, '-o', out / name])
		run([out / name])
	result = subprocess.run([str(oracle)], capture_output=True, text=True, check=True)
	assert result.stderr == ''
	match = re.search(r'// oracle (.*)', result.stdout)
	assert match
	counts = {key: int(value) for key, value in re.findall(r'(\w+)=(\d+)', match[1])}
	source = out / 'oracle.astra'
	source.write_text(result.stdout)
	run([compiler, source, '-o', out / 'oracle'])
	run([out / 'oracle'])
	# Operand traps precede later effects; saturation itself is total.
	traps = {
		'sat-add': 'sat_add(1/z,effect())',
		'sat-sub': 'sat_sub(1/z,effect())',
		'widen': 'widen_low(splat(1/z,4),u32)[0] as int',
		'pack': 'pack_sat(splat(1/z,4),splat(effect(),4),u8)[0] as int',
		'interleave': 'interleave_high(splat(1/z,4),splat(effect(),4))[0]',
	}
	# Widen requires a narrower source, while keeping division before its cast.
	traps['widen'] = 'widen_low(splat((1/z) as i16,4),u32)[0] as int'
	for name, expression in traps.items():
		source = out / ('trap-' + name + '.astra')
		source.write_text('extern(C) void abort(); int effect(){abort();return 1;} int main(){int z=0;return ' + expression + ';}\n')
		run([compiler, source, '-o', out / ('trap-' + name)])
		result = subprocess.run([str(out / ('trap-' + name))], capture_output=True)
		assert result.returncode == -4 and result.stdout == result.stderr == b'', (name, result)
	results = {'fixtures': len(FIXTURES), 'oracle': counts, 'trap_order': list(traps)}
	(out / 'results.json').write_text(json.dumps(results, indent='\t') + '\n')
	print(json.dumps(results), flush=True)


if __name__ == '__main__':
	main(*(Path(arg).resolve() for arg in sys.argv[1:]))
