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
	out.mkdir(parents=True, exist_ok=False); evidence = build/'tests/struct-elem-1'; jobs = []
	for name in ['semantic', 'core', 'cfg', 'ssa', 'nabi', 'pipeline', 'llvm']:
		if name in ['pipeline', 'llvm']:
			# These unchanged complete models expose the host GLib startup loss.
			# Bind each to its own independently built baseline, not a suppression.
			for prefix, root in [('', build), ('baseline-', baseline)]:
				jobs.append(dict(name=prefix+'model-'+name, argv=registered_command(root, 'struct-elements-' + name), status=99, category='inherited-startup-glib'))
		else:
			jobs.append(dict(name='model-'+name, argv=registered_command(build, 'struct-elements-' + name), status=0))
	for stage in ['syntax', 'semantics', 'core', 'instances', 'cfg', 'ssa', 'nabi', 'cabi', 'llvm']:
		jobs.append(dict(name='compiler-'+stage, argv=[build/'astrac', '--dump-'+stage, ROOT/'tests/struct-elem-1/fixtures/generic-boundaries.astra'], status=0))
	for name, source in [('parse-failure', 'struct S{int x;}void f(){S[1] a={{x=}};}'), ('field-failure', 'struct S{int x;}void f(){S[1] a={{x=1,x=2}};}'), ('cycle-failure', 'struct A{B b;}struct B{A a;}void f(){var a=new A[1];}'), ('borrow-failure', 'struct S{int x;void set(int v){this.x=v;}}int take(owned S[] a){return 1;}void f(){var a=new S[1];a[0].set(take(move a));}')]:
		path = out/(name+'.astra'); path.write_text(source); jobs.append(dict(name=name, argv=[build/'astrac', '--dump-llvm', path], status=1))
	control = out/'ordinary-name-control.astra'; control.write_text('int f(){'+''.join('int C%d=0;' % i for i in range(5001))+'return 0;}')
	assert hashlib.sha256(control.read_bytes()).hexdigest() == '926d5a295e7a62db4fc11c96a59d71437e5cc96026ee092d31dca696a2965927'
	for name, compiler in [('baseline', baseline/'astrac'), ('candidate', build/'astrac')]:
		jobs.append(dict(name=name+'-inherited', argv=[compiler, '--dump-semantics', control], status=99, category='inherited-glib'))
	for name in ['matrix', 'deep-64', 'borrowed', 'effects', 'owned', 'mixed', 'mixed-leaves', 'lifetime', 'generic-boundaries', 'fixed-1024', 'identity', 'boundary', 'caller']:
		for mode in ['O0', 'O2']:
			jobs.append(dict(name='run-'+name+'-'+mode, argv=[(current_output(evidence / 'execution') / f'{name}-{mode}-gcc')], status=0))
	for name in ['destination-bounds', 'source-bounds', 'empty-bounds', 'negative-count', 'oom', 'local-oom', 'parameter-oom', 'field-oom', 'fixed-trap']:
		jobs.append(dict(name='fatal-'+name, argv=[(current_output(evidence / 'execution') / f'{name}-O2-gcc')], status=-4, category='fatal-nonunwinding'))
	client = (current_output(evidence / 'client') / 'relocated/qualification/client')
	for name, full in [('installed-client', False), ('handled-output-failure', True)]:
		jobs.append(dict(name=name, argv=[client/'consumer-0'], status=2 if full else 0, full=full))
	for mode in ['O0', 'O2', 'fma', 'preserved']:
		jobs.append(dict(name='client-'+mode, argv=[(current_output(evidence / 'client') / f'machine/{mode}-gcc')], status=0))
	installed = json.loads(((current_output(evidence / 'client') / 'results.json')).read_text())
	installed_inputs = ['--dump-llvm', 'types.astra', 'state.astra', 'processing.astra', 'main.astra', 'base/diagnostics.astra', 'base/clamp.astra', 'base/contracts.astra', 'hosted/text.astra', '--vapi', 'hosted/math.vapi']
	for name, compiler in [('baseline-installed-compiler', baseline/'astrac'), ('installed-compiler', Path(installed['installed_prefix'])/'bin/astrac')]:
		jobs.append(dict(name=name, argv=[compiler, *installed_inputs], status=99, category='inherited-startup-glib', cwd=client))
	jobs.append(dict(name='installed-fatal-client', argv=[client/'consumer-0', 'bad'], status=-6, category='fatal-nonunwinding'))
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
		elif row['category'] == 'inherited-startup-glib':
			assert row['errors'] == 1 and row['definite'] == 16384 and row['indirect'] == row['possible'] == 0, row
			stacks = []
			for block in re.split(r'\n==\d+==\s*\n', text):
				if '16,384 bytes in 1 blocks are definitely lost' in block:
					assert 'g_malloc' in block and 'call_init' in block, block
					frames = re.findall(r'(?:at|by) 0x[0-9A-F]+: (.+)', block)
					stacks.append([frame_identity(frame) for frame in frames])
			assert len(stacks) == 1 and stacks[0], stacks
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
	startup = {row['name']: row for row in rows if row['category'] == 'inherited-startup-glib'}
	assert len(startup) == 6
	for name in ['model-pipeline', 'model-llvm', 'installed-compiler']:
		assert startup[name]['loss_stack_identities'] == startup['baseline-'+name]['loss_stack_identities'], name
		for suffix in ['stdout', 'stderr']:
			def observed(label):
				data = (out/(label+'.'+suffix)).read_text()
				if name.startswith('model-') and suffix == 'stdout':
					data = re.sub(r'^# random seed:.*\n', '', data, flags=re.M)
					# Keep the slow-test name/line; only its measured duration varies.
					data = re.sub(r'^(# slow test .* executed in )[0-9.]+( secs)$', r'\1ELAPSED\2', data, flags=re.M)
				return data
			assert observed(name) == observed('baseline-'+name), (name, suffix)
	(out/'results.json').write_text(json.dumps(rows, indent='\t')+'\n')
	print(f'{len(rows)} unsuppressed records, with fatal termination and exact inherited GLib controls separate')


if __name__ == '__main__':
	sys.dont_write_bytecode = True
	sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tools/qualification'))
	from output_paths import fresh_output
	sys.argv[-1] = str(fresh_output(sys.argv[-1]))
	qualify(Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve(), Path(sys.argv[3]).resolve())
