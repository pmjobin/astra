# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Public O0/O2 applications, independent oracles, C linkage and syscall evidence."""
from pathlib import Path
import hashlib
import json
import os
import random
import re
import resource
import signal
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
APPS = ROOT / 'examples/compiler-systems'
LIBS = [ROOT / ('lib/astra/' + name + '.astra') for name in [
	'text/scalar-format', 'hosted/text-ops', 'hosted/files', 'text/utf8-byte-builder',
	'text/utf8-message', 'collections/bag', 'base/errors', 'hosted/text']]
SUPPORT = ROOT / 'examples/application-runtime/support.astra'
MASK = (1 << 64) - 1
VG = ['valgrind', '--default-suppressions=no', '--leak-check=full', '--show-leak-kinds=all',
	'--errors-for-leak-kinds=all', '--error-exitcode=99']
WRAPS = '-Wl,--wrap=open,--wrap=read,--wrap=write,--wrap=fsync,--wrap=close'


def sha(path):
	return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def fnv(data):
	value = 14695981039346656037
	for byte in data:
		value = ((value ^ byte) * 1099511628211) & MASK
	return value


def main(compiler, emitter, output, runtime):
	compiler, emitter, output, runtime = [Path(x).resolve() for x in [compiler, emitter, output, runtime]]
	assert not output.is_relative_to(ROOT) and not runtime.is_relative_to(ROOT)
	output.mkdir(parents=True, exist_ok=True); runtime.mkdir(parents=True, exist_ok=True)
	out = Path(tempfile.mkdtemp(prefix='run-', dir=output))
	data_dir = Path(tempfile.mkdtemp(prefix='compiler-systems-', dir=runtime))
	resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
	commands, apps, comparisons, counts, inputs_record = [], {}, [], [], {}
	compiler_identity = sha(compiler)
	emitter_identity = sha(emitter)
	started = time.monotonic()

	def run(argv, code=0, stdout=b'', stderr=b'', env=None, memory=False, save=None):
		argv = list(map(str, argv)); before = time.monotonic()
		p = subprocess.run(argv, cwd=ROOT, capture_output=True, timeout=150,
			env=dict(os.environ, CCACHE_DISABLE='1', **(env or {})))
		valid = p.returncode == code and (stdout is None or p.stdout == stdout)
		if memory:
			valid &= all(x in p.stderr for x in [b'ERROR SUMMARY: 0 errors',
				b'in use at exit: 0 bytes in 0 blocks', b'(suppressed: 0 from 0)'])
			valid &= re.sub(rb'^==\d+==[^\n]*\n', b'', p.stderr, flags=re.M) == stderr
		else:
			valid &= stderr is None or p.stderr == stderr
		commands.append(dict(argv=argv, exit=p.returncode, expected_exit=code,
			stdout_hex=p.stdout.hex(), stderr_hex=p.stderr.hex(), expected_stdout_hex=None if stdout is None else stdout.hex(),
			expected_stderr_hex=None if stderr is None else stderr.hex(), env=env, memory=memory,
			seconds=time.monotonic()-before, passed=bool(valid)))
		(out / 'commands.json').write_text(json.dumps(commands, indent=2) + '\n')
		assert valid, commands[-1]
		if save: Path(save).write_bytes(p.stdout)
		return p

	def exact(path, expected):
		actual = Path(path).read_bytes()
		comparisons.append(dict(path=str(path), bytes=len(actual), expected_sha256=hashlib.sha256(expected).hexdigest(),
			actual_sha256=hashlib.sha256(actual).hexdigest(), passed=actual == expected,
			expected_hex=expected.hex() if len(expected) <= 4096 else None,
			actual_hex=actual.hex() if len(actual) <= 4096 else None))
		assert actual == expected, comparisons[-1]

	def fixture(path, data):
		path.write_bytes(data)
		inputs_record[str(path)] = dict(bytes=len(data), sha256=sha(path))

	help_text = run([compiler, '--help'], stdout=None).stdout
	assert all(flag in help_text for flag in [b'-O0', b'-O1', b'-O2', b'-c'])
	raw=run([compiler,'--dump-llvm','-O0',HERE/'optimizer-probe.astra'],stdout=None).stdout
	optimized=run([compiler,'--dump-llvm','-O2',HERE/'optimizer-probe.astra'],stdout=None).stdout
	assert b'mul i32' in raw and b'mul i32' not in optimized and b'ret i32 42' in optimized
	(out/'public-probe-O0.ll').write_bytes(raw);(out/'public-probe-O2.ll').write_bytes(optimized)
	providers = []
	for name in ['args', 'text', 'text-ops', 'files']:
		obj = out / (name + '.o'); providers.append(obj)
		run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-c', ROOT / f'lib/astra/platform/{name}-posix.c', '-o', obj])
	observer = out / 'io-observer.o'
	run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-c', HERE / 'io-observer.c', '-o', observer])
	observed_provider = out / 'files-observed.o'
	run(['cc', '-r', out / 'files.o', observer, WRAPS, '-o', observed_provider])
	observed_providers = [*providers[:-1], observed_provider]

	def compile_app(name, sources=None):
		sources = sources or [APPS / (name + '.astra')]
		inputs = [*sources, SUPPORT, *LIBS]
		pair = []
		for level in [0, 2]:
			binary = out / f'{name}-O{level}'
			run([compiler, f'-O{level}', *inputs, *[v for p in providers for v in ['--link-object', p]], '-o', binary])
			pair.append(binary)
			# Independent LLVM tool route remains an explicit reference, not public O2 evidence.
		ir = out / f'{name}.ll'; optimized = out / f'{name}-reference.ll'; obj = out / f'{name}-reference.o'
		run([emitter, '--emit', ir, *inputs])
		run(['opt', '-passes=default<O2>', '-S', ir, '-o', optimized])
		run(['opt', '-passes=verify', '-disable-output', optimized])
		run(['llc', '-O2', '-filetype=obj', '-relocation-model=pic', optimized, '-o', obj])
		reference = out / f'{name}-reference'
		run(['cc', obj, *providers, '-o', reference]); pair.append(reference)
		apps[name] = dict(sources={str(p.relative_to(ROOT)):sha(p) for p in inputs},
			products={str(p):dict(sha256=sha(p), bytes=p.stat().st_size) for p in [*pair, ir, optimized, obj]}, cases=[])
		return pair, inputs

	def exercise(name, pair, args, stdout=b'', stderr=b'', code=0, file_expected=None, memory=True):
		for binary in pair:
			run([binary, *args], code, stdout, stderr)
			if file_expected is not None: exact(args[-1], file_expected)
			if memory:
				run([*VG, binary, *args], code, stdout, stderr, memory=True)
				if file_expected is not None: exact(args[-1], file_expected)
		apps[name]['cases'].append(dict(args=list(map(str,args)), stdout_hex=stdout.hex(), stderr_hex=stderr.hex(), exit=code,
			output_sha256=None if file_expected is None else hashlib.sha256(file_expected).hexdigest()))

	diagnostics, _ = compile_app('optimized-diagnostics')
	for index, data in enumerate([b'10|alpha\n-2|caf\xc3\xa9\n0|zero\n', b'-7|x\n9|a\x00b\n']):
		source = data_dir / f'diagnostics-{index}.input'; target = data_dir / f'diagnostics-{index}.output'; fixture(source,data)
		rows = [line.split(b'|', 1) for line in data.split(b'\n') if line]
		codes = [int(code) for code, _ in rows]
		expected = f'positive={sum(c>0 for c in codes)} negative={sum(c<0 for c in codes)} zero={codes.count(0)}\n'.encode()
		expected += b''.join(str(int(code)).encode()+b':'+str(len(text)).encode()+b':'+text+b'\n' for code,text in rows)
		exercise('optimized-diagnostics', diagnostics, [source,target], b'diagnostics released\n', file_expected=expected)
	bad = data_dir / 'diagnostics-bad.input'; fixture(bad,b'invalid\n'); target.write_bytes(b'preserved')
	exercise('optimized-diagnostics', diagnostics, [bad,target], b'diagnostics released\n', b'invalid diagnostics\n', 3, b'preserved')

	bulk, bulk_inputs = compile_app('bulk-copy')
	generator = random.Random(0xA57A2026)
	payloads = [b'', b'\x00\xff\x80a\x00', generator.randbytes(262147), generator.randbytes(327791)]
	files = []
	for index, data in enumerate(payloads):
		source = data_dir / f'binary-{index}.input'; target = data_dir / f'binary-{index}.output'; fixture(source,data); files.append(source)
		exercise('bulk-copy', bulk, [source,target], file_expected=data, memory=index in [1,2])

	wide, _ = compile_app('wide-counter')
	for rounds in [0,1,97]:
		value = 14695981039346656037
		for at in range(rounds): value = ((value ^ at)*1099511628211)&MASK
		signed = -(1<<63)+rounds*4294967297
		expected = f'rounds={rounds}\nu64={value}\ni64={signed}\nwrap={(MASK+rounds)&MASK}\nhigh={value>>32}\nlow={value&0xffffffff}\nmin={-(1<<63)}\nmax={MASK}\n'.encode()
		exercise('wide-counter',wide,[rounds],expected)

	namespaces, _ = compile_app('namespace-same-name', [APPS / f'namespace-{s}.astra' for s in ['same-name','left','right']])
	# Each module witness is also qualified independently by modules-1.
	for left,right in [(7,9),(-3,22)]:
		expected = f'left={left}\nright={right}\n'.encode()
		exercise('namespace-same-name', namespaces, [left,right], expected)

	config, _ = compile_app('module-config', [APPS / f'module-config{s}.astra' for s in ['', '-parser', '-model', '-format']])
	for index, data in enumerate([b'limit=2147483647\nextra=2147483647\n', '\u03b1=12\n\u03b2=-5\nlast=100\n'.encode(), b'']):
		source = data_dir / f'module-config-{index}.input'; target = data_dir / f'module-config-{index}.output'; fixture(source,data)
		values=[int(line.split(b'=')[1]) for line in data.splitlines()]
		expected = f'records={len(values)}\ntotal={sum(values)}\nsource-bytes={len(data)}\nUTF-8=valid\n'.encode()
		exercise('module-config', config, [source,target], file_expected=expected)

	digest, digest_inputs = compile_app('file-digest64')
	for source in files[2:]:
		target = data_dir / (source.stem + '.digest')
		exercise('file-digest64',digest,[source,target],file_expected=f'{fnv(source.read_bytes())}\n'.encode())

	client = out / 'object-client.o'
	run(['cc','-std=c11','-Wall','-Wextra','-Werror','-c',APPS/'object-link-client.c','-o',client])
	object_sources = [APPS/'object-link-client.astra', APPS/'object-link-math.astra']
	objects, object_cases = [], []
	for level in [0,1,2]:
		obj = out/f'object-link-client-O{level}.o'; binary = out/f'object-link-client-O{level}'
		run([compiler,f'-O{level}','-c',*object_sources,'-o',obj])
		header=run(['readelf','-h',obj],stdout=None).stdout
		assert re.search(rb'Type:\s+REL\b',header) and b'X86-64' in header
		symbols=run(['nm','--defined-only',obj],stdout=None).stdout
		assert b' T astra_systems_mix' in symbols and not re.search(rb'\bmain$',symbols,re.M)
		run(['cc',client,obj,'-o',binary]); objects.extend([obj,binary])
		for value in [0,4294967297,MASK]:
			expected = f'{((value^14695981039346656037)*1099511628211)&MASK}\n'.encode()
			run([binary,value],stdout=expected)
			object_cases.append(dict(level=level, args=[str(value)], stdout_hex=expected.hex(), exit=0))
			if value == MASK: run([*VG,binary,value],stdout=expected,memory=True)
	apps['object-link-client']=dict(sources={str(p.relative_to(ROOT)):sha(p) for p in [*object_sources,APPS/'object-link-client.c']},products={str(p):dict(sha256=sha(p),bytes=p.stat().st_size) for p in objects},cases=object_cases)
	repeated=out/'object-link-client-repeated.o'
	run([compiler,'-O2','-c',*reversed(object_sources),'-o',repeated])
	assert sha(repeated)==sha(out/'object-link-client-O2.o')
	for binary in [diagnostics[1],out/'object-link-client-O2']:
		dynamic=run(['readelf','-d',binary],stdout=None).stdout
		assert set(re.findall(rb'Shared library: \[([^\]]+)\]',dynamic)) <= {b'libc.so.6'}

	report, report_inputs = compile_app('systems-report',[APPS/'systems-report.astra',APPS/'systems-report-math.astra'])
	for source in [files[0],files[2]]:
		data=source.read_bytes();target=data_dir/(source.stem+'.report')
		expected=f'bytes={len(data)}\nfnv64={fnv(data)}\n'.encode()
		exercise('systems-report',report,[source,target],b'report acquired\nreport released\n',file_expected=expected)
	exercise('systems-report',report,[data_dir/'missing',target],b'report acquired\nreport released\n',b'file I/O\n',2)

	# Instrument provider objects; the actual application remains a public driver executable.
	for name, inputs in [('bulk-copy',bulk_inputs),('file-digest64',digest_inputs),('systems-report',report_inputs)]:
		for level in [0,2]:
			binary=out/f'{name}-observed-O{level}'
			run([compiler,f'-O{level}',*inputs,*[v for p in observed_providers for v in ['--link-object',p]],'-o',binary])
			modes=['normal','short','eintr'] if name=='file-digest64' else ['normal','short','eintr','read-error','zero','eagain','flush','close']
			if name=='bulk-copy':modes.append('write-error')
			for mode in modes:
				receipt=data_dir/f'{name}-O{level}-{mode}.json';target=data_dir/f'{name}-O{level}-{mode}.output'
				success=mode in ['normal','short','eintr']
				expected_stdout=b'report acquired\nreport released\n' if name=='systems-report' else b''
				expected_stderr=b'' if success or name=='bulk-copy' else b'file I/O\n'
				run([binary,files[2],target],0 if success else 2,expected_stdout,expected_stderr,env={'CS_IO_MODE':mode,'CS_IO_REPORT':str(receipt)})
				if name=='systems-report' and mode in ['read-error','zero']:
					run([*VG,binary,files[2],target],2,expected_stdout,expected_stderr,memory=True,env={'CS_IO_MODE':mode,'CS_IO_REPORT':str(receipt)})
				row=json.loads(receipt.read_text());row.update(app=name,level=level,mode=mode,bytes=len(payloads[2]),wall_seconds=commands[-1]['seconds']);counts.append(row)
				assert row['opens']==row['closes']
				if success:
					expected=payloads[2] if name=='bulk-copy' else (f'{fnv(payloads[2])}\n'.encode() if name=='file-digest64' else f'bytes={len(payloads[2])}\nfnv64={fnv(payloads[2])}\n'.encode())
					exact(target,expected)
					assert row['read_bytes']==len(payloads[2])
					assert row['written_bytes']==len(expected)
					if mode=='normal':assert row['reads']<len(payloads[2])//1000
					if mode=='normal' and name=='bulk-copy':assert row['writes']<len(payloads[2])//1000
				elif mode=='write-error':exact(target,payloads[2][:613])
				elif mode=='zero':exact(target,b'')
				elif name=='bulk-copy' and mode=='read-error':
					exact(target,payloads[2][:997]);assert row['read_bytes']==997 and row['written_bytes']==997
				elif name=='bulk-copy' and mode=='eagain':exact(target,b'')
				elif name=='bulk-copy' and mode in ['flush','close']:exact(target,payloads[2])
				elif name=='systems-report' and mode in ['read-error','eagain','close']:
					assert not target.exists() and row['written_bytes']==0
				elif name=='systems-report' and mode=='flush':
					exact(target,f'bytes={len(payloads[2])}\nfnv64={fnv(payloads[2])}\n'.encode())

					# Invalid options/failed compilation preserve a previous product and publish no partial object.
	for level in [0,2]:
		binary=out/f'byte-baseline-O{level}';target=data_dir/f'byte-baseline-O{level}.output';receipt=data_dir/f'byte-baseline-O{level}.json'
		run([compiler,f'-O{level}',HERE/'byte-baseline.astra',SUPPORT,*LIBS,*[v for p in observed_providers for v in ['--link-object',p]],'-o',binary])
		run([binary,files[2],target],env={'CS_IO_REPORT':str(receipt)})
		exact(target,payloads[2]);row=json.loads(receipt.read_text());row.update(app='byte-baseline',level=level,mode='normal',bytes=len(payloads[2]),wall_seconds=commands[-1]['seconds']);counts.append(row)
		assert row['reads']==len(payloads[2])+1 and row['writes']==len(payloads[2])

	bad_source=data_dir/'invalid.astra';fixture(bad_source,b'int broken( {\n')
	sentinel=out/'sentinel.o';sentinel.write_bytes(b'previous product')
	for args in [['-O3'],['-O9'],['--target','i686-unknown-linux-gnu'],['-c','--link-object',client],['-c','-O2',bad_source]]:
		p=run([compiler,*args,'-o',sentinel],code=1 if bad_source in args else 2,stderr=None)
		exact(sentinel,b'previous product')
	missing=HERE/'missing-foreign.astra'
	p=run([compiler,'-O2',missing,'-o',sentinel],code=1,stderr=None)
	assert b'astra_systems_absent_provider' in p.stderr;exact(sentinel,b'previous product')
	missing_obj=out/'missing-foreign.o';missing_client=data_dir/'missing-client.c'
	fixture(missing_client,b'extern int missing_bridge(void);int main(void){return missing_bridge();}\n')
	run([compiler,'-O2','-c',missing,'-o',missing_obj])
	p=run(['cc',missing_client,missing_obj,'-o',out/'missing-linked'],code=1,stderr=None)
	assert b'astra_systems_absent_provider' in p.stderr and not (out/'missing-linked').exists()

	fp_provider=out/'floating.o';fp_client=out/'floating-client.o'
	run(['cc','-std=c11','-Wall','-Wextra','-Werror','-c',HERE/'floating.c','-o',fp_provider])
	run(['cc','-std=c11','-Wall','-Wextra','-Werror','-DASTRA_FLOAT_CLIENT','-c',HERE/'floating.c','-o',fp_client])
	for level in [0,1,2]:
		binary=out/f'floating-O{level}';obj=out/f'floating-O{level}.o';linked=out/f'floating-client-O{level}'
		run([compiler,f'-O{level}',HERE/'floating.astra','--link-object',fp_provider,'-o',binary]);run([binary]);run([*VG,binary],memory=True)
		run([compiler,f'-O{level}','-c',HERE/'floating.astra','-o',obj]);run(['cc',obj,fp_client,'-o',linked]);run([linked])
		ir=run([compiler,f'-O{level}','--dump-llvm',HERE/'floating.astra'],stdout=None).stdout
		assert b'fmul float' in ir and b'fadd float' in ir and b'fmul double' in ir and b'fadd double' in ir
		assert not re.search(rb'\b(fast|reassoc|contract|afn|nsz|nnan|ninf)\b',ir)
		(out/f'floating-O{level}.ll').write_bytes(ir)
	allocation_client=out/'allocation-client.o'
	run(['cc','-std=c11','-Wall','-Wextra','-Werror','-c',HERE/'allocation.c','-o',allocation_client])
	for level in [0,2]:
		obj=out/f'allocation-O{level}.o';binary=out/f'allocation-O{level}'
		run([compiler,f'-O{level}','-c',HERE/'allocation.astra','-o',obj])
		run(['cc',obj,allocation_client,'-Wl,--wrap=calloc,--wrap=free','-o',binary])
		expected=b'allocate\nfree\nreturned\n'
		run([binary],stdout=expected);run([*VG,binary],stdout=expected,memory=True)
		run([binary],code=-signal.SIGILL,stdout=b'allocate\n',env={'CS_ALLOCATION_FAIL':'1'})
		ir=run([compiler,f'-O{level}','--dump-llvm',HERE/'allocation.astra'],stdout=None).stdout
		assert b'@calloc(' in ir and b'@free(' in ir and b'nobuiltin' in ir and b'llvm.trap' in ir
		(out/f'allocation-O{level}.ll').write_bytes(ir)
	foreign_client=out/'foreign-effects-client.o'
	run(['cc','-std=c11','-Wall','-Wextra','-Werror','-fno-builtin','-c',HERE/'foreign-effects.c','-o',foreign_client])
	for level in [0,2]:
		obj=out/f'foreign-effects-O{level}.o';binary=out/f'foreign-effects-O{level}'
		run([compiler,f'-O{level}','-c',HERE/'foreign-effects.astra','-o',obj])
		run(['cc',obj,foreign_client,'-Wl,--wrap=abs','-o',binary]);run([binary])
	resource_provider=out/'resource-provider.o'
	run(['cc','-std=c11','-Wall','-Wextra','-Werror','-c',ROOT/'tests/cabi/companion.c','-o',resource_provider])
	resource_types=ROOT/'tests/resource/fixtures/resource-types.vapi'
	resource_api=ROOT/'tests/resource/fixtures/resource-api.vapi'
	for source in [*[ROOT/f'tests/resource/fixtures/resource-{name}.astra' for name in ['basic','move','order','loop']],HERE/'resource-error.astra']:
		for level in [0,2]:
			binary=out/f'{source.stem}-public-O{level}'
			inputs=[source,*([ROOT/'lib/astra/base/errors.astra'] if source.name=='resource-error.astra' else [])]
			run([compiler,f'-O{level}',*inputs,'--vapi',resource_types,'--vapi',resource_api,'--link-object',resource_provider,'-o',binary])
			run([binary]);run([*VG,binary],memory=True)
	assert len(apps)==8
	assert compiler_identity==sha(compiler) and emitter_identity==sha(emitter)
	for path,initial in inputs_record.items():assert sha(path)==initial['sha256'] and Path(path).stat().st_size==initial['bytes']
	identity=dict(all_passed=True,compiler_sha256=compiler_identity,emitter_sha256=emitter_identity,output=str(out),runtime=str(data_dir),inputs=inputs_record,
		seconds=time.monotonic()-started,applications=apps,commands=len(commands),memory_runs=sum(x['memory'] for x in commands),
		file_comparisons=comparisons,syscall_counts=counts,
		products={str(p):dict(sha256=sha(p),bytes=p.stat().st_size) for p in out.iterdir() if p.is_file() and p.suffix!='.json'})
	(out/'identity.json').write_text(json.dumps(identity,indent=2)+'\n');(output/'current.json').write_text(json.dumps(identity,indent=2)+'\n')
	print(json.dumps({k:v for k,v in identity.items() if k not in ['applications','file_comparisons']},indent=2))


if __name__=='__main__':main(*sys.argv[1:])
