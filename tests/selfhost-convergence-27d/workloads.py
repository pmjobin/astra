#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Retained config/digest/report qualification with explicit compiler and outputs."""
from pathlib import Path
import sys,json,os,subprocess,ast,shutil,hashlib,re,random
root=Path(__file__).resolve().parents[2];work=root.parent/'codex/work/astra';sys.path.insert(0,str(root/'tests/selfhost-ownership-syntax-27b'))
from support import execute,write,sha,tool_identity
import argparse
p=argparse.ArgumentParser();p.add_argument('--compiler',type=Path,required=True);p.add_argument('--compiler-sha256',required=True);p.add_argument('--runtime',type=Path,required=True);p.add_argument('--build',type=Path,required=True);a=p.parse_args()
leaf=a.runtime;build=a.build
for path,parent in [(leaf,work/'runtime'),(build,work/'build')]:
	assert path.is_absolute() and path.resolve().is_relative_to(parent.resolve()) and not any(p.is_symlink() for p in (path,*path.parents));path.mkdir(exist_ok=False)
(leaf/'recipe.py.txt').write_bytes(Path(__file__).read_bytes())
candidate=root;candidate_names={'examples/compiler-systems/'+n for n in ['module-config.astra','module-config-parser.astra','file-digest64.astra','systems-report.astra']};helper_name='examples/compiler-systems/checked-arguments.astra'
base='b3cc7bd9b972d3897a8981dfbcf12bf87a08821e';c0=work/'build/selfhost27b/c0-recovery-safealloc2/astrac';host=a.compiler;assert sha(c0)=='19d744c828551b2184f06552740db1beb5b6eeb326b8e98ba56d2dfa5bca31b6';assert sha(host)==a.compiler_sha256
apps={'config':['module-config.astra','module-config-parser.astra','module-config-model.astra','module-config-format.astra'],'digest':['file-digest64.astra'],'report':['systems-report.astra','systems-report-math.astra']}
libnames=['base/errors','base/diagnostics','text/utf8-message','text/utf8-byte-builder','text/scalar-format','hosted/text-ops','collections/bag','hosted/files','hosted/text'];common=['examples/application-runtime/support.astra',*['lib/astra/'+n+'.astra' for n in libnames]];allnames=sorted(set(common+[ 'examples/compiler-systems/'+n for group in apps.values() for n in group]));snapshots={};inputs={};origins={};blobs={}
for lane in ['baseline','current']:
	snapshots[lane]={}
	for name in allnames:
		origin=candidate/name if name in candidate_names else root/name;raw=subprocess.check_output(['git','-C',root,'show',base+':'+name]) if lane=='baseline' else origin.read_bytes();p=leaf/'source-inputs'/lane/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(raw);p.chmod(0o444);snapshots[lane][name]=p;inputs[str(p)]=sha(p)
		if lane=='baseline':blobs[name]=subprocess.check_output(['git','-C',root,'rev-parse',base+':'+name],text=True).strip()
		else:origins[str(origin)]=sha(origin)
helper=leaf/'source-inputs/current'/helper_name;helper.write_bytes((candidate/helper_name).read_bytes());helper.chmod(0o444);snapshots['current'][helper_name]=helper;inputs[str(helper)]=sha(helper);origins[str(candidate/helper_name)]=sha(candidate/helper_name)
providers={p:h for p,h in json.loads((work/'runtime/selfhost27c-dev16/link.json').read_text())['objects'].items() if Path(p).name!='llvm-capi.o'};assert len(providers)==6 and all(sha(p)==h for p,h in providers.items())
observer_source=root/'tests/compiler-systems-2/io-observer.c';observer=leaf/'io-observer.c';observer.write_bytes(observer_source.read_bytes());observer.chmod(0o444);inputs[str(observer)]=sha(observer)
tools=tool_identity([c0,host,sys.executable,*[shutil.which(n) for n in ['cc','opt','readelf','valgrind']]])
identity=dict(recipe_sha256=sha(__file__),baseline_revision=base,baseline_git_blobs=blobs,sources=inputs,origins=origins,providers=providers,tools=tools,observer=dict(original=str(observer_source),sha256=sha(observer_source)),producer=dict(path=str(host),sha256=sha(host)),scope='Selected actual migrated config/digest/report sources versus exact legacy Git sources, using identical provider objects and independent output expectations. No full compiler-source, complete ecosystem or final milestone acceptance.')
write(leaf/'identity.json',identity);commands=[];products={};observations=[];env=dict(os.environ,CCACHE_DISABLE='1',PYTHONDONTWRITEBYTECODE='1');env.pop('LD_PRELOAD',None);env.pop('VALGRIND_OPTS',None);counter=0

