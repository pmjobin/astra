# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Verify and compact actual final receipts; never build, commit or publish."""
from pathlib import Path
import hashlib
import json
import os
import platform
import re
import shutil
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[2]


def sha(path):
	value=hashlib.sha256()
	with Path(path).open('rb') as stream:
		for block in iter(lambda:stream.read(1048576),b''):
			value.update(block)
	return value.hexdigest()


def digest(value):
	return hashlib.sha256(json.dumps(value,sort_keys=True,ensure_ascii=True,separators=(',',':')).encode()).hexdigest()


def identity(path):
	path=Path(path).resolve()
	return dict(path=str(path),bytes=path.stat().st_size,sha256=sha(path))


def git(*arguments):
	return subprocess.check_output(['git',*arguments],cwd=ROOT,text=True).strip()


def output(value):
	value=value or ''
	return dict(bytes=len(value.encode()),sha256=hashlib.sha256(value.encode()).hexdigest(),
		text=value if len(value)<=1800 else value[:1800]+'\n[complete output in raw external receipt]')


def protect(initial):
	for name,expected in initial['untracked'].items():
		path=ROOT/name
		assert oct(path.lstat().st_mode)==expected['mode'] and path.stat().st_size==expected['bytes'] and sha(path)==expected['sha256'],name
		assert (os.readlink(path) if path.is_symlink() else None)==expected['symlink'],name
	hooks=Path(git('rev-parse','--git-path','hooks'))
	if not hooks.is_absolute():
		hooks=ROOT/hooks
	actual={p.name:dict(mode=oct(p.lstat().st_mode),sha256=sha(p)) for p in hooks.iterdir() if p.is_file()}
	assert actual==initial['hooks'],'hook drift'
	refs=lambda text:{line.split()[1]:line.split()[0] for line in text.splitlines() if not line.endswith(' refs/heads/astra-lazy-1')}
	assert refs(git('show-ref'))==refs(initial['refs']),'unrelated ref drift'
	assert git('stash','list')==initial['stash'].strip(),'stash drift'
	assert git('diff','--cached')==initial['index_diff'].strip(),'initial staged work drift'
	assert git('worktree','list','--porcelain').split('\n\n')[1:]==initial['worktrees'].strip().split('\n\n')[1:],'peer drift'
	return dict(status='PRESERVED',files=initial['untracked'],hooks=actual,unrelated_refs=refs(initial['refs']),
		stash_sha256=digest(initial['stash']),peer_worktree_sha256=digest(initial['worktrees'].strip().split('\n\n')[1:]))


def compact_receipt(path,compiler_hash):
	data=json.loads(path.read_text())
	assert data.get('status','PASS') in ['PASS','PASS_APPLICATION'],path
	assert data.get('compiler_sha256',data.get('compiler',{}).get('sha256') if isinstance(data.get('compiler'),dict) else None)==compiler_hash,path
	sources=data.get('sources',{})
	for source,expected in sources.items():
		assert sha(ROOT/source)==expected,('stale source',source)
	for product,expected in data.get('products',{}).items():
		assert sha(product)==expected,('stale product',product)
	for file in data.get('files',[]):
		assert identity(file['path'])==file,('stale file',file)
	commands=data.get('checks',data.get('commands',[]))
	assert commands,path
	compact=[]
	memory=0
	for command in commands:
		argv=command.get('command',command.get('argv'))
		actual=command.get('actual_exit',command.get('exit'))
		expected=command['expected_exit']
		assert actual==expected and command.get('passed',True),command
		if Path(argv[0]).name=='valgrind':
			memory+=1
			assert all(text in command['stderr'] for text in ['ERROR SUMMARY: 0 errors','in use at exit: 0 bytes in 0 blocks','(suppressed: 0 from 0)']),command
		entry=dict(argv_sha256=digest(argv),expected_exit=expected,actual_exit=actual,
			output_sha256=digest([command.get('stdout',''),command.get('stderr','')]))
		if Path(argv[0]).name=='valgrind' or Path(argv[0]).is_absolute() and Path(argv[0]).is_relative_to(path.parent):
			entry['runtime_argv']=argv
			if len(command.get('stdout',''))<=2048:
				entry['observed_stdout']=command.get('stdout','')
		compact.append(entry)
	return dict(raw_receipt=identity(path),application=data.get('application'),profile=data.get('profile'),
		commands=compact,command_count=len(commands),unsuppressed_zero_error_zero_live_byte_valgrind=memory,
		sources=sources,products=data.get('products',{}),files=data.get('files',[]),file_inputs=data.get('file_inputs',{}),
		async_provider_sha256=data.get('async_provider_sha256'),instrumentation=data.get('instrumentation'))


