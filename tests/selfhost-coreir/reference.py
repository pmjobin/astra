#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""C0 execution is an independent oracle, never execution of native Core."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import resource
import subprocess
import sys
import time
from corpus import additional

ROOT = Path(__file__).resolve().parents[2]


def main():
	p = argparse.ArgumentParser()
	for name in ('compiler', 'build', 'runtime', 'baseline', 'additional'):
		p.add_argument('--'+name, type=Path, required=True)
	a = p.parse_args()
	resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
	a.runtime.mkdir(parents=True, exist_ok=False)
	a.build.mkdir(parents=True, exist_ok=True)
	subprocess.run([sys.executable, '-B', ROOT/'tests/selfhost-semadmit/reference.py', '--compiler', a.compiler, '--build', a.build/'semadmit', '--runtime', a.runtime/'semadmit', '--baseline', a.baseline], check=True)
	entries = {x['name']: x for x in json.loads((a.additional/'frozen.json').read_text())}
	commands = []
	for item in additional():
		if item['status'] != 0: continue
		entry = entries[item['name']]
		assert hashlib.sha256(Path(entry['paths'][0]).read_bytes()).hexdigest() == entry['sha256']
		for mode in ('O0', 'O2'):
			exe = a.build/(item['name']+'-'+mode)
			for stage, argv, expected in [('compile', [a.compiler, '-'+mode, *entry['paths'], '-o', exe], 0), ('execute', [exe], item['exit']), ('memory', ['valgrind', '--default-suppressions=no', '--error-exitcode=97', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=definite,indirect,possible', exe], item['exit'])]:
				name = item['name']+'-'+mode+'-'+stage
				t = time.monotonic()
				r = subprocess.run(['/usr/bin/time', '-v', '-o', str(a.runtime/(name+'.time')), *map(str, argv)], cwd=a.build, capture_output=True, env=dict(os.environ, CCACHE_DISABLE='1'))
				(a.runtime/(name+'.stdout')).write_bytes(r.stdout)
				(a.runtime/(name+'.stderr')).write_bytes(r.stderr)
				commands.append(dict(name=name, argv=list(map(str, argv)), exit=r.returncode, seconds=time.monotonic()-t))
				(a.runtime/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
				assert r.returncode == expected, (name, r.returncode, r.stderr.decode())
				if item.get('fatal_signal') and stage != 'compile': assert 'Command terminated by signal '+str(item['fatal_signal']) in (a.runtime/(name+'.time')).read_text()
				if stage == 'memory': assert b'ERROR SUMMARY: 0 errors' in r.stderr and not re.search(rb'(?:definitely|indirectly|possibly) lost: [1-9]', r.stderr)


if __name__ == '__main__':
	main()
