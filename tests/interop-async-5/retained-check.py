#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Public retained C registration/dispatch/quiescence, A33/A34, ABI and memory."""
from pathlib import Path
import hashlib,json,os,re,resource,shutil,subprocess,sys,time
ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent
VG=['valgrind','--default-suppressions=no','--leak-check=full','--show-leak-kinds=all','--errors-for-leak-kinds=all','--error-exitcode=99']
HEADER='class Env{int bias;init(int bias){this.bias=bias;}} int apply(borrowed Env env,int x){return env.bias+x;}'
BIND='var env=new Env(10);var f=closure_bind(move env,apply);'
NEGATIVES={
	'checked-target':('class Fault : Error { init() : base("fault") {} } class Env{init(){}} int apply(borrowed Env env,int x)throws Fault{return x;}','var env=new Env();var f=checked_closure_bind(move env,apply);return retained_register(f,0);','retained callback requires a live exact'),
	'reserved-register':('extern(C) void* astra_retained_register(void* code,void* context,int mode);'+HEADER,BIND+'return retained_register(f,0);','compiler-private retained callback runtime symbol'),
	'reserved-export':('export(C) int astra_retained_observe(void* token){return 1;}'+HEADER,BIND+'return retained_register(f,0);','compiler-private retained callback runtime symbol'),
	'reserved-retire':('extern(C) int astra_retained_retire(void* token);'+HEADER,BIND+'return retained_register(f,0);','compiler-private retained callback runtime symbol'),
	'reserved-thunk':('[CCode(cname="astra.retained.i32.thunk")] extern(C) int forged(void* context,int value);'+HEADER,BIND+'return retained_register(f,0);','compiler-private retained callback runtime symbol'),
	'reserved-native-wrapper':('[CCode(cname="astra.retained.retire")] extern(C) int forged(void* token);'+HEADER,BIND+'return retained_register(f,0);','compiler-private retained callback runtime symbol'),
	'raw-closure-parameter':(HEADER+'extern(C) int inspect(borrowed Closure<Env,int,int> f);',BIND+'return inspect(f);','native Closure/CheckedClosure carriers cannot cross a raw C boundary'),
	'raw-closure-result':(HEADER+'extern(C) Closure<Env,int,int> inspect();','return 0;','native Closure/CheckedClosure carriers cannot cross a raw C boundary'),
	'raw-checked-parameter':('class Fault : Error { init() : base("fault") {} } class Env{init(){}} extern(C) int inspect(borrowed CheckedClosure<Env,Fault,int,int> f);','return 0;','native Closure/CheckedClosure carriers cannot cross a raw C boundary'),
	'forged-context':(HEADER,'return retained_register(123,0);','retained callback requires a live exact'),
	'wrong-signature':('class Env{init(){}} bool apply(borrowed Env env,bool x){return x;}','var env=new Env();var f=closure_bind(move env,apply);return retained_register(f,0);','retained callback requires a live exact'),
	'foreign-convention':(HEADER,BIND+'return retained_threaded_register(f,0);',None),
	'temporary-owner':(HEADER,'return retained_register(closure_bind(new Env(1),apply),0);','retained callback requires a live exact'),
	'double-release':(HEADER,BIND+'int registered=retained_register(f,0);release f;release f;return 0;',"owned value 'f' has already been released"),
	'after-release':(HEADER,BIND+'release f;return retained_dispatch(f,1);',"use of released owned value 'f'"),
	'after-move':(HEADER,BIND+'var g=move f;return retained_register(f,0);',"use of moved owned value 'f'"),
	'consume-during-dispatch':(HEADER+'int consume(owned Closure<Env,int,int> f){return 1;}',BIND+'return retained_dispatch(f,consume(move f));','forbids moving its backing'),
	'wrong-arity':(HEADER,BIND+'return retained_revoke(f,1);','retained callback operation requires exact arity'),
	'wrong-event-type':(HEADER,BIND+'return retained_dispatch(f,true);','retained callback requires exact int argument'),
	'borrow-escape':(HEADER+'owned Closure<Env,int,int> escape(borrowed Closure<Env,int,int> f){int registered=retained_register(f,0);return move f;}','return 0;','owned nominal handle local or parameter'),
	'borrowed-capture':(HEADER+'void escape(borrowed Env env){var f=closure_bind(move env,apply);retained_register(f,0);}','return 0;','nontransferable'),
	'c-function-pointer':('extern(C) int raw(void* callback);'+HEADER,BIND+'return raw(f);',None),
}
APPS={
	'A33':('deferred-event-subscriber',b'event=1:10\nevent=2:0\nevent=3:13\nevent=3:18\nevent=7:18\nevent=8:18\nevent=1:20\nevent=8:20\n'),
	'A35':('checked-event-transformer',b'event=31:3\nevent=32:1\nevent=33:12\nevent=34:-7\nevent=35:1\nevent rejected: negative payload\nevent=33:15\nevent=36:1\nevent=37:1\nevent=38:3\nevent=39:15\n'),
	'A34':('weak-document-observer',b'event=11:42\nevent=12:0\nevent=13:0\nevent=14:43\nevent=15:42\nevent=16:2\nevent=17:0\nevent=18:0\n')}
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def main(compiler,output):
	compiler=Path(compiler).resolve();out=Path(output).resolve();assert not out.is_relative_to(ROOT);out.mkdir(parents=True,exist_ok=True);resource.setrlimit(resource.RLIMIT_CORE,(0,0))
	record={'compiler':{'path':str(compiler),'sha256':sha(compiler)},'commands':[],'products':{},'applications':{},'source_sha256':{},'limitations':'GNU x86-64 LP64, single thread, bounded 64-slot explicit-step C registrar; exact nonthrowing Closure<Env,int,int>; checked adapters catch natively before C return. No arbitrary provider ABI or concurrent callbacks.'}
	def save():(out/'results.json').write_text(json.dumps(record,indent=2)+'\n')
	def run(argv,code=0,stdout=b'',diagnostic=None,memory=False,stderr_empty=True):
		argv=list(map(str,argv));start=time.monotonic();p=subprocess.run(argv,cwd=ROOT,capture_output=True,timeout=180,env=dict(os.environ,CCACHE_DISABLE='1'))
		good=p.returncode==code and (stdout is None or p.stdout==stdout)
		if diagnostic:good &= diagnostic.encode() in p.stderr and re.search(rb':[0-9]+:[0-9]+: error:',p.stderr)!=None and b'internal error' not in p.stderr.lower()
		elif memory:good &= all(x in p.stderr for x in [b'ERROR SUMMARY: 0 errors',b'in use at exit: 0 bytes in 0 blocks',b'(suppressed: 0 from 0)'])
		elif stderr_empty:good &= not p.stderr
		record['commands'].append({'argv':argv,'exit':p.returncode,'expected_exit':code,'stdout_hex':p.stdout.hex(),'stderr_hex':p.stderr.hex(),'expected_stdout_hex':None if stdout is None else stdout.hex(),'diagnostic':diagnostic,'memory':memory,'seconds':time.monotonic()-start,'passed':bool(good)});save();assert good,record['commands'][-1];return p.stdout
	def product(p):record['products'][str(p)]={'sha256':sha(p),'bytes':p.stat().st_size};save()
	ccs=[cc for cc in ['gcc','clang-22'] if shutil.which(cc)]
	if not any('clang' in cc for cc in ccs) and shutil.which('clang'):ccs.append('clang')
	assert len(ccs)==2 and shutil.which('valgrind')
	for cc in ccs:
		provider=out/(cc+'-retained.o');observer=out/(cc+'-observer.o')
		run([cc,'-std=c11','-O2','-Wall','-Wextra','-Werror','-c',ROOT/'lib/runtime/interop/retained.c','-o',provider]);product(provider)
		run([cc,'-std=c11','-O2','-Wall','-Wextra','-Werror','-c',HERE/'retained-observer.c','-o',observer]);product(observer)
		client=out/(cc+'-provider-client');expected=b'retained-provider calls=2 identity=stable stale=rejected quiesced=2\n'
		run([cc,'-std=c11','-O2','-Wall','-Wextra','-Werror',HERE/'retained-provider-client.c',provider,'-o',client]);run([client],stdout=expected);run([*VG,client],stdout=expected,memory=True);product(client)
		if 'clang' in cc:
			sanitizer=out/(cc+'-provider-sanitized')
			run([cc,'-std=c11','-O1','-g','-fsanitize=address,undefined','-fno-omit-frame-pointer',HERE/'retained-provider-client.c',ROOT/'lib/runtime/interop/retained.c','-o',sanitizer]);run([sanitizer],stdout=expected);product(sanitizer)
			record['sanitizer_qualification']={'compiler':cc,'checks':['ASan','UBSan'],'status':'PASS'};save()
		else:
			runtimes=[]
			for runtime in ['libasan.so','libubsan.so']:
				probe=subprocess.run([cc,'-print-file-name='+runtime],capture_output=True,check=True,text=True);path=Path(probe.stdout.strip())
				script_inputs=[]
				if path.is_file():
					raw=path.read_bytes()
					if not raw.startswith(b'\x7fELF'):
						script_inputs=[{'path':value,'available':Path(value).is_file()} for value in re.findall(r'/[^()\s]+',raw.decode('ascii',errors='replace'))]
				runtimes.append({'name':runtime,'compiler_path':str(path),'resolved_path':str(path.resolve()),'link_script_inputs':script_inputs,'available':path.is_file() and all(value['available'] for value in script_inputs)})
			record['gcc_sanitizer_limitation']={'status':'UNAVAILABLE' if not all(x['available'] for x in runtimes) else 'NOT_SELECTED','runtimes':runtimes,'qualification':'GCC independent provider/runtime and unsuppressed Valgrind still required; Clang ASan/UBSan is the sanitizer qualification'};save()
		text_provider=out/(cc+'-text-posix.o')
		run([cc,'-std=c11','-O2','-Wall','-Wextra','-Werror','-c',ROOT/'lib/runtime/platform/text-posix.c','-o',text_provider]);product(text_provider)
		for app_id,(name,expected) in APPS.items():
			source=ROOT/'examples/interop-async-5'/(name+'.astra')
			for level in [0,1,2]:
				binary=out/(cc+'-'+name+f'-O{level}')
				extras=[ROOT/'lib/astra/base/errors.astra',ROOT/'lib/astra/text/utf8-message.astra',ROOT/'lib/astra/hosted/text.astra','--link-object',text_provider] if app_id=='A35' else []
				run([compiler,f'-O{level}',source,*extras,'--link-object',provider,'--link-object',observer,'-o',binary]);product(binary);run([binary],stdout=expected)
				if level in [0,2]:run([*VG,binary],stdout=expected,memory=True)
			record['applications'][app_id]={'source':str(source.relative_to(ROOT)),'public_levels':[0,1,2],'expected_sha256':hashlib.sha256(expected).hexdigest(),'providers':ccs,'cleanup':'independent exact C event trace and unsuppressed zero-live Valgrind'};record['source_sha256'][str(source.relative_to(ROOT))]=sha(source);save()
	source=HERE/'retained-identity.astra';expected=b'event=51:10\nevent=51:20\nevent=52:15\nevent=52:125\nevent=53:10\nevent=53:20\n'
	for level in [0,1,2]:
		binary=out/f'retained-identity-O{level}'
		run([compiler,f'-O{level}',source,'--link-object',out/(ccs[0]+'-retained.o'),'--link-object',out/(ccs[0]+'-observer.o'),'-o',binary]);run([binary],stdout=expected);product(binary)
		if level in [0,2]:run([*VG,binary],stdout=expected,memory=True)
	source=HERE/'retained-checked-failure.astra';expected=b'event=41:7\nevent=42:1\nevent=43:7\nevent=44:1\nevent=41:9\nevent=45:12\nevent=43:9\n'
	for level in [0,1,2]:
		binary=out/f'retained-checked-failure-O{level}'
		run([compiler,f'-O{level}',source,ROOT/'lib/astra/base/errors.astra','--link-object',out/(ccs[0]+'-retained.o'),'--link-object',out/(ccs[0]+'-observer.o'),'-o',binary]);run([binary],stdout=expected);product(binary)
		if level in [0,2]:run([*VG,binary],stdout=expected,memory=True)
	source=ROOT/'examples/interop-async-5/deferred-event-subscriber.astra'
	for stage in ['semantics','core','cfg','ssa','nabi','cabi','llvm']:
		dump=run([compiler,'--dump-'+stage,source],stdout=None);(out/('retained-'+stage+'.txt')).write_bytes(dump)
		assert b'retained' in dump
		if stage=='llvm':assert b'call fastcc i32 %' in dump and b'@astra_retained_register' in dump and b'retained.quiescence' in dump
	for name,(header,body,diagnostic) in NEGATIVES.items():
		source=out/('negative-retained-'+name+'.astra');source.write_text(header+'\nint main(){'+body+'}\n');run([compiler,'--check',source,*([ROOT/'lib/astra/base/errors.astra'] if name in ['checked-target','raw-checked-parameter'] else [])],code=1,diagnostic=diagnostic,stderr_empty=False)
	bad=out/'bad-ack.o';run([ccs[0],'-std=c11','-Wall','-Wextra','-Werror','-c',HERE/'retained-bad-ack.c','-o',bad])
	source=out/'bad-ack.astra';source.write_text(HEADER+'\nint main(){'+BIND+'if(retained_register(f,0)!=0){return 1;}return 0;}\n')
	for level in [0,1,2]:
		binary=out/f'bad-ack-O{level}';run([compiler,f'-O{level}',source,'--link-object',bad,'-o',binary]);run([binary],code=-4);product(binary)
	for path in [*HERE.glob('retained-*'),ROOT/'lib/runtime/interop/retained.c',ROOT/'lib/runtime/interop/retained.h']:
		if path.is_file():record['source_sha256'][str(path.relative_to(ROOT))]=sha(path)
	record['status']='PASS';save();print(f'PASS retained callbacks: {len(record["commands"])} checks; {len(record["products"])} products; A33/A34/A35; GCC/Clang; stale-token/reentry/ACK guards; unsuppressed memory')
if __name__=='__main__':main(*sys.argv[1:])
