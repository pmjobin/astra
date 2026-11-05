#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Fresh affected-gate replay with original inputs and explicitly routed outputs."""
import argparse
import json
import os
from pathlib import Path
import resource
import subprocess
import time
from state import ROOT, RUNTIME, BUILD, PRIOR, read, sha


def main():
	resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
	p = argparse.ArgumentParser(); p.add_argument('--mode', choices=('O0','O2'), required=True); p.add_argument('--gate', required=True); p.add_argument('--component', type=Path, required=True); p.add_argument('--name', required=True); a = p.parse_args()
	assert a.name.replace('-', '').isalnum()
	old_runtime = PRIOR/('final-v7-'+a.gate+'-'+a.mode)
	old_build = ROOT.parent/'codex/work/astra/build/ownexchange19'/old_runtime.name
	leaf = RUNTIME/a.name; build = BUILD/a.name; leaf.mkdir(exist_ok=False); build.mkdir(exist_ok=False)
	identity = read(a.component.with_suffix('.identity.json')); assert sha(a.component) == identity['sha256']
	assert all(sha(path) == value for group in ('sources','tools') for path, value in identity['identity'][group].items())
	rows = []; environment = dict(os.environ, CCACHE_DISABLE='1'); environment.pop('VALGRIND_OPTS', None)
	for old in read(old_runtime/'commands.json'):
		argv = old['argv'].copy()
		for i, word in enumerate(argv):
			if word.endswith('/astra-llvm-'+a.mode): word = str(a.component)
			if word.startswith(str(old_build)): word = str(build)+word[len(str(old_build)):]
			if word.startswith('--xml-file='+str(old_runtime)): word = word.replace(str(old_runtime), str(leaf), 1)
			if i and argv[i-1] in ('--runtime','--output','--receipt') and word.startswith(str(old_runtime)): word = str(leaf)+word[len(str(old_runtime)):]
			argv[i] = word
			# All source and selection paths stay original, read-only inputs. Commands
			# with writable artifacts route through the new build/runtime arguments.
		start = time.monotonic(); name = old['name']
		with (leaf/(name+'.stdout')).open('xb') as out, (leaf/(name+'.stderr')).open('xb') as err:
			r = subprocess.run(['/usr/bin/time','-v','-o',leaf/(name+'.time'),*argv], cwd=ROOT, stdout=out, stderr=err, env=environment, timeout=2400)
		rows.append(dict(name=name, argv=argv, exit=r.returncode, expected=old['exit'], start=start, end=time.monotonic(), stdout_sha256=sha(leaf/(name+'.stdout')), stderr_sha256=sha(leaf/(name+'.stderr'))))
		(leaf/'commands.json').write_text(json.dumps(rows, indent=2)+'\n')
		print(a.mode, a.gate, name, r.returncode, flush=True)
		assert r.returncode == old['exit'], str(leaf/(name+'.stderr'))
	if a.gate == 'mutations':
		text = (leaf/'mutations.stdout').read_text(); assert text.count('OWNEXCHANGE_MODEL_MUTATION ') == 26 and text.count('OWNEXCHANGE_PHYSICAL_MUTATION ') == 11 and text.count(' LLVM_VALID ') == 11
	(leaf/'result.json').write_text(json.dumps(dict(status='PASS', gate=a.gate, mode=a.mode, component_sha256=sha(a.component), original_commands_sha256=sha(old_runtime/'commands.json'), commands=rows, limitation='Fresh execution of this exact affected gate. Historical proof outputs are not reattributed; higher-level corpus counts are independently reconciled.'), indent=2)+'\n')


if __name__ == '__main__':
	main()