def compact_legacy(path,compiler_hash):
	data=json.loads(path.read_text())
	assert data.get('status','PASS')=='PASS',path
	compiler=data.get('compiler')
	assert data.get('compiler_sha256',compiler.get('sha256') if isinstance(compiler,dict) else None)==compiler_hash,path
	files={}
	for field in ['sources','source_sha256','source_hashes']:
		if not isinstance(data.get(field),dict):
			continue
		for name,expected in data[field].items():
			if isinstance(expected,str):
				file=ROOT/name;assert sha(file)==expected,('legacy source drift',file)
				files[str(file)]=expected
	products={}
	for name,expected in data.get('products',{}).items():
		file=path.parent/name
		digest_value=expected['sha256'] if isinstance(expected,dict) else expected
		assert sha(file)==digest_value,('legacy product drift',file)
		products[str(file)]=digest_value
	commands=[];memory=[]
	for row in data.get('checks',data.get('commands',data.get('records',[]))):
		argv=row.get('command',row.get('argv'))
		expected=row.get('expected_exit',row.get('expected'))
		assert row.get('passed',True) and (expected is None or row['exit']==expected),row
		commands.append(dict(argv_sha256=digest(argv),expected_exit=expected,actual_exit=row['exit']))
		if Path(argv[0]).name=='valgrind':
			stderr=bytes.fromhex(row['stderr_hex']).decode(errors='replace') if 'stderr_hex' in row else row.get('stderr','')
			memory.append(re.findall(r'(?:definitely lost|indirectly lost|possibly lost|still reachable|ERROR SUMMARY|in use at exit):[^\n]*',stderr))
	return dict(raw_receipt=identity(path),commands=commands,sources=files,products=products,memory_observations=memory,
		sanitizer_probes=data.get('sanitizer_probes'),gcc_sanitizer_limitation=data.get('gcc_sanitizer_limitation'),sanitizer_qualification=data.get('sanitizer_qualification'))


