"""Read-only qualification/conservation verifier; does not build or run tests."""
from pathlib import Path
import datetime
import hashlib
import json
import re
import stat
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[2]
BASE='f799990886184cb79d2892350c8631f16aad18e2'


def identity(path):
	path=Path(path)
	return dict(bytes=path.stat().st_size,sha256=hashlib.sha256(path.read_bytes()).hexdigest())


def git(*args):
	return subprocess.check_output(['git',*args],cwd=ROOT,text=True).strip()


def main(build,runtime,output):
	build,runtime,output=map(lambda p:Path(p).resolve(),[build,runtime,output])
	compiler=identity(build/'astrac'); components=build/'tests/numerical-optimization-11'
	routing=json.loads((build/'meson-info/meson-info.json').read_text())['directories']
	assert Path(routing['source']).resolve()==ROOT and Path(routing['build']).resolve()==build
	subprocess.run(['git','merge-base','--is-ancestor',BASE,'HEAD'],cwd=ROOT,check=True)
	assert not git('diff','--name-only','--','bootstrap','lib/astra','meson.build','meson.options')
	build_receipt=runtime/'n9-selected-build-3.json'; built=json.loads(build_receipt.read_text()); assert built['exit']==0
	for name,expected in built['source'].items():assert identity(ROOT/name)['sha256']==expected,name
	test_command=runtime/'n9-final-test-command.json'; command=json.loads(test_command.read_text())
	assert command['exit']==0 and command['compiler_sha256']==compiler['sha256']
	selection=(ROOT/'tests/numerical-optimization-11/regression-selection.txt').read_text().splitlines()
	meson_path=build/'meson-logs/surge-11-final.json'; meson=[json.loads(line) for line in meson_path.read_text().splitlines()]
	assert len(selection)==len(meson)==137 and all(row['result']=='OK' for row in meson)
	assert {row['name'].split(':',1)[-1] for row in meson}==set(selection)
	tap=sum(int(match[1]) for row in meson if (match:=re.search(r'^1\.\.(\d+)\s*$',row['stdout'],re.M)))
	assert tap==507
	names=['policies','memory','unit-policies','portability',*[f'a{i}' for i in range(85,92)],*[f'a{i}' for i in range(93,97)],'ablation','simd-cost','sanitizers','memory-audit','packet-checked']
	rows=[]; commands=0; valgrind=0; compact=[]
	for name in names:
		path=components/name/(name+'.json'); data=json.loads(path.read_text())
		assert data['status']=='PASS' and data['compiler']['sha256']==compiler['sha256'],name
		assert all(row['exit']==row['expected_exit'] for row in data['commands']),name
		for source,expected in data['frozen_inputs'].items():assert identity(source)=={key:expected[key] for key in ('bytes','sha256')},source
		for product in data['files']:assert identity(product['path'])=={key:product[key] for key in ('bytes','sha256')},product['path']
		count=sum(Path(row['command'][0]).name=='valgrind' for row in data['commands']); commands+=len(data['commands']);valgrind+=count
		rows.append(dict(name=name,path=str(path),identity=identity(path),commands=len(data['commands']),valgrind_commands=count))
		compact.append(dict(name=name,compiler=data['compiler'],frozen_inputs=data['frozen_inputs'],files=data['files'],commands=[dict(
			command=row['command'],exit=row['exit'],expected_exit=row['expected_exit'],seconds=row['seconds'],environment_overrides=row['environment_overrides'],
			stdout_text_sha256=hashlib.sha256(row['stdout'].encode()).hexdigest(),stderr_text_sha256=hashlib.sha256(row['stderr'].encode()).hexdigest(),
			stdout_tail=row['stdout'][-512:],stderr_tail=row['stderr'][-512:]) for row in data['commands']]))
	timer_path=components/'timer-continuity/results.json';timer=json.loads(timer_path.read_text())
	assert timer['status']=='PASS' and timer['compiler_sha256']==compiler['sha256']
	assert len(timer['commands'])==11 and all(row['passed'] for row in timer['commands'])
	for name,expected in timer['sources'].items():assert identity(ROOT/name)['sha256']==expected,name
	allocation=json.loads((components/'ablation/measurements.json').read_text())
	assert set(allocation['apps'])=={'89','91','93','94'}
	for app,row in allocation['apps'].items():
		for mode in ('off','on'):
			assert len(row['modes'][mode]['warm_process_seconds']['samples'])==11
			assert len(row['modes'][mode]['compile_seconds']['samples'])==3
			assert all(len(value['samples'])==7 for value in row['modes'][mode]['hardware_counters'].values())
		if app in ('89','91'):assert row['machine_identical']
		else:assert row['modes']['off']['allocation_calls']==row['work_items'] and row['modes']['on']['allocation_calls']==0
	policy={path.name:json.loads(path.read_text()) for path in sorted((components/'policies').glob('*errors.json'))}
	assert policy['fma-errors.json']['fused_observations']>=1
	checked_packet=json.loads((components/'packet-checked/packet-checked.json').read_text())
	assert checked_packet['checked_failures']==425 and checked_packet['allocation_calls']>=48000
	pipeline_identical=identity(components/'a95/a95-O2-off')==identity(components/'a95/a95-O2-on')
	assert pipeline_identical
	preserved_path=runtime/'intake-preservation.json'; preserved=json.loads(preserved_path.read_text())
	for category in ('user','hooks'):
		for name,expected in preserved[category].items():
			path=ROOT/name; assert dict(mode=stat.S_IMODE(path.stat().st_mode),**identity(path))==expected,name
	assert git('stash','list')==preserved['commands']['git stash list']['output'].strip()
	old=dict(line.split(' ',1) for line in preserved['commands']['git for-each-ref --format=%(refname) %(objectname)']['output'].splitlines())
	current=dict(line.split(' ',1) for line in git('for-each-ref','--format=%(refname) %(objectname)').splitlines())
	branch='refs/heads/'+git('branch','--show-current');assert old.keys()==current.keys() and all(old[key]==current[key] for key in old if key!=branch)
	assert len(preserved['user'])==17 and len(preserved['hooks'])==15
	sources={name:identity(ROOT/name)['sha256'] for name in git('ls-files','--','bootstrap','lib/astra','tests/numerical-optimization-11','examples/numerical-optimization-11','meson.build','meson.options').splitlines()}
	command_output=output.with_name('numerical-optimization-11-command-evidence.json')
	command_output.write_text(json.dumps(dict(scope='Current numerical recipe commands and file identities; stdout/stderr are text hashes and bounded tails.',recipes=compact,timer=timer),indent=2,sort_keys=True)+'\n')
	assert command_output.stat().st_size<2*1024**2,'compact command evidence exceeds publisher per-file cap'
	result=dict(status='PASS',scope='Surge 11 finite N1-N9 domains; selected Linux x86-64 qualification',
		generated_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),base_commit=BASE,
		qualified_head=git('rev-parse','HEAD'),qualified_tree=git('rev-parse','HEAD^{tree}'),
		compiler_source_commit=git('log','-1','--format=%H','--','bootstrap','lib/astra','meson.build','meson.options'),compiler=compiler,
		source_digest=hashlib.sha256(json.dumps(sources,sort_keys=True,separators=(',',':')).encode()).hexdigest(),sources=sources,
		build=dict(receipt=str(build_receipt),identity=identity(build_receipt),targets=len(built['targets']),routing=routing),
		regressions=dict(receipt=str(meson_path),identity=identity(meson_path),command_receipt=str(test_command),command_identity=identity(test_command),passed=len(meson),tap_subtests=tap,names=selection),
		current_recipes=rows,recipe_commands=commands,recipe_valgrind_commands=valgrind,
		command_evidence=dict(path=str(command_output.relative_to(ROOT)),identity=identity(command_output)),
		timer=dict(path=str(timer_path),identity=identity(timer_path),top_level_commands=11,generated=timer['generated'],valgrind=timer['valgrind'],liburing=timer['liburing']),
		floating_error_tables=policy,controlled_ablations=allocation,
		pipeline_machine_identical=pipeline_identical,checked_packet=dict(failures=425,allocation_calls=checked_packet['allocation_calls']),
		simd_cost=json.loads((components/'simd-cost/measurements.json').read_text()),
		preservation=dict(receipt=str(preserved_path),identity=identity(preserved_path),user_files=17,hooks=15,stash='unchanged',unrelated_refs='unchanged',worktrees=git('worktree','list','--porcelain')),
		gates={name:'PASS within documented finite profile' for name in [f'N{i}' for i in range(1,10)]},
		limits=['137 selected registrations, not the complete 9302-entry registry or all historical applications.',
		'A89/A91/A95 optimized on/off executables are byte-identical; measured short-run variation is not an optimization gain or regression.',
		'A93/A94 gains belong to the new semantic optimization group; no universal or isolated-pass speedup claim.',
		'Scalar-source PCM is independently executed; LLVM also vectorizes it at O2.',
		'ASan instruments emitted Astra LLVM and C; UBSan instruments C; system libraries are uninstrumented.',
		'Linux no-libc is executed; AArch64 is OBJECT_ONLY; no no-OS, SH-4, Dreamcast or self-hosting execution claim.',
		'Historical LAZY-1 Q4 remains HELD/INCOMPLETE. Surges12-14 remain required and outside this acceptance.'])
	output.write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
	print(f'PASS: {len(meson)} selected registrations, {tap} TAP subtests, {len(rows)} current recipes, {commands} recipe commands, {valgrind} Valgrind commands plus timer.')


if __name__=='__main__':main(*sys.argv[1:])
