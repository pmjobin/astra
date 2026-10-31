#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Native void callable prerequisites for typed foreign callbacks."""
from pathlib import Path
import hashlib
import itertools
import json
import os
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent


def sha(path):
	return hashlib.sha256(path.read_bytes()).hexdigest()


def main(compiler_arg, output_arg):
	compiler, output = Path(compiler_arg).resolve(), Path(output_arg).resolve()
	assert not output.is_relative_to(ROOT)
	output.mkdir(parents=True, exist_ok=True)
	work = Path(tempfile.mkdtemp(prefix='native-void-callables-', dir=output))
	receipt = dict(scope='native void Fn, closures and checked closures; typed foreign callback adapters remain pending',
		compiler_sha256=sha(compiler), checks=[], sources={})
	for path in [Path(__file__).resolve(), HERE/'native-callables.astra', HERE/'native-callables-client.c']:
		receipt['sources'][str(path.relative_to(ROOT))] = sha(path)
	def run(command, contains='', expected=0):
		assert sha(compiler) == receipt['compiler_sha256']
		result = subprocess.run(list(map(str, command)), cwd=work, capture_output=True, text=True,
			timeout=120, env=dict(os.environ, CCACHE_DISABLE='1', PYTHONDONTWRITEBYTECODE='1'))
		receipt['checks'].append(dict(command=list(map(str, command)), exit=result.returncode, expected_exit=expected,
			stdout=result.stdout, stderr=result.stderr))
		(work/'checks.json').write_text(json.dumps(receipt, indent='\t')+'\n')
		assert result.returncode == expected and contains in result.stdout+result.stderr, receipt['checks'][-1]
		return result.stdout
	def memcheck(binary):
		run(['valgrind', '--vgdb=no', '--default-suppressions=no', '--leak-check=full',
			'--show-leak-kinds=definite,indirect,possible', '--errors-for-leak-kinds=definite,indirect,possible',
			'--error-exitcode=99', binary], contains='ERROR SUMMARY: 0 errors')
	for stage in ['semantics', 'core', 'cfg', 'ssa', 'nabi', 'cabi']:
		run([compiler, '--dump-'+stage, HERE/'native-callables.astra'])
	for level in '012':
		obj = work/('native-O'+level+'.o'); binary = work/('native-O'+level)
		run([compiler, '-O'+level, '-c', HERE/'native-callables.astra', '-o', obj])
		run(['cc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread',
			HERE/'native-callables-client.c', obj, '-o', binary])
		run([binary], contains='PASS native void Fn and checked/ordinary closure effects')
		memcheck(binary)
	base = (HERE/'native-callables.astra').read_text()
	negatives = {
		'void-local': base.replace('code(value,2.5,true);', 'var invalid=code(value,2.5,true);'),
		'void-argument': base.replace('code(value,2.5,true);', 'observe(code(value,2.5,true),2.5);'),
		'void-return': base.replace('void apply(Fn<void,i32,f64,bool>', 'int apply(Fn<void,i32,f64,bool>').replace('code(value,2.5,true);', 'return code(value,2.5,true);'),
		'wrong-code-result': base.replace('Fn<void,i32,f64,bool>', 'Fn<i32,i32,f64,bool>'),
		'checked-void-local': base.replace('closure_invoke(code,delta);', 'var invalid=closure_invoke(code,delta);'),
		'checked-void-unhandled': base.replace('void checked_call(borrowed CheckedClosure<State,Fault,void,int> code,int delta) throws Fault', 'void checked_call(borrowed CheckedClosure<State,Fault,void,int> code,int delta)'),
		'owned-void-result': base.replace('Fn<void,i32,f64,bool>', 'Fn<owned void,i32,f64,bool>'),
		'moved-input-use': base.replace('code(move state);', 'code(move state);state.add(1);'),
	}
	for name, text in negatives.items():
		assert text != base
		unit = work/(name+'.astra'); unit.write_text(text)
		stage = 'cfg' if name == 'moved-input-use' else 'semantics'
		if stage == 'cfg':
			run([compiler, '--dump-semantics', unit])
		run([compiler, '--dump-'+stage, unit], contains='error:', expected=1)
		# No implementation source is available to the middle unit or final consumer.
	for levels in [*itertools.product('02', repeat=3), ('1','1','1')]:
		case = work/('units-'+''.join(levels)); case.mkdir()
		leaf = case/'leaf.astra'; leaf.write_text('namespace VoidLeaf;\nvoid dispatch(Fn<void,i32,f64,bool> code,int value){code(value,2.5,true);}\n')
		middle = case/'middle.astra'; middle.write_text('namespace VoidMiddle;\nvoid relay(Fn<void,i32,f64,bool> code,int value){VoidLeaf.dispatch(code,value);}\n')
		consumer = case/'consumer.astra'; consumer.write_text('[CImport(name="callables16_observe")]void observe(i32 value,f64 scale);\nvoid emit(i32 value,f64 scale,bool enabled){if(enabled){observe(value,scale);}}\nexport(C) int run(){VoidMiddle.relay(emit,7);return 0;}\n')
		client = case/'client.c'; client.write_text('#include <stdint.h>\n#include <assert.h>\n#include <stdio.h>\nstatic int calls;\nvoid callables16_observe(int32_t value,double scale){assert(value==7 && scale==2.5);++calls;}\nextern int32_t run(void);int main(void){assert(run()==0 && calls==1);puts("PASS opaque void callable units");return 0;}\n')
		for index, (source, module, name, imports) in enumerate([(leaf,'VoidLeaf','dispatch',[]),(middle,'VoidMiddle','relay',[case/'leaf.asti'])]):
			run([compiler, '-O'+levels[index], '-c', '--module', module, '--native-export', module+'.'+name,
				'--emit-interface', source.with_suffix('.asti'), *[item for path in imports for item in ['--import-module',path]],
				source, '-o', source.with_suffix('.o')])
			source.unlink()
		run([compiler, '-O'+levels[2], '-c', '--import-module', case/'middle.asti', consumer, '-o', case/'consumer.o'])
		binary = case/'client'
		run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', client,
			case/'consumer.o', case/'middle.o', case/'leaf.o', '-o', binary])
		run([binary], contains='PASS opaque void callable units')
		if levels in [('0','2','0'), ('2','0','2')]:
			memcheck(binary)
	receipt['status'] = 'NATIVE_VOID_CALLABLE_INTEGRATION_PASS'
	(work/'checks.json').write_text(json.dumps(receipt, indent='\t')+'\n')
	print(json.dumps(dict(status=receipt['status'], commands=len(receipt['checks']), receipt=str(work/'checks.json'))))


if __name__ == '__main__':
	main(*sys.argv[1:])
