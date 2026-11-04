#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Audit exact predecessor tools before treating a process as a source oracle."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]
C0_SHA = '908f8db9e524cf94b7651f36e9bf0ff32c98ef64cb7eacd737c3b5f680064b45'


def sha(path):
	return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def command(argv):
	start = time.monotonic()
	try:
		r = subprocess.run(list(map(str, argv)), capture_output=True, text=True, timeout=30)
		return dict(argv=list(map(str, argv)), exit=r.returncode, stdout=r.stdout, stderr=r.stderr, monotonic_start=start, monotonic_end=time.monotonic())
	except (OSError, subprocess.TimeoutExpired) as error:
		return dict(argv=list(map(str, argv)), error=str(error), monotonic_start=start, monotonic_end=time.monotonic())


def audit(compiler, components):
	rows, blockers = [], []
	for path in [compiler, *components]:
		row = dict(path=str(path), present=path.is_file())
		if not path.is_file():
			blockers.append('missing product: '+str(path)); rows.append(row); continue
		row['sha256'] = sha(path)
		if path == compiler:
			row['expected_sha256'] = C0_SHA
			if row['sha256'] != C0_SHA: blockers.append('C0 binary identity mismatch')
		else:
			sidecar = path.with_suffix('.identity.json')
			if not sidecar.is_file():
				blockers.append('missing component identity: '+str(sidecar))
			else:
				identity = json.loads(sidecar.read_text()); row['sidecar_sha256'] = sha(sidecar)
				row['expected_sha256'] = identity['sha256']
				if row['sha256'] != identity['sha256']: blockers.append('component binary identity mismatch: '+str(path))
				drift = []
				for section in ('sources', 'tools'):
					for name, expected in identity['identity'][section].items():
						dependency = Path(name)
						actual = sha(dependency) if dependency.is_file() else None
						if actual != expected: drift.append(dict(section=section, path=name, expected_sha256=expected, actual_sha256=actual))
				row['dependency_drift'] = drift
				if drift: blockers.append('exact component dependency drift: '+str(path))
		row['ldd'] = command(['ldd', path]); row['startup'] = command([path, '--version'])
		if row['startup'].get('exit') == 127 or 'error' in row['startup']: blockers.append('product cannot start: '+str(path))
		rows.append(row)
	llvm = command(['llvm-config', '--version'])
	if llvm.get('stdout', '').strip() != '22.1.8': blockers.append('qualified LLVM 22.1.8 unavailable through llvm-config')
	pins = json.loads((ROOT/'format/toolchain.json').read_text()); format_tools = {}
	for name, pin in pins.items():
		path = compiler if name == 'astrac' else shutil.which(pin['command'])
		actual = sha(path) if path and Path(path).is_file() else None
		format_tools[name] = dict(path=str(path) if path else None, expected_sha256=pin['sha256'], actual_sha256=actual, matches=actual == pin['sha256'])
	return dict(status='ENVIRONMENT_BLOCKED' if blockers else 'READY', qualified_llvm='22.1.8', llvm=llvm, products=rows, blockers=blockers, formatter_tools=format_tools, limitation='Existing binary hashes and source facts do not qualify changed runtime libraries. A loader failure is neither a semantic rejection nor a native execution.')


def main():
	p = argparse.ArgumentParser()
	p.add_argument('--compiler', type=Path, required=True)
	p.add_argument('--component', type=Path, action='append', required=True)
	p.add_argument('--output', type=Path, required=True)
	a = p.parse_args()
	assert not a.output.resolve().is_relative_to(ROOT)
	result = audit(a.compiler, a.component)
	with a.output.open('x') as out: out.write(json.dumps(result, indent=2)+'\n')
	print(result['status']+': '+ '; '.join(result['blockers']))
	return 0 if result['status'] == 'READY' else 2


if __name__ == '__main__':
	raise SystemExit(main())
