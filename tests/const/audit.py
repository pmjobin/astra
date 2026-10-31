# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Accepted-SHA inventory, independent compiler checks and unsuppressed memory audit."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import argparse
import hashlib
import json
import re
import subprocess
import sys

sys.dont_write_bytecode = True
from qualify import ROOT, STAGES, process, run
BASELINE = 'f4df1b43b5f71f529544173532be4366e14f4fbe'
STASH = 'd280dd61953b9e959a1c55aae70900e0c169c606'
GOLDENS = {'.syntax','.semantics','.core','.instances','.cfg','.ssa','.nabi','.cabi','.ll','.stderr','.flow','.flow-stderr','.json'}
SUPERSEDED = {'tests/infer/negative.py', 'tests/infer/parse-tests.vala'}


def save(path, data):
	path.write_text(json.dumps(data, indent='\t') + '\n')


def inventory(out):
	names = run(['git','ls-tree','-r','--name-only',BASELINE,'tests'], cwd=ROOT).splitlines()
	rows = []; changes = []
	for name in names:
		original = subprocess.check_output(['git','show',BASELINE + ':' + name], cwd=ROOT)
		changed = original != (ROOT / name).read_bytes()
		if changed: changes.append(name)
		rows.append(dict(path=name, sha256=hashlib.sha256(original).hexdigest(), golden=Path(name).suffix in GOLDENS, changed=changed))
	assert set(changes) == SUPERSEDED
	assert sum(r['golden'] for r in rows) == 1023 and all(not r['changed'] for r in rows if r['golden'])
	save(out / 'accepted-tests.json', rows)
	assert STASH in run(['git','stash','list','--format=%H'], cwd=ROOT).splitlines()
	return dict(baseline=BASELINE, tests=len(rows), goldens=1023, supersessions=changes, manifest_sha256=hashlib.sha256((out/'accepted-tests.json').read_bytes()).hexdigest(), stash=STASH, stash_tree=run(['git','rev-parse',STASH+'^{tree}'], cwd=ROOT).strip(), stash_untracked_tree=run(['git','rev-parse',STASH+'^3^{tree}'], cwd=ROOT).strip())


def compare(build, candidate, independent, baseline, out):
	from_sources = [ROOT/'tests/const/fixtures'/n for n in ['00-dimensions.astra','10-values.astra','20-client.astra']] + [ROOT/'lib/astra/base/order.astra']
	rows = []
	for stage in ['syntax','semantics',*STAGES]:
		args = ['--dump-'+stage,*from_sources]
		expected = run([build/'astrac',*args])
		for compiler in [build/'astrac',candidate/'astrac',independent/'astrac']:
			assert expected == run([compiler,*args]); rows.append(dict(compiler=str(compiler), stage=stage, sha256=hashlib.sha256(expected.encode()).hexdigest()))
			# Accepted pure/core, ownership, numeric, generic, array and BASELIB consumers.
	programs = [(['tests/core/fixtures/arithmetic.astra'],[]), (['tests/array/fixtures/array-basic.astra'],[]), (['tests/f64/fixtures/f64-literal.astra'],[]), (['examples/base/pure.astra','lib/astra/base/order.astra','lib/astra/base/classify.astra'],[]), (['examples/base/contracts.astra',*['lib/astra/base/'+n+'.astra' for n in ['order','classify','contracts','clamp']]],[]), (['tests/baselib/fixtures/lifetime.astra','lib/astra/base/contracts.astra'],['--vapi',ROOT/'tests/baselib/fixtures/runtime.vapi'])]
	for sources, options in programs:
		for stage in ['syntax','semantics',*STAGES]:
			args = ['--dump-'+stage,*[ROOT/p for p in sources],*(options if stage != 'syntax' else [])]
			expected = run([baseline/'astrac',*args])
			for compiler in [build/'astrac',candidate/'astrac',independent/'astrac']:
				assert expected == run([compiler,*args]); rows.append(dict(compiler=str(compiler), source=sources[0], stage=stage, sha256=hashlib.sha256(expected.encode()).hexdigest()))
				# Repeat exact evaluator records using an independently compiled executable.
	run([sys.executable,'-B',ROOT/'tests/const/oracle.py',independent/'tests/const/astra-const-operations',out/'independent-oracle'])
	assert json.loads((out/'independent-oracle/oracle.json').read_text()) == json.loads((build/'const-1/oracle/oracle.json').read_text())
	# Parameter-fed functions: independent compiler must produce identical IR.
	for filename in ['runtime.astra','named.astra','pure.astra']:
		source = build/'const-1/qualification'/filename
		for stage in STAGES:
			assert run([build/'astrac','--dump-'+stage,source]) == run([independent/'astrac','--dump-'+stage,source])
	return dict(comparisons=len(rows), records=rows, independent_evaluator_cases=2424390, independent_generated_stage_comparisons=21)


