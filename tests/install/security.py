#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Exercise bootstrap trust refusals without executing untrusted compilers."""
import argparse
import io
import json
from pathlib import Path
import subprocess
import sys
import tarfile
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT/'tools/ci'))
from common import external, identify, require, run, sha, verify, write
from trust import extract, fetch, host, seed_manifest
from bootstrap import authenticate_llvm


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--output', type=Path, required=True)
	a = p.parse_args()
	out = external(a.output)
	checks = []
	def refused(name, operation):
		try:
			operation()
		except (OSError, ValueError, subprocess.TimeoutExpired) as error:
			checks.append(dict(name=name, refused=True, exception=type(error).__name__, reason=str(error)))
		else:
			raise ValueError('unsafe input accepted: '+name)
		write(out/'controls.json', checks)
	seed = out/'seed'
	seed.write_bytes(b'authenticated fixture seed, never executed')
	pin = identify(seed)
	verify(seed, pin)
	refused('missing-seed', lambda:verify(out/'absent', pin))
	seed.write_bytes(b'changed input with same cached filename')
	refused('poisoned-cache-modified-seed', lambda:verify(seed, pin))
	refused('forged-checksum-manifest', lambda:verify(seed, dict(pin, sha256='0'*64)))
	altered = json.loads((ROOT/'tools/ci/seed-linux.json').read_text())
	altered.pop('license')
	write(out/'incomplete-manifest.json', altered)
	refused('altered-manifest-missing-provenance', lambda:seed_manifest(out/'incomplete-manifest.json'))
	refused('missing-distribution', lambda:fetch(dict(pin, url=None), out/'download'))
	refused('rolling-distribution', lambda:fetch(dict(pin, url='https://example.invalid/latest/seed'), out/'download'))
	with patch('platform.system', return_value='Windows'):
		refused('wrong-os', lambda:host(dict(os='Linux', machines=['x86_64'])))
	with patch('platform.system', return_value='Linux'), patch('platform.machine', return_value='aarch64'):
		refused('wrong-architecture', lambda:host(dict(os='Linux', machines=['x86_64'])))
	refused('wrong-llvm-version', lambda:authenticate_llvm(out, dict(format='astra-toolchain/1', version='23.1.5')))
	lock = dict(format='astra-toolchain/1', version='23.1.4', os='Linux', machines=['x86_64', 'amd64'], files={'missing-runtime':pin}, config='missing-runtime')
	refused('missing-runtime-dependency', lambda:authenticate_llvm(out, lock))
	for name, member, link in [('parent', '../escape', None), ('absolute', '/escape', None), ('backslash', 'dir\\escape', None), ('symlink', 'link', '../../escape')]:
		archive = out/(name+'.tar')
		with tarfile.open(archive, 'w') as packed:
			info = tarfile.TarInfo(member)
			if link:
				info.type = tarfile.SYMTYPE
				info.linkname = link
				packed.addfile(info)
			else:
				info.size = 1
				packed.addfile(info, io.BytesIO(b'x'))
		refused('archive-'+name, lambda:extract(archive, out/(name+'-extract')))
	archive = out/'symlink-parent.tar'
	with tarfile.open(archive, 'w') as packed:
		info = tarfile.TarInfo('dir')
		info.type = tarfile.SYMTYPE
		info.linkname = 'safe'
		packed.addfile(info)
		info = tarfile.TarInfo('dir/file')
		info.size = 1
		packed.addfile(info, io.BytesIO(b'x'))
	refused('archive-symlink-parent', lambda:extract(archive, out/'symlink-parent-extract'))
	refused('interrupted-bootstrap', lambda:run([sys.executable, '-c', 'import time; time.sleep(5)'], out/'interrupted', timeout=0.05))
	require(json.loads((out/'interrupted/command.json').read_text())['status'] == 'INTERRUPTED', 'interruption was accepted')
	argv = [sys.executable, '-B', ROOT/'tools/ci/bootstrap.py', '--commit', '0'*40, '--llvm', out, '--library', seed, '--library-receipt', out/'absent', '--build', out/'bad-build', '--runtime', out/'bad-runtime']
	result = subprocess.run(list(map(str, argv)), capture_output=True)
	require(result.returncode != 0 and b'checkout identity mismatch' in result.stderr and not (out/'bad-build').exists(), 'checkout identity not checked first')
	(out/'checkout-refusal.stderr').write_bytes(result.stderr)
	checks.append(dict(name='checkout-identity', refused=True))
	for workflow in (ROOT/'.github/workflows').glob('*.yml'):
		text = workflow.read_text()
		require('pull_request_target' not in text and 'secrets.' not in text and 'contents: write' not in text, 'unsafe workflow privilege')
	write(out/'result.json', dict(status='BOOTSTRAP_REFUSALS_PASS', checks=checks, recipe_sha256=sha(__file__), scope='Local actual refusals; no hosted CI or Windows execution credit'))
	print('BOOTSTRAP_REFUSALS_PASS', len(checks))


if __name__ == '__main__':
	main()