def run(name,argv,expected=0,stdout=b'',stderr=b'',overrides=None,memory=False):
	r=execute(argv,leaf/name,expected=expected,timeout=600,env=dict(env,**(overrides or {})));commands.append(dict(name=name,argv=list(map(str,argv)),result=r,environment_overrides=overrides or {}));write(leaf/'commands.json',commands);assert r['status']=='EXPECTED_OUTCOME',(name,(leaf/name/'stderr').read_text())
	actual=(leaf/name/'stdout').read_bytes();errors=(leaf/name/'stderr').read_bytes()
	if stdout is not None:assert actual==stdout,(name,actual,stdout)
	if memory:
		assert all(s in errors for s in [b'ERROR SUMMARY: 0 errors',b'in use at exit: 0 bytes in 0 blocks',b'(suppressed: 0 from 0)']);errors=re.sub(rb'^==\d+==[^\n]*\n',b'',errors,flags=re.M)
	if stderr is not None:assert errors==stderr,(name,errors,stderr)
	print(name,r['status'],round(r['seconds'],3),flush=True);return actual

def exercise(label,target,source,data,expected,stdout=b'',stderr=b'',code=0,mode=None,memory=False,preserved=False,open_failure=False):
	global counter
	counter+=1;name=label+'-'+str(counter);destination=leaf/(name+'.output')
	if preserved:destination.write_bytes(b'preserved destination')
	report=leaf/(name+'-io.json');overrides={'CS_IO_MODE':mode or 'normal','CS_IO_REPORT':str(report)}
	argv=[target,source,destination]
	if memory:argv=['valgrind','--default-suppressions=no','--error-exitcode=99','--leak-check=full','--show-leak-kinds=all','--errors-for-leak-kinds=all',*argv]
	run(name,argv,code,stdout,stderr,overrides,memory)
	if expected is not None:assert destination.exists() and destination.read_bytes()==expected,(name,destination.read_bytes() if destination.exists() else None,expected)
	else:assert not destination.exists(),name
	counts=json.loads(report.read_text());assert counts['opens'] - counts['closes'] == (1 if open_failure else 0),(name,counts)
	if open_failure:assert counts['reads']==0 and counts['writes']==0 and counts['flushes']==0,(name,counts)
	observations.append(dict(name=name,exit=code,output_sha256=sha(destination) if destination.exists() else None,counts=counts,memory=memory,mode=mode or 'normal'));write(leaf/'observations.json',observations)

run('observer-build',['cc','-std=c11','-O2','-Wall','-Wextra','-Werror','-c',observer,'-o',build/'observer.o']);products[str(build/'observer.o')]=sha(build/'observer.o')
wrap='-Wl,--wrap=open,--wrap=read,--wrap=write,--wrap=fsync,--wrap=close';fixtures=leaf/'fixtures';fixtures.mkdir();payload=random.Random(0xA57A2026).randbytes(4099);payloads=[b'',b'\0\xff\x80a\0',payload];binary_files=[]
for i,data in enumerate(payloads):p=fixtures/('binary-'+str(i));p.write_bytes(data);binary_files.append(p);inputs[str(p)]=sha(p)
configs=[b'limit=2147483647\nextra=2147483647\n','α=12\nβ=-5\nlast=100\n'.encode(),b''];config_files=[]
for i,data in enumerate(configs):p=fixtures/('config-'+str(i));p.write_bytes(data);config_files.append(p);inputs[str(p)]=sha(p)
unicode_binary=fixtures/'entrée-α-😀.bin';unicode_binary.write_bytes(payload);inputs[str(unicode_binary)]=sha(unicode_binary)
unicode_config=fixtures/'entrée-α-😀.conf';unicode_config.write_bytes(configs[1]);inputs[str(unicode_config)]=sha(unicode_config)
badconfigs=[b'invalid\n',b'x=2147483648\n',b'\xff'];badfiles=[]
for i,data in enumerate(badconfigs):p=fixtures/('bad-config-'+str(i));p.write_bytes(data);badfiles.append(p);inputs[str(p)]=sha(p)
def fnv(data):
	result=14695981039346656037
	for byte in data:result=((result^byte)*1099511628211)&((1<<64)-1)
	return result
