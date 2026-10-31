# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Production region lowering with scalar/bit/address/allocator observers."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]

def run(argv):
	result = subprocess.run([str(x) for x in argv], cwd=ROOT, capture_output=True, text=True, env=dict(os.environ, CCACHE_DISABLE='1'))
	assert result.returncode == 0, (argv, result.returncode, result.stdout, result.stderr)
	return result.stdout

def qualify(emitter, output):
	output.mkdir(parents=True, exist_ok=True)
	base = output/'generated'
	run([emitter, '--emit', base])
	ir = base.with_suffix('.ll').read_text()
	assert len(re.findall(r'call fastcc i32 %continuation.code', ir)) == 8
	assert len(re.findall(r'call fastcc void %continuation.code', ir)) == 3
	assert 'continuation.whole.move' in ir and 'continuation.runtime.code' in ir
	results = []
	for mode, flags in [('normal', None), ('preserved', ['-O0']), ('O2', ['-O2']), ('O2-fma', ['-O2', '-mfma'])]:
		obj = base.with_suffix('.o') if flags is None else output/(mode+'.o')
		if flags is not None:
			run(['clang', *flags, '-c', base.with_suffix('.ll'), '-o', obj])
		binary = output/mode
		run(['gcc', '-std=c11', '-Wall', '-Wextra', '-Werror', ROOT/'tests/callable-1/fixtures/observer.c', obj, '-Wl,--wrap=calloc', '-Wl,--wrap=free', '-o', binary])
		assembly = run(['objdump', '-dr', obj])
		(output/(mode+'.assembly')).write_text(assembly)
		if mode in ('normal', 'preserved'):
			assert len(re.findall(r'call\s+\*', assembly)) >= 11
		for flag in (0, 1):
			for seed in (3, 7, 11):
				trace = run([binary, flag, seed])
				name = f'{mode}-{flag}-{seed}'
				(output/(name+'.trace')).write_text(trace)
				allocs = re.findall(r'^A(\d+):(\d+):(\d+):(0x[0-9a-f]+)$', trace, re.M)
				assert [(a,b,c) for a,b,c,p in allocs] == [('1','1','40'),('2','3','4'),('3','1','40'),('4','3','4'),('5','1','4')]
				assert len({p for a,b,c,p in allocs[:4]}) == 4
				states = re.findall(r'^S([13]):.*:(0x[0-9a-f]+)$', trace, re.M)
				assert [a for a,p in states] == ['1','1','1','1','3']
				assert all(p == allocs[int(a)-1][3] for a,p in states)
				assert re.findall(r'^F(\d+)$', trace, re.M) == ['2','1','4','3','5']
				assert re.findall(r'^I:(-?\d+)$', trace, re.M) == [str(seed),str(seed*2),str(seed)]
				results.append({'case':name,'sha256':hashlib.sha256(trace.encode()).hexdigest(),'environment_addresses':[allocs[0][3],allocs[2][3]],'result':seed+(5 if flag else 6)})
		if mode in ('normal', 'preserved') and os.environ.get('CALLABLE_MEMCHECK') == '1':
			for flag in (0, 1):
				log = output/f'{mode}-{flag}-valgrind.log'
				run(['valgrind','--leak-check=full','--show-leak-kinds=all','--errors-for-leak-kinds=definite,indirect,possible','--error-exitcode=97',f'--log-file={log}',binary,flag,7])
				assert 'ERROR SUMMARY: 0 errors' in log.read_text() and 'All heap blocks were freed' in log.read_text()
	result = {'status':'PASS','native_cases':len(results),'indirect_invocations':8,'indirect_destructions':3,'modes':['normal','preserved','O2','O2-fma'],'observations':results}
	(output/'results.json').write_text(json.dumps(result,indent='\t')+'\n')
	print(json.dumps({'status':'PASS','native_cases':len(results),'indirect_invocations':8,'indirect_destructions':3}))

if __name__ == '__main__':
	qualify(Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve())
