#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Source-bound actual LLVM IR/object/executable and independent C0 qualification."""
import argparse
from collections import Counter
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time
from oracle import inspect, memory


def sha(path):
	return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
	p = argparse.ArgumentParser()
	for key in ('component', 'compiler', 'build', 'runtime', 'frozen'):
		p.add_argument('--'+key, type=Path, required=True)
	p.add_argument('--mode', choices=('O0','O2'), required=True)
	p.add_argument('--case', action='append')
	p.add_argument('--development', action='store_true')
	a = p.parse_args()
	a.runtime.mkdir(parents=True, exist_ok=False)
	a.build.mkdir(parents=True, exist_ok=True)
	if not a.development:
		identity = json.loads(a.component.with_suffix('.identity.json').read_text())
		assert sha(a.component) == identity['sha256']
		assert all(sha(path) == h for path, h in identity['identity']['sources'].items())
	assert sha(a.compiler) == '30865ad8a9d1652b63ad882f1e29031c76ac13204212f822b44235cb07df10de'
	commands = []
	results = []
	def run(argv, name, expected=0, timeout=60):
		start = time.monotonic()
		try:
			r = subprocess.run(['/usr/bin/time','-v','-o',str(a.runtime/(name+'.time')),*map(str,argv)], capture_output=True, cwd=a.build, timeout=timeout, env=dict(os.environ, CCACHE_DISABLE='1'))
		except subprocess.TimeoutExpired as error:
			commands.append(dict(argv=list(map(str,argv)), timeout=timeout, stdout_sha256=hashlib.sha256(error.stdout or b'').hexdigest(), monotonic_start=start, monotonic_end=time.monotonic()))
			(a.runtime/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
			raise
		(a.runtime/(name+'.stdout')).write_bytes(r.stdout); (a.runtime/(name+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(argv=list(map(str,argv)), exit=r.returncode, monotonic_start=start, monotonic_end=time.monotonic(), stdout_sha256=hashlib.sha256(r.stdout).hexdigest(), stderr_sha256=hashlib.sha256(r.stderr).hexdigest()))
		(a.runtime/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
		assert r.returncode == expected, (name, r.returncode, expected, r.stderr[-2200:].decode(errors='replace'))
		return r
	items = json.loads((a.frozen/'selection.json').read_text())
	for item in items:
		name = item['name']
		if a.case and name not in a.case:
			continue
		source = Path(item['source_path'])
		assert sha(source) == item['source_sha256']
		product = a.build/(name+'-'+a.mode)
		paths = dict(raw=product.with_suffix('.raw.ll'), ir=product.with_suffix('.ll'), object=product.with_suffix('.o'), executable=product, reference=product.with_suffix('.c0'))
		ssa = run([a.component,'--ssa',source], name+'-ssa').stdout
		for stage, key in [('--llvm-raw','raw'),('--llvm-ir','ir'),('--emit-obj','object')]:
			run([a.component,stage,a.mode,paths[key],source], name+'-'+key)
		facts = inspect(paths['raw'].read_bytes(), ssa)
		run(['llvm-as',paths['raw'],'-o',product.with_suffix('.bc')], name+'-parse-raw')
		run(['opt','-passes=verify','-disable-output',paths['ir']], name+'-verify-ir')
		elf = run(['readelf','-h',paths['object']], name+'-elf').stdout
		assert b'ELF64' in elf and b'REL (Relocatable file)' in elf and b'Advanced Micro Devices X86-64' in elf
		symbols = run(['nm','-a',paths['object']], name+'-symbols').stdout
		assert b' T main' in symbols
		undefined = run(['nm','-u',paths['object']], name+'-undefined').stdout.decode()
		assert all(line.split()[-1] in {'calloc','free','_GLOBAL_OFFSET_TABLE_'} for line in undefined.splitlines())
		run(['objdump','-dr',paths['object']], name+'-disassembly')
		link = ['gcc', paths['object'], '-o', product]
		run(link, name+'-link')
		actual = run([product], name+'-execute', item['expected_exit'])
		assert actual.stdout.decode() == item['expected_stdout'] and actual.stderr.decode() == item['expected_stderr']
		run([a.compiler,'-'+a.mode,source,'-o',paths['reference']], name+'-c0-compile')
		reference = run([paths['reference']], name+'-c0-execute', item['expected_exit'])
		assert (reference.stdout,reference.stderr) == (actual.stdout,actual.stderr)
		memories = {}
		for label, exe in [('native',product),('C0',paths['reference'])]:
			v = run(['valgrind','--default-suppressions=no','--trace-malloc=yes','--error-exitcode=97','--leak-check=full','--show-leak-kinds=all','--errors-for-leak-kinds=definite,indirect,possible',exe],name+'-memory-'+label,item['expected_exit'])
			assert v.stdout == actual.stdout
			memories[label] = memory(v.stderr, item['expected_trace'])
		assert memories['native']['observed_trace'] == memories['C0']['observed_trace']
		results.append(dict(**item, mode=a.mode, component_sha256=sha(a.component), c0_sha256=sha(a.compiler), ssa_sha256=hashlib.sha256(ssa).hexdigest(), products={k:dict(path=str(v),sha256=sha(v),bytes=v.stat().st_size) for k,v in paths.items()}, facts=facts, memory=memories, link=list(map(str,link)), result='PASS'))
		(a.runtime/'results.json').write_text(json.dumps(results,indent=2)+'\n')
		print(name,a.mode,'PASS',flush=True)
	if not a.case:
		assert len(results) == 24 and Counter(x['category'] for x in results) == dict(numeric=6,branch=4,loop=4,call=4,ownership=4,extra=2)
	(a.runtime/'result.json').write_text(json.dumps(dict(status='DEVELOPMENT' if a.development else 'PASS', executions=len(results), mode=a.mode, cases=results),indent=2)+'\n')


if __name__ == '__main__':
	main()
