#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Fixed-cap duplicate, distinct, and true instance-exhaustion controls."""
import argparse
import json
from pathlib import Path
import subprocess
import time
from state import ROOT, BUILD, RUNTIME, read, sha


def verify(component):
	identity = read(component.with_suffix('.identity.json')); assert sha(component) == identity['sha256']
	for path, value in identity['identity']['tools'].items(): assert sha(path) == value
	for path, value in identity['identity']['sources'].items():
		path = Path(path)
		if sha(path) == value: continue
		# Original argv/sidecar remain byte-exact. The retained baseline supplies
		# bytes for a historical source path after live engineering has continued.
		assert component.parent.name == 'diagnostic-baseline' and path.is_relative_to(ROOT)
		assert sha(RUNTIME/'source-baseline'/path.relative_to(ROOT)) == value
	return identity


def main():
	p = argparse.ArgumentParser(); p.add_argument('--version', required=True); p.add_argument('--generate', action='store_true'); p.add_argument('--name'); a = p.parse_args()
	inputs = RUNTIME/'controls-input-v1'
	if a.generate:
		inputs.mkdir(exist_ok=False)
		noise = ''.join('struct Noise'+str(i)+' { int x; int y; int z; }\n' for i in range(12000))
		duplicate = noise+'T same<T>(T value) { return value; }\nint main() { int sum = 0;\n'+''.join('sum = sum + same<int>(1);\n' for _ in range(1000))+'return sum; }\n'
		distinct = noise+''.join('T unique'+str(i)+'<T>(T value) { return value; }\n' for i in range(128))+'int main() { int sum = 0;\n'+''.join('sum = sum + unique'+str(i)+'<int>(1);\n' for i in range(128))+'return sum; }\n'
		exhaust = ''.join('T unique'+str(i)+'<T>(T value) { return value; }\n' for i in range(257))+'int main() { int sum = 0;\n'+''.join('sum = sum + unique'+str(i)+'<int>(1);\n' for i in range(257))+'return sum; }\n'
		for name, source in [('duplicate', duplicate), ('distinct', distinct), ('exhaust', exhaust)]: (inputs/(name+'.astra')).write_text(source)
		(inputs/'identities.json').write_text(json.dumps({p.name:dict(bytes=p.stat().st_size, sha256=sha(p)) for p in inputs.glob('*.astra')}, indent=2)+'\n')
	component = BUILD/('diagnostic-'+a.version)/'resource-O0'; verify(component)
	name = a.name or a.version; assert name.replace('-', '').isalnum()
	leaf = RUNTIME/('controls-'+name); leaf.mkdir(exist_ok=False); results = {}
	for name in ('duplicate', 'distinct', 'exhaust'):
		path = inputs/(name+'.astra'); assert sha(path) == read(inputs/'identities.json')[path.name]['sha256']
		argv = [str(component), str(path)]; start = time.monotonic()
		with (leaf/(name+'.stdout')).open('xb') as out, (leaf/(name+'.stderr')).open('xb') as err:
			r = subprocess.run(['/usr/bin/time', '-v', '-o', leaf/(name+'.time'), *argv], stdout=out, stderr=err, cwd=ROOT, timeout=180)
		lines = (leaf/(name+'.stdout')).read_text().splitlines(); counts = [list(map(int, line.split()[1:])) for line in lines if line.startswith('GENCOUNTS ')]
		results[name] = dict(argv=argv, exit=r.returncode, counts=counts, diagnostics=[line for line in lines if line.startswith(('CHECKED_ERROR ', 'ERROR '))], events=[line for line in lines if line.startswith('GENEVENT ') and line.split()[2] in ('5','6','7')], start=start, end=time.monotonic(), component_sha256=sha(component), source_sha256=sha(path), stdout_sha256=sha(leaf/(name+'.stdout')))
		(leaf/'result.json').write_text(json.dumps(results, indent=2)+'\n'); print(name, results[name], flush=True)
	assert results['duplicate']['exit'] == 0 and results['duplicate']['counts'][0][3] == 1
	assert results['exhaust']['exit'] == 1 and results['exhaust']['counts'][0][3] == 256
	assert bytes.fromhex(results['exhaust']['diagnostics'][0].split()[4]).decode() == 'generic instance resource limit'
	if a.version != 'baseline': assert results['distinct']['exit'] == 0 and results['distinct']['counts'][0][3] == 128


if __name__ == '__main__':
	main()