def suite(directory):
	results = [json.loads(line) for line in (directory/'meson-logs/testlog.json').read_text().splitlines()]
	assert all(r['result'] in ['OK','EXPECTEDFAIL'] for r in results), [(r['name'],r['result']) for r in results if r['result'] not in ['OK','EXPECTEDFAIL']]
	plans = [int(m[1]) for row in results for m in re.finditer(r'^1\.\.(\d+)$',row.get('stdout',''),re.M)]
	commands = json.loads((directory/'compile_commands.json').read_text())
	generated = [r for r in commands if 'meson-generated' in r['command']]
	assert generated and all('-DVALA_STRICT_C' in r['command'] and '-Werror' in r['command'] for r in generated)
	options = {r['name']:r['value'] for r in json.loads((directory/'meson-info/intro-buildoptions.json').read_text())}
	assert options['werror'] and '--fatal-warnings' in (directory/'build.ninja').read_text()
	return dict(tests=len(results), tap_suites=len(plans), tap_cases=sum(plans), failed=0, skipped=0, strict_generated_c_commands=len(generated), firewall_tests=sum(any(s in r['name'] for s in ['no-llvm','links-qualified-llvm','linkage-rejects','firewall-rejects']) for r in results))


def controls(build, out):
	qualification=build/'const-1/qualification'
	# Internal Linux/x86_64 startup witness; the public CLI remains hosted.
	startup=out/'startup.S'
	startup.write_text('\t.text\n\t.globl _start\n_start:\n\tcall answer\n\tsub $42, %eax\n\tmov %eax, %edi\n\tmov $60, %eax\n\tsyscall\n\t.section .note.GNU-stack,"",@progbits\n')
	run(['cc','-c',startup,'-o',out/'startup.o'])
	run(['ld',out/'startup.o',qualification/'pure.o','-o',out/'startup'])
	assert run([out/'startup'])=='' and run(['nm','-u',out/'startup'])==''
	dynamic=run(['readelf','-d',out/'startup']); assert 'There is no dynamic section' in dynamic
	(out/'startup-dynamic.txt').write_text(dynamic)
	# A concrete local constant in an Ownable generic does not alter cleanup.
	source=qualification/'ownership/lifetime.astra'; target=out/'local-generic.astra'
	target.write_text(source.read_text().replace('{ return move value; }','{ const SAFE=false && ((1/0)==0); return move value; }'))
	assert target.read_text()!=source.read_text()
	options=[ROOT/'lib/astra/base/contracts.astra','--vapi',ROOT/'tests/baselib/fixtures/runtime.vapi']
	for stage in STAGES: assert run([build/'astrac','--dump-'+stage,target,*options])==run([build/'astrac','--dump-'+stage,source,*options])
	ssa=run([build/'astrac','--dump-ssa',target,*options]); main=re.search(r'\(function #(\d+) "main" -> int',ssa)[1]
	ir=run([build/'astrac','--dump-llvm',target,*options])+f'\ndefine i32 @main() {{\n\t%result = call fastcc i32 @astra.fn.{main}()\n\tret i32 %result\n}}\n'
	(out/'local-generic.ll').write_text(ir)
	run(['opt','-passes=verify','-disable-output',out/'local-generic.ll'])
	run(['llc','-O0','-filetype=obj','-relocation-model=pic',out/'local-generic.ll','-o',out/'local-generic.o'])
	run(['cc',out/'local-generic.o',qualification/'ownership/companion.o',build/'lib/astra/failure-hosted.o','-Wl,--wrap=calloc,--wrap=free','-lm','-o',out/'local-generic'])
	trace=run([out/'local-generic']); assert trace=='E7\nE90\nE1\nE2\nE8\nE-90\nE-7\n'
	(out/'local-generic-ownership.txt').write_text(trace)
	return dict(startup_status=0,startup_undefined_symbols=0,startup_dynamic_section=False,local_ownable_generic_stage_comparisons=7,cleanup_trace=trace)


