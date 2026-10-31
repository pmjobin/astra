#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Distinct borrowed native callback code/context views."""
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
	work = Path(tempfile.mkdtemp(prefix='native-callback-views-', dir=output))
	receipt = dict(scope='native borrowed callback code/context carriers and opaque native units; foreign matrices are separate',
		compiler_sha256=sha(compiler), checks=[], sources={})
	for path in [Path(__file__).resolve(), HERE/'callback-views.astra', HERE/'callback-views-client.c']:
		receipt['sources'][str(path.relative_to(ROOT))] = sha(path)
	def run(command, contains='', expected=0):
		assert sha(compiler) == receipt['compiler_sha256']
		result = subprocess.run(list(map(str, command)), cwd=work, capture_output=True, text=True,
			timeout=120, env=dict(os.environ, CCACHE_DISABLE='1', PYTHONDONTWRITEBYTECODE='1'))
		receipt['checks'].append(dict(command=list(map(str, command)), exit=result.returncode, expected_exit=expected,
			stdout=result.stdout, stderr=result.stderr))
		(work/'checks.json').write_text(json.dumps(receipt, indent='\t')+'\n')
		assert result.returncode == expected and contains in result.stdout+result.stderr, receipt['checks'][-1]
		assert 'CRITICAL' not in result.stderr, receipt['checks'][-1]
		return result.stdout
	def memcheck(binary):
		run(['valgrind', '--vgdb=no', '--default-suppressions=no', '--leak-check=full',
			'--show-leak-kinds=definite,indirect,possible', '--errors-for-leak-kinds=definite,indirect,possible',
			'--error-exitcode=99', binary], contains='ERROR SUMMARY: 0 errors')
	for stage in ['semantics', 'core', 'cfg', 'ssa', 'nabi', 'cabi']:
		run([compiler, '--dump-'+stage, HERE/'callback-views.astra'])
	for level in '012':
		obj = work/('native-O'+level+'.o'); binary = work/('native-O'+level)
		run([compiler, '-O'+level, '-c', HERE/'callback-views.astra', '-o', obj])
		run(['cc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread',
			HERE/'callback-views-client.c', obj, '-o', binary])
		run([binary], contains='PASS distinct native callback code/context views')
		memcheck(binary)
	base = (HERE/'callback-views.astra').read_text()
	negatives = {
		'unmanaged-callback': base.replace('borrowed Callback', 'Callback'),
		'owned-callback': base.replace('borrowed Callback', 'owned Callback'),
		'copied-local': base.replace('return apply(code);', 'var local=code;return apply(local);'),
		'explicit-local': base.replace('return apply(code);', 'Callback<i64,i32,u32,i64,u64,f32,f64,bool> local=code;return apply(local);'),
		'callback-field': base + '\nclass Storage{Callback<int,int> code;}\n',
		'callback-property': base + '\nclass Storage{property Callback<int,int> code{get{return code;}}}\n',
		'callback-result': base + '\nCallback<int,int> bad(borrowed Callback<int,int> code){return code;}\n',
		'callback-scalar-kind': base.replace('Callback<bool,bool>', 'Callback<bool,u8>'),
		'callback-record': base + '\nstruct Record{int value;}void bad(borrowed Callback<void,Record> code){}\n',
		'wrong-result': base.replace('Callback<i64,i32', 'Callback<f64,i32'),
		'raw-fn-substitution': base + '\nvoid plain(Fn<void,int> code){}void bad(borrowed Callback<void,int> code){plain(code);}\n',
	}

	for name, text in negatives.items():
		assert text != base
		unit = work/(name+'.astra'); unit.write_text(text)
		run([compiler, '--dump-semantics', unit], contains='error:', expected=1)
		# The same compiler handles an empty argument list without a fake result or data argument in source.
	zero = base.replace('void notify(int value){seen(value);}', 'void notify(){seen(19);}')
	zero = zero.replace('Callback<void,i32>', 'Callback<void>').replace('code(19);', 'code();')
	unit = work/'zero.astra';unit.write_text(zero)
	for level in '012':
		obj = work/('zero-O'+level+'.o');binary = work/('zero-O'+level)
		run([compiler, '-O'+level, '-c', unit, '-o', obj])
		run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-pedantic', HERE/'callback-views-client.c', obj, '-o', binary])
		run([binary], contains='PASS distinct native callback code/context views')
		memcheck(binary)
		# No implementation source is available to the middle unit or final consumer.
	for levels in [*itertools.product('02', repeat=3), ('1','1','1')]:
		case = work/('units-'+''.join(levels)); case.mkdir()
		leaf = case/'leaf.astra'; leaf.write_text('namespace CallbackLeaf;\nvoid dispatch(borrowed Callback<void,i32,f64,bool> code,int value){code(value,2.5,true);}\n')
		middle = case/'middle.astra'; middle.write_text('namespace CallbackMiddle;\nvoid relay(borrowed Callback<void,i32,f64,bool> code,int value){CallbackLeaf.dispatch(code,value);}\n')
		consumer = case/'consumer.astra'; consumer.write_text('[CImport(name="callbackviews16_observe")]void observe(i32 value,f64 scale);\nclass Context{int bias;init(int bias){this.bias=bias;}}\nvoid emit(borrowed Context context,i32 value,f64 scale,bool enabled){if(enabled){observe(value+context.bias,scale);}}\nexport(C) int run(){var context=new Context(3);var callback=closure_bind(move context,emit);CallbackMiddle.relay(callback,4);return 0;}\n')
		client = case/'client.c'; client.write_text('#include <stdint.h>\n#include <assert.h>\n#include <stdio.h>\nstatic int calls;\nvoid callbackviews16_observe(int32_t value,double scale){assert(value==7 && scale==2.5);++calls;}\nextern int32_t run(void);int main(void){assert(run()==0 && calls==1);puts("PASS opaque typed callback units");return 0;}\n')
		for index, (source, module, name, imports) in enumerate([(leaf,'CallbackLeaf','dispatch',[]),(middle,'CallbackMiddle','relay',[case/'leaf.asti'])]):
			run([compiler, '-O'+levels[index], '-c', '--module', module, '--native-export', module+'.'+name,
				'--emit-interface', source.with_suffix('.asti'), *[item for path in imports for item in ['--import-module',path]],
				source, '-o', source.with_suffix('.o')])
			source.unlink()
		run([compiler, '-O'+levels[2], '-c', '--import-module', case/'middle.asti', consumer, '-o', case/'consumer.o'])
		binary = case/'client'
		run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', client,
			case/'consumer.o', case/'middle.o', case/'leaf.o', '-o', binary])
		run([binary], contains='PASS opaque typed callback units')
		if levels in [('0','2','0'), ('2','0','2')]:
			memcheck(binary)
	receipt['status'] = 'NATIVE_CALLBACK_VIEW_INTEGRATION_PASS'
	(work/'checks.json').write_text(json.dumps(receipt, indent='\t')+'\n')
	print(json.dumps(dict(status=receipt['status'], commands=len(receipt['checks']), receipt=str(work/'checks.json'))))


if __name__ == '__main__':
	main(*sys.argv[1:])