binaries={}
for app,names in apps.items():
	binaries[app]=[]
	for lane,compiler in [('baseline',c0),('current',host)]:
		sources=[snapshots[lane]['examples/compiler-systems/'+n] for n in names]+[snapshots[lane][n] for n in common]
		if lane=='current':sources.append(snapshots[lane][helper_name])
		for mode in ['O0','O2']:
			label=app+'-'+lane+'-'+mode;obj=build/(label+'.o');target=build/label
			argv=[compiler,'-c','-'+mode,'-o',obj,*sources] if lane=='current' else [compiler,'-c','--entry-object','-'+mode,*sources,'-o',obj]
			run(label+'-compile',argv);run(label+'-link',['cc','-no-pie',obj,*providers,build/'observer.o',wrap,'-o',target]);header=run(label+'-ELF',['readelf','-h',target],stdout=None);assert b'ELF64' in header and b'Advanced Micro Devices X86-64' in header
			binaries[app].append((label,target));products.update({str(p):sha(p) for p in [obj,target]})
		if lane=='current':
			ir=build/(app+'-current.ll');run(app+'-current-LLVM',[compiler,'--emit-llvm','-o',ir,*sources]);run(app+'-LLVM-verify',['opt','-passes=verify','-disable-output',ir]);products[str(ir)]=sha(ir)
argv_policy=[];raw_memory_count=0

def run_raw(name,target,arguments,expected,memory=False):
	global raw_memory_count
	directory=leaf/name;directory.mkdir();start=__import__('time').monotonic()
	if memory:
		invocation=[b'valgrind',b'--default-suppressions=no',b'--error-exitcode=99',b'--leak-check=full',b'--show-leak-kinds=all',b'--errors-for-leak-kinds=all',*arguments];executable=shutil.which('valgrind')
	else:invocation=arguments;executable=target
	with (directory/'stdout').open('wb') as stdout,(directory/'stderr').open('wb') as stderr:
		process=subprocess.run(invocation,executable=executable,stdout=stdout,stderr=stderr,timeout=60,env=env)
	actual=(directory/'stdout').read_bytes();errors=(directory/'stderr').read_bytes()
	assert process.returncode==expected and not actual,(name,process.returncode,actual,errors)
	if memory:
		assert all(s in errors for s in [b'ERROR SUMMARY: 0 errors',b'in use at exit: 0 bytes in 0 blocks',b'(suppressed: 0 from 0)']);errors=re.sub(rb'^==\d+==[^\n]*\n',b'',errors,flags=re.M);raw_memory_count+=1
	assert not errors,(name,errors)
	row=dict(name=name,executable=str(executable),argv_hex=[a.hex() for a in invocation],expected_exit=expected,exit=process.returncode,seconds=__import__('time').monotonic()-start,stdout_sha256=sha(directory/'stdout'),stderr_sha256=sha(directory/'stderr'),strict_target_memory=memory)
	commands.append(row);write(leaf/'commands.json',commands);argv_policy.append(row);print(name,'RAW_ARGV_EXPECTED',flush=True)

for app,targets in binaries.items():
	for label,target in targets:
		normal=[os.fsencode(target),b'valid',os.fsencode(fixtures/'unused-output')]
		byte_cases=[('usage',[normal[0]],64),('usage-unicode-extra',normal+['α😀'.encode()],64),('bad-input',[normal[0],b'\xff',normal[2]],2),('bad-output',[normal[0],normal[1],b'\xff'],2),('bad-extra',normal+[b'\xff'],2),('bad-argv0',[b'\xff',normal[1],normal[2]],2),('overlong',[normal[0],b'\xc0\x80',normal[2]],2),('surrogate',[normal[0],b'\xed\xa0\x80',normal[2]],2),('above-max',[normal[0],b'\xf4\x90\x80\x80',normal[2]],2)]
		for case,args,code in byte_cases:
			run_raw(label+'-argv-'+case,target,args,code)
			if case=='bad-input':run_raw(label+'-argv-'+case+'-memory',target,args,code,memory=True)
			if case=='bad-argv0':
				alias=os.fsencode(leaf/(label+'-argv0-'))+b'\xff';os.symlink(os.fsencode(target),alias);run_raw(label+'-argv-'+case+'-memory',target,[alias,*args[1:]],code,memory=True)