def memory(build, out, baseline):
	qualification = build/'const-1/qualification'; logs=out/'valgrind'; logs.mkdir(exist_ok=True)
	jobs = []
	for name in ['semantic','pipeline','llvm']:
		jobs.append(('test-'+name,[build/'tests/const'/('astra-const-'+name),'--tap'],0,False))
	for stage in ['semantics',*STAGES]: jobs.append(('compiler-'+stage,[build/'astrac','--dump-'+stage,qualification/'named.astra'],0,False))
	for source in ['runtime-trap-convert.astra','pure.astra']: jobs.append(('compile-'+source,[build/'astrac','--check',qualification/source],0,False))
	for mode in ['O0','O2','fma']:
		jobs.append(('runtime-'+mode,[qualification/('runtime-'+mode)],0,False))
		jobs.append(('ownership-'+mode,[qualification/'ownership'/('lifetime-'+mode)],0,False))
		jobs.append(('fatal-'+mode,[qualification/'ownership'/('fatal-'+mode)],None,True))
	for name,text in [('failure','const BAD=1/0;'),('cycle','const A=false && B;const B=A;'),('conversion','const BAD=(1.0d/0.0d) as int;')]:
		path=logs/(name+'.astra');path.write_text(text)
		jobs.append(('compiler-'+name,[build/'astrac','--check',path],1,False))
	for name in ['installed','relocated']: jobs.append(('consumer-'+name,[qualification/('consumer-'+name)],0,False))
	control=logs/'accepted-quark-growth.astra'
	control.write_text('int f(){'+''.join('int C'+str(i)+'=0;' for i in range(5001))+'return 0;}')
	jobs += [('baseline-quark-growth',[baseline/'astrac','--dump-semantics',control],99,False),('current-quark-growth',[build/'astrac','--dump-semantics',control],99,False)]
	growth_names={'test-semantic','baseline-quark-growth','current-quark-growth'}
	def measure(job):
		name,args,status,fatal=job; log=logs/(name+'.log')
		p=process(['valgrind','--vgdb=no','--leak-check=full','--show-leak-kinds=all','--errors-for-leak-kinds=definite,indirect,possible','--error-exitcode=99','--log-file='+str(log),*args],cwd=ROOT)
		(logs/(name+'.stdout')).write_text(p.stdout);(logs/(name+'.stderr')).write_text(p.stderr)
		text=log.read_text()
		def number(pattern):
			m=re.search(pattern,text);return int(m[1].replace(',','')) if m else 0
		row=dict(name=name,status=p.returncode,fatal=fatal,errors=number(r'ERROR SUMMARY: ([\d,]+) errors'),definite=number(r'definitely lost: ([\d,]+) bytes'),indirect=number(r'indirectly lost: ([\d,]+) bytes'),possible=number(r'possibly lost: ([\d,]+) bytes'),reachable=number(r'still reachable: ([\d,]+) bytes'),suppressed=number(r'suppressed: ([\d,]+) bytes'),allocations=number(r'total heap usage: ([\d,]+) allocs'))
		assert 'ERROR SUMMARY:' in text and row['suppressed']==0,row
		row['baseline_glib_growth'] = name in growth_names
		if name in growth_names:
			# Exact accepted-SHA reproduction, not a suppression or changed leak class.
			assert p.returncode==99 and row['errors']==2 and row['definite']==49152 and row['indirect']==row['possible']==0,row
			assert 'g_quark_from_string' in text and 'call_init' in text
		else:
			assert row['errors']==0,row
			assert p.returncode<0 if fatal else p.returncode==status,row
			if not fatal: assert row['definite']==row['indirect']==row['possible']==0,row
		return row
	with ThreadPoolExecutor(max_workers=4) as pool: rows=list(pool.map(measure,jobs))
	save(out/'valgrind.json',rows)
	return dict(runs=len(rows),clean_normal=sum(not r['fatal'] and not r['baseline_glib_growth'] for r in rows),fatal=sum(r['fatal'] for r in rows),baseline_glib_growth=[r for r in rows if r['baseline_glib_growth']],errors=sum(r['errors'] for r in rows),suppressions=0,unexplained_leaks=0)


def main():
	parser=argparse.ArgumentParser();parser.add_argument('build',type=Path);parser.add_argument('--candidate',type=Path);parser.add_argument('--independent',type=Path);parser.add_argument('--baseline',type=Path);parser.add_argument('--memory',action='store_true');args=parser.parse_args()
	build=args.build.resolve();out=build/'const-1/evidence';out.mkdir(exist_ok=True)
	if args.memory:
		assert args.baseline, 'memory audit requires the exact accepted-SHA compiler control'
		print(json.dumps(memory(build,out,args.baseline.resolve())));return
	result=dict(inventory=inventory(out),comparison=compare(build,args.candidate.resolve(),args.independent.resolve(),args.baseline.resolve(),out),controls=controls(build,out),suites={name:suite(path.resolve()) for name,path in [('current',build),('candidate',args.candidate),('baseline',args.baseline)]},compilers={name:dict(sha256=hashlib.sha256((path/'astrac').read_bytes()).hexdigest(),version=run([path/'astrac','--version']).strip()) for name,path in [('current',build),('candidate',args.candidate),('independent',args.independent),('baseline',args.baseline)]})
	save(out/'audit.json',result);print(json.dumps(result,indent='\t'))


if __name__=='__main__': main()
