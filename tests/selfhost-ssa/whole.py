#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""The complete current source remains deferred, with zero whole-program proofs."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import time
from build import ROOT, core


def main():
	p = argparse.ArgumentParser()
	for key in ('build', 'runtime'):
		p.add_argument('--'+key, type=Path, required=True)
	p.add_argument('--mode', action='append')
	a = p.parse_args()
	a.runtime.mkdir(parents=True, exist_ok=False)
	paths = [*(p for group in ('source', 'syntax', 'semantic', 'core', 'cfg', 'ssa') for p in sorted((ROOT/'compiler'/group).glob('*.astra'))), *[ROOT/('lib/astra/'+name+'.astra') for name in core.base.LIBRARIES]]
	hashes = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
	(a.runtime/'inputs.json').write_text(json.dumps(hashes, indent=2)+'\n')
	commands = []
	for mode in a.mode or ('O0', 'O2'):
		exe = a.build/('astra-ssa-'+mode)
		identity = json.loads(exe.with_suffix('.identity.json').read_text())
		assert hashlib.sha256(exe.read_bytes()).hexdigest() == identity['sha256']
		assert all(identity['identity']['sources'][p] == h for p,h in hashes.items())
		for command in ('--admit', '--core', '--cfg', '--ssa'):
			start = time.monotonic()
			r = subprocess.run(['/usr/bin/time', '-v', '-o', str(a.runtime/(mode+'-'+command[2:]+'.time')), exe, command, *paths], capture_output=True)
			(a.runtime/(mode+'-'+command[2:]+'.stdout')).write_bytes(r.stdout)
			(a.runtime/(mode+'-'+command[2:]+'.stderr')).write_bytes(r.stderr)
			commands.append(dict(argv=list(map(str, [exe, command, *paths])), exit=r.returncode, monotonic_start=start, monotonic_end=time.monotonic()))
			(a.runtime/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
			assert r.returncode == 3, (mode, command, r.returncode, r.stderr.decode()[-1000:])
			if command == '--admit':
				assert r.stdout.startswith(b'astra-flow/3\n')
				assert all(int(x.split()[3]) == 0 for x in r.stdout.splitlines() if x.startswith(b'PROOF '))
			else:
				assert not r.stdout
				assert r.stderr.startswith(b'SSA_DEFERRED' if command == '--ssa' else b'CFG_DEFERRED' if command == '--cfg' else b'CORE_DEFERRED')
	(a.runtime/'result.json').write_text(json.dumps(dict(whole_compiler='DEFERRED', whole_program_proofs=0, source_count=len(paths)), indent=2)+'\n')


if __name__ == '__main__':
	main()