for label,target in binaries['config']:
	for data,source in zip(configs,config_files):
		values=[int(line.split(b'=')[1]) for line in data.splitlines()];expected=f'records={len(values)}\ntotal={sum(values)}\nsource-bytes={len(data)}\nUTF-8=valid\n'.encode();exercise(label,target,source,data,expected,memory=data==b'')
	data=configs[1];values=[int(line.split(b'=')[1]) for line in data.splitlines()];expected=f'records={len(values)}\ntotal={sum(values)}\nsource-bytes={len(data)}\nUTF-8=valid\n'.encode();exercise(label+'-sortie-β-😀',target,unicode_config,data,expected,memory=True)
	for source in badfiles:exercise(label+'-invalid',target,source,None,b'preserved destination',code=3,preserved=True,memory=source==badfiles[-1])
	exercise(label+'-missing',target,fixtures/'missing',None,b'preserved destination',code=2,preserved=True,open_failure=True)
for app in ['digest','report']:
	for label,target in binaries[app]:
		stdout=b'report acquired\nreport released\n' if app=='report' else b''
		for data,source in zip(payloads,binary_files):
			expected=(f'bytes={len(data)}\nfnv64={fnv(data)}\n' if app=='report' else f'{fnv(data)}\n').encode();exercise(label,target,source,data,expected,stdout=stdout,memory=len(data)==5)
		expected=(f'bytes={len(payload)}\nfnv64={fnv(payload)}\n' if app=='report' else f'{fnv(payload)}\n').encode();exercise(label+'-sortie-β-😀',target,unicode_binary,payload,expected,stdout=stdout,memory=True)
		exercise(label+'-missing',target,fixtures/'missing',None,None,stdout=stdout,stderr=b'file I/O\n',code=2,memory=app=='report',open_failure=True)
		for mode in ['short','eintr']:
			expected=(f'bytes={len(payload)}\nfnv64={fnv(payload)}\n' if app=='report' else f'{fnv(payload)}\n').encode();exercise(label+'-'+mode,target,binary_files[-1],payload,expected,stdout=stdout,mode=mode)
		if app=='report':
			for mode in ['read-error','zero','eagain','flush','close']:
				expected=f'bytes={len(payload)}\nfnv64={fnv(payload)}\n'.encode() if mode=='flush' else b'' if mode=='zero' else None
				exercise(label+'-'+mode,target,binary_files[-1],payload,expected,stdout=stdout,stderr=b'file I/O\n',code=2,mode=mode,memory=mode in ['read-error','zero'])
assert all(sha(p)==h for p,h in {**inputs,**origins,**providers,**tools}.items());write(leaf/'products.json',products);write(leaf/'identity.json',identity);write(leaf/'result.json',dict(status='ACTUAL_MIGRATED_WORKLOAD_EQUIVALENCE_NATIVE_AND_MEMORY_PASS',apps=list(apps),target_profiles=['O0','O2'],source_versions=['legacy-C0-Git-b3cc7bd','actual-current-examples-27d-Source'+subprocess.check_output(['git','-C',root,'rev-parse','HEAD'],text=True).strip()],observations=len(observations),strict_target_memory_streams=sum(o['memory'] for o in observations)+raw_memory_count,malformed_argv_native_and_memory_cases=len(argv_policy),identity_sha256=sha(leaf/'identity.json'),commands_sha256=sha(leaf/'commands.json'),scope=identity['scope'],limitation='Actual app/file/error/fault and selected returning target-memory evidence only. No compiler-memory claim for this workload recipe, no full ecosystem, source closure or final milestone acceptance.'))
