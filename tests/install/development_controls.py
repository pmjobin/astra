#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Transport corruption and default-publication refusals, not installer acceptance."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT/'tools/ci'))
from common import external, require, write
from development_bundle import verify_bundle


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--output', type=Path, required=True)
	a = p.parse_args()
	out = external(a.output)
	data = b'TRANSPORT_CONTROL_NOT_AN_INSTALLER\n'
	payload = {'control.deb':data, 'PACKAGES.json':json.dumps({'deb':{'name':'control.deb', 'sha256':hashlib.sha256(data).hexdigest()}}).encode()}
	index = dict(qualification='DEVELOPMENT_UNQUALIFIED', files={name:dict(bytes=len(value), sha256=hashlib.sha256(value).hexdigest()) for name, value in payload.items()})
	payload['MANIFEST.json'] = json.dumps(index).encode()
	def archive(name, members):
		path = out/(name+'.zip')
		with zipfile.ZipFile(path, 'x') as packed:
			for key, value in members.items():
				packed.writestr(key, value)
		return path
	valid = archive('valid', payload)
	verify_bundle(valid)
	controls = []
	for name, changed in [('changed-package', dict(payload, **{'control.deb':b'CHANGED'})), ('missing-package', {k:v for k, v in payload.items() if k != 'control.deb'}), ('extra-member', dict(payload, extra=b'x')), ('stable-label', dict(payload, **{'MANIFEST.json':json.dumps(dict(index, qualification='RELEASE_QUALIFIED')).encode()}))]:
		try:
			verify_bundle(archive(name, changed))
		except ValueError:
			controls.append(name)
		else:
			raise AssertionError('unsafe transport accepted: '+name)
	for name, request in [('absent', None), ('false', {'public_installer_artifacts':False})]:
		approval = out/(name+'.json')
		if request is not None:
			write(approval, request)
		output = out/(name+'.output')
		result = subprocess.run([sys.executable, '-B', ROOT/'tools/ci/development_bundle.py', '--verify', valid, '--approval', approval, '--github-output', output], capture_output=True)
		(out/(name+'.stderr')).write_bytes(result.stderr)
		require(result.returncode == 0 and output.read_text() == 'approved=false\n', 'default publication must remain disabled')
		controls.append('publication-'+name)
	write(out/'result.json', dict(status='DEVELOPMENT_CONTROLS_PASS', controls=controls, scope='Transport fixtures only. No actual installer or owner approval is simulated as acceptance.'))
	print('DEVELOPMENT_CONTROLS_PASS', len(controls))


if __name__ == '__main__':
	main()
