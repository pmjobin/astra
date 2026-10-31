# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Unsuppressed normal, failure, fatal and exact inherited-control measurements."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import hashlib
import json
import os
import re
import resource
import subprocess
import sys
sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/support'))
from pipeline import registered_command
resource.setrlimit(resource.RLIMIT_CORE, (0, 0))


sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tools/qualification'))
from output_paths import current_output

def frame_identity(frame):
	# A resolved compiler symbol is identical with a source location or with
	# '(in .../astrac)' when debug information is absent. Preserve library names.
	module = Path(frame.split(' (in ')[1].rstrip(')')).name if ' (in ' in frame else ''
	return frame.split(' (')[0] + ('@'+module if module and module != 'astrac' else '')


def qualify(build, baseline, out):
	out.mkdir(parents=True, exist_ok=False); evidence = build/'tests/gen-slice-1'; jobs = []
	for name in ['semantic', 'core', 'cfg', 'ssa', 'nabi', 'pipeline', 'llvm']:
		jobs.append(dict(name='model-'+name, argv=registered_command(build, 'gen-slice-' + name), status=0))
	for stage in ['syntax','semantics','core','instances','cfg','ssa','nabi','cabi','llvm']:
		jobs.append(dict(name='compiler-'+stage, argv=[build/'astrac','--dump-'+stage,ROOT/'lib/astra/base/slices.astra',ROOT/'tests/gen-slice-1/fixtures/basic.astra'], status=0))
	for name in ['nominal','generic-definition','unused-eq','owned-formal','local-tu','ownable-element','whole-slice','literal-f32','borrow-move','live-destination']:
		jobs.append(dict(name='failure-'+name,argv=[build/'astrac','--dump-llvm',ROOT/'lib/astra/base/slices.astra',current_output(evidence / 'negative')/(name+'.astra'),'--vapi',ROOT/'tests/struct-elem-1/fixtures/runtime.vapi'],status=1,diagnostic="'f64' and 'f32'" if name=='literal-f32' else None))
	control=out/'ordinary-name-control.astra'; control.write_text('int f(){'+''.join('int C%d=0;' % i for i in range(5001))+'return 0;}')
	assert hashlib.sha256(control.read_bytes()).hexdigest()=='926d5a295e7a62db4fc11c96a59d71437e5cc96026ee092d31dca696a2965927'
	for name,compiler in [('baseline',baseline/'astrac'),('candidate',build/'astrac')]:
		jobs.append(dict(name=name+'-inherited',argv=[compiler,'--dump-semantics',control],status=99,category='inherited-glib'))
	for name in ['matrix','deep-64','basic','effects','capabilities']:
		for mode in ['O0','O2','preserved-O2']:
			jobs.append(dict(name='run-'+name+'-'+mode,argv=[(current_output(evidence / 'execution') / f'{name}-{mode}-gcc')],status=0))
	for name in ['negative-index','count-index','empty-index','swap-first','swap-second','swap-same-invalid','destination','source','saved-view-count']:
		jobs.append(dict(name='fatal-'+name,argv=[(current_output(evidence / 'execution') / f'{name}-O2-gcc')],status=-4,category='fatal-nonunwinding'))
	installed=json.loads(((current_output(evidence / 'client') / 'results.json')).read_text());client=Path(installed['installed'])
	jobs.append(dict(name='installed-client',argv=[client/'consumer-0'],status=0))
	jobs.append(dict(name='handled-output-failure',argv=[client/'consumer-0'],status=2,full=True))
	jobs.append(dict(name='installed-fatal-client',argv=[client/'consumer-0','failure'],status=-6,category='fatal-nonunwinding'))
	jobs.append(dict(name='installed-compiler',argv=[Path(installed['installed_prefix'])/'bin/astrac','--dump-llvm','types.astra','values.astra','processing.astra','main.astra','base/slices.astra','base/diagnostics.astra','hosted/text.astra'],status=0,cwd=client))
	def measure(job):
		name = job['name']; log = out/(name+'.log')
		command = ['valgrind', '--vgdb=no', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=definite,indirect,possible', '--error-exitcode=99', '--log-file='+str(log), *map(str, job['argv'])]
		kwargs = dict(cwd=job.get('cwd', ROOT), stderr=subprocess.PIPE, env=dict(os.environ, CCACHE_DISABLE='1'), timeout=600)
		if job.get('full'):
			with open('/dev/full', 'wb') as sink:
				p = subprocess.run(command, stdout=sink, **kwargs)
		else:
			p = subprocess.run(command, stdout=subprocess.PIPE, **kwargs)
		(out/(name+'.stdout')).write_bytes(p.stdout or b''); (out/(name+'.stderr')).write_bytes(p.stderr)
		if job.get('diagnostic'): assert job['diagnostic'].encode() in p.stderr, (name, p.stderr)
		text = log.read_text()
		def number(pattern):
			match = re.search(pattern, text); return int(match[1].replace(',', '')) if match else 0
		row = dict(name=name, category=job.get('category', 'normal'), status=p.returncode, errors=number(r'ERROR SUMMARY: ([\d,]+) errors'), definite=number(r'definitely lost: ([\d,]+) bytes'), indirect=number(r'indirectly lost: ([\d,]+) bytes'), possible=number(r'possibly lost: ([\d,]+) bytes'), suppressed=number(r'suppressed: ([\d,]+) bytes'), reachable=number(r'still reachable: ([\d,]+) bytes'), command=command)
		(out/(name+'.json')).write_text(json.dumps(row, indent='\t')+'\n')
		assert 'ERROR SUMMARY:' in text and row['suppressed'] == 0 and p.returncode == job['status'], row
		if row['category'] == 'inherited-glib':
			assert row['errors'] == 2 and row['definite'] == 49152 and row['indirect'] == row['possible'] == 0, row
			assert '16,384 bytes in 1 blocks are definitely lost' in text and '32,768 bytes in 1 blocks are definitely lost' in text and 'g_quark_from_string' in text, name
			stacks = {}
			for block in re.split(r'\n==\d+==\s*\n', text):
				match = re.search(r'([\d,]+) bytes in 1 blocks are definitely lost', block)
				if not match:
					continue
				frames = re.findall(r'(?:at|by) 0x[0-9A-F]+: (.+)', block)
				stacks[match[1]] = [frame_identity(frame) for frame in frames]
			assert set(stacks) == {'16,384', '32,768'} and all(stacks.values()), stacks
			row['loss_stack_identities'] = stacks
		elif row['category'] == 'normal':
			assert row['errors'] == row['definite'] == row['indirect'] == row['possible'] == 0, row
		else:
			assert row['errors'] == 0, row
		row['log_sha256'] = hashlib.sha256(log.read_bytes()).hexdigest()
		(out/(name+'.json')).write_text(json.dumps(row, indent='\t')+'\n')
		return row
	with ThreadPoolExecutor(max_workers=4) as pool:
		rows = list(pool.map(measure, jobs))
	controls = [row for row in rows if row['category'] == 'inherited-glib']
	assert len(controls) == 2 and controls[0]['loss_stack_identities'] == controls[1]['loss_stack_identities'], controls
	(out/'results.json').write_text(json.dumps(rows, indent='\t')+'\n')
	print(f'{len(rows)} unsuppressed records, with fatal termination and exact inherited GLib controls separate')


if __name__ == '__main__':
	sys.dont_write_bytecode = True
	sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tools/qualification'))
	from output_paths import fresh_output
	sys.argv[-1] = str(fresh_output(sys.argv[-1]))
	qualify(Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve(), Path(sys.argv[3]).resolve())
