# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Exact old-stage/object/runtime comparison against the preserved compiler."""
from pathlib import Path
import hashlib
import json
import os
import subprocess
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
STAGES = ('syntax','semantics','core','instances','cfg','ssa','nabi','cabi','llvm')


def main(baseline, candidates, out):
	out.mkdir(parents=True, exist_ok=True)
	def run(argv, expected=0):
		p = subprocess.run(list(map(str,argv)),cwd=ROOT,capture_output=True,env=dict(os.environ,CCACHE_DISABLE='1'))
		assert p.returncode == expected, (argv,p.returncode,p.stderr.decode())
		return p
	providers = candidates[0].parent / 'lib/astra'
	cases = {name: ([ROOT / 'tests/struct-abi/fixtures' / ('struct-abi-'+name+'.astra')],[],[]) for name in ('nested','generic','mixed','method','vector','f32','f64','pointer')}
	cases['owner-swap'] = ([ROOT / 'examples/owned-buffer-exchange' / name for name in ('types.astra','values.astra','owners.astra','main.astra')] + [ROOT / 'lib/astra' / name for name in ('base/buffers.astra','base/slices.astra','base/diagnostics.astra')], [], [providers / 'args-posix.o',providers / 'diagnostics-hosted.o'])
	cases['generic-arrays'] = ([ROOT / 'examples/generic-owned-arrays' / name for name in ('types.astra','values.astra','processing.astra','main.astra')] + [ROOT / 'lib/astra' / name for name in ('base/buffers.astra','base/slices.astra','base/diagnostics.astra','hosted/text.astra')], [], [providers / 'args-posix.o',providers / 'diagnostics-hosted.o',providers / 'text-posix.o'])
	cases['text-diag'] = ([ROOT / 'examples/base/diagnostics.astra',ROOT / 'lib/astra/hosted/equality.astra'],[],[providers / 'failure-hosted.o'])
	application = out / 'application.o'; run(['cc','-c',ROOT / 'examples/allocation-failure/application.c','-o',application])
	cases['allocation-actions'] = ([ROOT / 'examples/allocation-failure' / name for name in ('types.astra','actions.astra','factory.astra','main.astra')], ['--vapi',ROOT / 'examples/allocation-failure/application.vapi'], [application, providers / 'args-posix.o'])
	rows, banners = [], []
	for label, compiler in [('baseline',baseline)] + [('candidate-'+str(i+1),path) for i,path in enumerate(candidates)]:
		banners.append(dict(label=label,version=run([compiler,'--version']).stdout.decode(),help=run([compiler,'--help']).stdout.decode(),compiler_sha256=hashlib.sha256(compiler.read_bytes()).hexdigest()))
	for name, (sources, metadata, links) in cases.items():
		canonical, object_identity, native_identity, execution = {}, None, None, None
		for i, compiler in enumerate([baseline,*candidates]):
			for stage in STAGES:
				p = run([compiler,'--dump-'+stage,*sources,*(metadata if stage!='syntax' else [])]); assert not p.stderr
				if stage not in canonical:
					canonical[stage] = p.stdout
				assert p.stdout == canonical[stage], (name,i,stage)
				if stage=='llvm':
					ir=out / (name+'-'+str(i)+'.ll'); ir.write_bytes(p.stdout); obj=ir.with_suffix('.o'); run(['llc','-filetype=obj','-relocation-model=pic',ir,'-o',obj]); identity=hashlib.sha256(obj.read_bytes()).hexdigest()
					if object_identity is None:
						object_identity=identity
					assert identity==object_identity,(name,i,'object')
			exe=out / (name+'-'+str(i)); p=run([compiler,*sources,*metadata,*[part for link in links for part in ('--link-object',link)],'-o',exe]); assert not p.stdout and not p.stderr
			identity=hashlib.sha256(exe.read_bytes()).hexdigest()
			if native_identity is None:
				native_identity=identity
			assert identity==native_identity,(name,i,'native')
			p=run([exe]); observed=(p.stdout,p.stderr)
			if execution is None:
				execution=observed
			assert execution==observed,(name,i,'execution')
		rows.append(dict(name=name,stage_sha256={stage:hashlib.sha256(data).hexdigest() for stage,data in canonical.items()},object_sha256=object_identity,native_sha256=native_identity,stdout_sha256=hashlib.sha256(execution[0]).hexdigest(),stderr_sha256=hashlib.sha256(execution[1]).hexdigest()))
	(out / 'results.json').write_text(json.dumps(dict(cases=rows,banners=banners,canonical_stage_comparisons=len(rows)*len(candidates)*len(STAGES),object_comparisons=len(rows)*len(candidates),native_execution_comparisons=len(rows)*len(candidates),normalization='NONE; banner text recorded separately'),indent='\t')+'\n')
	print(str(len(rows))+' exact inherited source/object/execution cases')


if __name__ == '__main__':
	main(Path(sys.argv[1]).resolve(),[Path(arg).resolve() for arg in sys.argv[2:-1]],Path(sys.argv[-1]).resolve())
