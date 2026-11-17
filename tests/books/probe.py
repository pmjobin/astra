#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Retained authoring experiments; outcomes do not qualify book examples."""
import json
import os
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT.parent/'codex/work/astra'
sys.path.insert(0,str(ROOT/'tests/selfhost-ownership-syntax-27b'))
from support import execute, output_path, sha, write


def main():
	runtime = output_path(Path(sys.argv[1]),WORK/'runtime')
	runtime.mkdir(parents=True,exist_ok=False)
	identity = json.loads((WORK/'runtime/selfhost27c-dev21/build-identity.json').read_text())
	env = dict(os.environ,PYTHONDONTWRITEBYTECODE='1')
	env.update({k:v for k,v in identity['environment'].items() if v is not None})
	product = json.loads((WORK/'runtime/api-docs28a1-products.json').read_text())['products']['O2']
	assert sha(product['path']) == product['sha256']
	base = Path(__file__).with_name('values.astra').read_text()
	owners = Path(__file__).with_name('owners.astra').read_text()
	shared = Path(__file__).with_name('shared.astra').read_text()
	cases = {
		'no-const':base.replace('const LIMIT = 6;','').replace('i < LIMIT','i < 6'),
		'no-chain':base.replace('0 < total < 20','0 < total && total < 20'),
		'no-continue':base.replace('if (i == 2) continue;','if (i == 2) { continue; }'),
		'no-small-compound':base.replace('wrapped += 1;','wrapped = wrapped + 1;'),
		'no-const-or-small-compound':base.replace('const LIMIT = 6;','').replace('i < LIMIT','i < 6').replace('wrapped += 1;','wrapped = wrapped + 1;'),
		'minimal-loop':'language astra27b; int main() { int total = 0; for (int i = 0; i < 6; i += 1) { total += i; } return total+27; }',
		'minimal-chain':'language astra27b; int main() { int value = 2; if (0 < value < 4) return 42; return 1; }',
		'explicit-owner-result':owners.replace('Reading make_reading','owned Reading make_reading'),
		'no-property':owners.replace('return reading.doubled;','return reading.value*2;'),
		'shared-no-view':shared.replace('var view = shared_borrow(upgraded);\n\treturn view.value;','return shared_read(upgraded);')+'\nint shared_read(shared Reading value) { return read(shared_borrow(value)); }\nint read(Reading value) { return value.value; }\n',
		'array-foreach':'language astra27b; int main() { int[2] values = {20,22}; int total = 0; foreach (var value in values) { total += value; } return total; }',
	}
	results = []
	for name,text in cases.items():
		source = runtime/(name+'.astra'); source.write_text(text)
		r = execute([product['path'],'--check',source],runtime/name,env=env)
		err = (runtime/name/'stderr').read_text()
		results.append(dict(name=name,source_sha256=sha(source),result=r,diagnostic=err))
		print(name,r['exit'],err.strip(),flush=True)
	write(runtime/'result.json',dict(status='AUTHORING_OBSERVATIONS_ONLY',cases=results))


if __name__ == '__main__':
	main()
