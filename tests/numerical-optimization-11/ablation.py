"""Same-O2 semantic optimization ablations; ordinary public driver processes."""
from pathlib import Path
import hashlib
import json
import os
import platform
import random
import re
import statistics
import subprocess
import sys
import time
import evidence as support

ROOT = support.ROOT


def probe(command):
	start = time.monotonic()
	result = subprocess.run(command,cwd=ROOT,capture_output=True,text=True,timeout=60)
	return dict(command=list(map(str,command)),exit=result.returncode,stdout=result.stdout,stderr=result.stderr,seconds=time.monotonic()-start)


def distribution(values):
	return dict(samples=values,median=statistics.median(values),minimum=min(values),maximum=max(values),mean=statistics.mean(values),stdev=statistics.stdev(values))


def main(compiler,output,baseline=None):
	e = support.Evidence(compiler,output,'ablation')
	apps = ROOT/'examples/numerical-optimization-11'; numerics = ROOT/'lib/astra/numerics'
	fixtures = {
		89: ('biquad',['filters'],'application-oracle.c',48000),
		91: ('geometry',['vectors','complex'],'application-oracle.c',48000),
		93: ('packet',[],'packet-oracle.c',48000),
		94: ('metadata',[],'metadata-oracle.c',375),
	}
	host = dict(platform=platform.platform(),python=sys.version,affinity=sorted(os.sched_getaffinity(0)),
		cpuinfo=Path('/proc/cpuinfo').read_text().split('\n\n')[0],load_before=Path('/proc/loadavg').read_text(),
		lscpu=probe(['lscpu','--json']),llvm=probe(['llvm-config','--version']),clang=probe(['clang','--version']),
		target=e.run([e.compiler,'--target-info']).stdout)
	cpu = host['affinity'][0]
	for name in ('scaling_governor','scaling_cur_freq'):
		path=Path(f'/sys/devices/system/cpu/cpu{cpu}/cpufreq')/name
		host[name]=path.read_text().strip() if path.exists() else 'unavailable'
	results = dict(protocol='same source, C oracle, O2 and LLVM pipeline; only ASTRA_TEST_OPTIMIZATIONS differs',host=host,
		seed=110093,warmups=2,paired_repetitions=11,compile_repetitions=3,apps={},limits=[
		'Wall times include process launch, C reference work and output formatting; no timing threshold is an acceptance gate.',
		'Machine instruction counts cover the complete executable including the identical C oracle and startup.',
		'First observed run is recorded separately from warmups and interleaved measured runs.',
		'No CPU affinity, frequency, governor, kernel permissions or host settings are changed.'])
	if baseline:
		baseline=Path(baseline).resolve(); results['historical_baseline']=support.parent.identity(baseline)
	assert e.compiler != baseline
	e.inputs(Path(__file__))
	for app,(name,modules,oracle_name,count) in fixtures.items():
		source=apps/f'a{app}-{name}.astra'; libraries=[numerics/(module+'.astra') for module in modules]
		oracle=Path(__file__).with_name(oracle_name); e.inputs(source,*libraries,oracle)
		folder=e.output/f'a{app}'; folder.mkdir(exist_ok=True); provider=folder/'oracle.o'
		e.run(['clang','-std=c11','-O2','-ffp-contract=off','-fno-fast-math','-fno-builtin','-Wall','-Wextra','-Werror',f'-DAPP_ID={app}','-c',oracle,'-o',provider])
		row=dict(work_items=count,modes={}); products={}; observations=[]
		for mode in ('off','on'):
			env={'ASTRA_TEST_OPTIMIZATIONS':mode}; exe=folder/mode; products[mode]=exe; compiles=[]
			for repeat in range(3):
				e.run([e.compiler,'-O2',source,*libraries,'--link-object',provider,'--link-library','m','-o',exe],env=env)
				compiles.append(e.data['commands'][-1]['seconds'])
			data=folder/f'{mode}.bin'
			e.run([exe],contains=f'numerical:A{app}:{count}')
			cold=e.data['commands'][-1]['seconds']
			result=e.run([exe],env={'ASTRA_NUMERICAL_OUTPUT':str(data)},contains=f'numerical:A{app}:{count}')
			observations.append(data.read_bytes())
			allocation=re.search(r'calloc=(\d+)',result.stdout)
			mode_row=dict(compile_seconds=distribution(compiles),cold_process_seconds=cold,observed=result.stdout,
				allocation_calls=int(allocation[1]) if allocation else None,executable=support.parent.identity(exe),
				size=e.run(['size',exe]).stdout)
			for level,label in [(0,'source-lowering'),(2,'optimized')]:
				ir=folder/f'{mode}-{label}.ll'; ir.write_text(e.run([e.compiler,'--dump-llvm',f'-O{level}',source,*libraries],env=env).stdout); e.files(ir)
			assembly=folder/f'{mode}.asm'; assembly.write_text(e.run(['objdump','-d','--no-show-raw-insn',exe]).stdout)
			mode_row['static_machine_instructions']=len(re.findall(r'^\s*[0-9a-f]+:\s+\S',assembly.read_text(),re.M))
			e.run(['valgrind','--quiet','--error-exitcode=91','--leak-check=full','--errors-for-leak-kinds=all',exe],contains='failed=0' if app in (93,94) else f'numerical:A{app}:')
			for warmup in range(2): e.run([exe])
			row['modes'][mode]=mode_row; e.files(exe,data,assembly)
		assert observations[0]==observations[1]
		if app in (93,94):
			assert row['modes']['off']['allocation_calls']==count and row['modes']['on']['allocation_calls']==0
		measurements={'off':[],'on':[]}; randomizer=random.Random(110093+app)
		for repeat in range(11):
			order=['off','on']; randomizer.shuffle(order)
			for mode in order:
				e.run([products[mode]]); measurements[mode].append(e.data['commands'][-1]['seconds'])
		for mode in measurements: row['modes'][mode]['warm_process_seconds']=distribution(measurements[mode])
		row['median_on_over_off']=statistics.median(measurements['on'])/statistics.median(measurements['off'])
		row['machine_identical']=row['modes']['off']['executable']['sha256']==row['modes']['on']['executable']['sha256']
		counter_probe=probe(['perf','stat','-x,','-e','instructions,cycles',str(products['on'])]); row['counter_probe']=counter_probe
		if counter_probe['exit']==0:
			counters={mode:{event:[] for event in ('instructions','cycles')} for mode in ('off','on')}
			for repeat in range(7):
				order=['off','on']; randomizer.shuffle(order)
				for mode in order:
					result=e.run(['perf','stat','-x,','-e','instructions,cycles',products[mode]],contains=f'numerical:A{app}:')
					for line in result.stderr.splitlines():
						fields=line.split(',')
						if len(fields)>=3 and fields[2].split(':')[0] in counters[mode]: counters[mode][fields[2].split(':')[0]].append(int(fields[0]))
			for mode in counters:
				assert all(len(values)==7 for values in counters[mode].values())
				row['modes'][mode]['hardware_counters']={event:distribution(values) for event,values in counters[mode].items()}
		if baseline and app!=91:
			exe=folder/'historical-O2'
			e.run([baseline,'-O2',source,*libraries,'--link-object',provider,'--link-library','m','-o',exe])
			compile_seconds=e.data['commands'][-1]['seconds']
			data=folder/'historical.bin'; result=e.run([exe],env={'ASTRA_NUMERICAL_OUTPUT':str(data)})
			assert data.read_bytes()==observations[0]
			for warmup in range(2): e.run([exe])
			timings=[]
			for repeat in range(11):e.run([exe]);timings.append(e.data['commands'][-1]['seconds'])
			row['historical']=dict(observed=result.stdout,executable=support.parent.identity(exe),compile_seconds=compile_seconds,warm_process_seconds=distribution(timings),size=e.run(['size',exe]).stdout); e.files(exe,data)
		elif baseline: row['historical_unavailable']='Pinned compiler predates the bounded-vector load/store source forms used by A91; no substituted source comparison.'
		results['apps'][str(app)]=row; e.files(provider)
		(e.output/'measurements.json').write_text(json.dumps(results,indent=2)+'\n')
	results['host']['load_after']=Path('/proc/loadavg').read_text()
	results['perf_probe']=probe(['perf','stat','-x,','-e','instructions,cycles',str(e.output/'a89/on')])
	if results['perf_probe']['exit']!=0: results['limits'].append('Hardware performance counters unavailable; exact perf refusal is retained. Wall time, allocation counts, static instruction counts, binary sizes and compilation times are measured.')
	path=e.output/'measurements.json'; path.write_text(json.dumps(results,indent=2)+'\n'); e.files(path)
	e.complete()


if __name__=='__main__': main(*sys.argv[1:])