def main(build_path,runtime_path,destination):
	build,runtime,destination=map(lambda p:Path(p).resolve(),[build_path,runtime_path,destination])
	assert destination.is_relative_to(ROOT)
	compiler=identity(build/'astrac')
	intake=json.loads((runtime/'pm-next-intake.json').read_text())
	assert intake['base_commit']=='959c47cb31cc7847150752ab26615545953a3400' and not intake.get('published')
	initial=json.loads((runtime/'initial-state.json').read_text())
	conservation=protect(initial)
	build_command=json.loads((runtime/'g9-final-build-command.json').read_text())
	test_command=json.loads((runtime/'g9-final-test-command.json').read_text())
	timer_command=json.loads((runtime/'g9-final-timer-command.json').read_text())
	for kind,command in [('build',build_command),('test',test_command),('timer',timer_command)]:
		command.setdefault('log_path',str(runtime/('g9-final-'+kind+'.log')))
		assert command['actual_exit']==command['expected_exit']==0,command
		assert sha(Path(command['log_path']))==command['log_sha256']
	assert build_command['compiler_after_sha256']==compiler['sha256']
	assert test_command['compiler_sha256']==timer_command['compiler_sha256']==compiler['sha256']
	assert git('merge-base','--is-ancestor',build_command['head'],'HEAD')==''
	index=runtime/'g9-source-index.json'
	assert sha(index)==build_command['source_index_sha256']
	for name,expected in json.loads(index.read_text()).items():
		assert sha(ROOT/name)==expected,('qualified input changed',name)
	options={row['name']:row['value'] for row in json.loads((build/'meson-info/intro-buildoptions.json').read_text())}
	assert options['werror'] is True and options['linux_async'] is False
	routing=json.loads((build/'meson-info/meson-info.json').read_text())['directories']
	assert routing['source']==str(ROOT) and routing['build']==str(build)
	selected=json.loads((ROOT/'tests/language-generalization-10/integration-tests.json').read_text())
	meson=build/'meson-logs/surge-10-final.json'
	rows=[json.loads(line) for line in meson.read_text().splitlines() if line.strip()]
	assert len(rows)==len(selected) and {row['name'].split(':',1)[-1] for row in rows}==set(selected)
	assert all(row['result']=='OK' and row['returncode']==0 and not row['is_fail'] for row in rows)
	assert all(row['starttime']>=test_command['started_epoch']-2 for row in rows),'inherited Meson result'
	app_rows=[row for row in rows if re.fullmatch(r'astra:language-generalization-10-application-a\d\d',row['name'])]
	assert len(app_rows)==12
	base=build/'tests/language-generalization-10'
	fresh=[]
	for name in ['checks.json','a82.json','boundaries.json']:
		for path in base.rglob(name):
			if test_command['started_epoch']<=path.stat().st_mtime<=test_command['finished_epoch']+2:
				fresh.append(path)
	assert len(fresh)==22,('expected nine public language components, twelve apps and one boundary recipe',len(fresh),fresh)
	receipts=[compact_receipt(path,compiler['sha256']) for path in sorted(fresh)]
	assert {row['application'] for row in receipts if row['application']}=={f'a{n}' for n in range(73,85)}
	for name in ['minimal','numeric','volatile','arena','portability']:
		path=build/'tests/systems-dsp-9'/name/(name+'.json')
		assert path.stat().st_mtime>=test_command['started_epoch']
		receipts.append(compact_receipt(path,compiler['sha256']))
	legacy=[]
	for family in ['gobject','signals','gir']:
		paths=[path for path in (build/'tests/ecosystem-abi-8'/family).rglob('checks.json') if path.stat().st_mtime>=test_command['started_epoch']]
		assert len(paths)==1,(family,paths)
		legacy.append(compact_legacy(paths[0],compiler['sha256']))
	for family in ['checked','retained','record','payload','importer']:
		path=build/'tests/interop-async-5'/family/'results.json'
		assert path.stat().st_mtime>=test_command['started_epoch']
		legacy.append(compact_legacy(path,compiler['sha256']))
	timer=build/'tests/language-generalization-10/timer-continuity/results.json'
	timer_data=json.loads(timer.read_text())
	assert timer_data['status']=='PASS' and timer_data['compiler_sha256']==compiler['sha256']
	assert timer.stat().st_mtime>=timer_command['started_epoch']
	assert all(row['passed'] and row['exit']==row['expected'] for row in timer_data['commands'])
	for source,expected in timer_data['sources'].items():
		assert sha(ROOT/source)==expected,source
	for name,expected in timer_data['products'].items():
		assert sha(timer.parent/name)==expected,name
	assert sha(timer_data['generated']['receipt'])==timer_data['generated']['sha256']
	generated_path=Path(timer_data['generated']['receipt'])
	generated=json.loads(generated_path.read_text())
	assert generated['status']=='PASS' and generated['compiler_sha256']==compiler['sha256']
	assert all(row['status']=='PASS' and row['exit']==row['expected'] for row in generated['records'])
	timer_summary=dict(raw_receipt=identity(timer),status=timer_data['status'],real_profile=timer_data['real_profile'],liburing=timer_data['liburing'],
		commands=timer_data['commands'],products=timer_data['products'],valgrind=timer_data['valgrind'],
		generated=dict(raw_receipt=identity(generated_path),commands=[dict(name=row['name'],argv_sha256=digest(row['command']),expected_exit=row['expected'],actual_exit=row['exit']) for row in generated['records']]))
	tools={}
	for name in ['valac','llvm-config','opt','llc','ld.lld','gcc','clang-22','meson','ninja','valgrind','gdb','readelf']:
		path=shutil.which(name);assert path,name
		result=subprocess.run([path,'--version'],capture_output=True,text=True,check=True)
		tools[name]=dict(binary=identity(path),version=result.stdout+result.stderr)
	compiler_version=subprocess.run([str(build/'astrac'),'--version'],capture_output=True,text=True,check=True).stdout
	target_info=subprocess.run([str(build/'astrac'),'--target-info'],capture_output=True,text=True,check=True).stdout
	dependencies=subprocess.run(['ldd',str(build/'astrac')],capture_output=True,text=True,check=True).stdout
	llvm_libraries=[identity(match) for match in re.findall(r'libLLVM[^\s]*\s+=>\s+(\S+)',dependencies)]
	assert llvm_libraries,'compiler LLVM linkage was not identified'
	targets=json.loads((ROOT/'tests/language-generalization-10/integration-targets.json').read_text())
	products={}
	for target in json.loads((build/'meson-info/intro-targets.json').read_text()):
		if target['name'] in targets:
			products[target['name']]=[identity(path) for path in target['filename']]
	assert set(products)==set(targets)
	source_paths=git('diff','--name-only',intake['base_commit'],'HEAD').splitlines()
	measured=json.loads(index.read_text())
	record=dict(format='astra-surge-10-evidence/1',status='PASS_CONTRACTED_G1_G9',project_id='astra',
		base_commit=intake['base_commit'],qualification_commit=build_command['head'],qualification_tree=build_command['tree'],
		compiler=compiler,compiler_version=compiler_version,target_info=target_info,linked_llvm=llvm_libraries,platform=platform.platform(),tools=tools,conservation=conservation,evidence_verifier_source=identity(Path(__file__)),
		build=build_command,test=test_command,timer=timer_summary,strict_options=dict(werror=options['werror'],linux_async=options['linux_async']),
		routing=routing,source_index=identity(index),measured_source_hashes=measured,
		task_committed_source_hashes={path:sha(ROOT/path) for path in source_paths if (ROOT/path).is_file()},
		selected_tests=[dict(name=row['name'],result=row['result'],returncode=row['returncode'],duration=row['duration'],
		command=row['command'],command_sha256=digest(row['command']),stdout=output(row.get('stdout','')),stderr=output(row.get('stderr','')),
		tap_passes=len(re.findall(r'^ok\s+\d+',row.get('stdout',''),re.M))) for row in rows],
		registered_test_count=len(json.loads((build/'meson-info/intro-tests.json').read_text())),
		build_products=products,receipts=receipts,legacy_boundary_receipts=legacy,
		limits=['Finite ADR 0132-0155 profiles; no general language completeness claim.',
		'LAZY-1 Q4 HELD/INCOMPLETE; original Surge 3/6 PARTIAL history unchanged.',
		'Linux no-libc executed; AArch64 OBJECT_ONLY; actual no-OS NOT_EXECUTED; no SH-4 or self-hosting.',
		'New boundary recipe instruments C adapters only; selected historical record recipes separately instrument generated LLVM controls. System libraries are not sanitizer-instrumented.',
		'Selected historical registrations and applications; full registry/all historical apps deferred to Surge 14.'])
	destination.write_text(json.dumps(record,indent=1)+'\n')
	assert destination.stat().st_size<1900000,'keep canonical source snapshot and patch within publisher limits'
	print('Verified',len(rows),'selected suites, twelve apps,',sum(len(row['commands']) for row in receipts),'focused commands;',destination)


if __name__=='__main__':
	main(*sys.argv[1:])
