#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Authenticate the exact original compiler and LLVM frontend bytes."""
import argparse
import hashlib
import json
from pathlib import Path
import platform
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT.parent/'codex/work/astra'
EXPECTED = {
	'opt': '2f287dfa714b32026b70f5712230d9e49644fd9aeba470b0a9d772be73caf845',
	'llc': '35be28120a2d05e9fad67200a16ef5d4a661bd5ffc838a7db30738e58cef5bdc',
	'llvm-config': 'f1c7b4c56e3f0c2ac6991423ea9b68eee5690f9e757cbb4b37ca40b84f8a3047',
}
FILES = {
	'/usr/lib64/libLLVM.so.23.1': '3149b73c3118dee2d2829a210b422ca89a4aa0064b57e77936ede12bdcfe750d',
	'/usr/lib64/llvm23/include/llvm-c/Core.h': '0eaa6a9bf72d28e33590fd217f89f413fb418aed4cba9557177eb5b2388d7a24',
	'/usr/lib64/llvm23/include/llvm/Config/llvm-config-x86_64.h': '9535b0ce77d3ed8d86d3e67fe9f55cddc63fe0f382de2311e49c2079aa1f8606',
}


def digest(path):
	with path.open('rb') as stream:
		return hashlib.file_digest(stream, 'sha256').hexdigest()


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--compiler', type=Path, required=True)
	p.add_argument('--receipt', type=Path, required=True)
	a = p.parse_args()
	assert a.receipt.is_absolute() and a.receipt.resolve().is_relative_to((WORK/'runtime').resolve())
	assert a.receipt.parent.is_dir() and not a.receipt.exists()
	rows = []
	failed = []
	inputs = {str(a.compiler): 'e3b2a5d6a4b9c5a42becbc3704f2d062489fb6f99a5ed1727461dfef4cf8681b', **FILES}
	for name, expected in EXPECTED.items():
		path = shutil.which(name)
		if path is None:
			failed.append('missing '+name)
		else:
			inputs[path] = expected
	for name, expected in inputs.items():
		path = Path(name)
		actual = digest(path) if path.is_file() else None
		rows.append(dict(path=name, resolved_path=str(path.resolve()), sha256=actual, expected_sha256=expected, matched=actual == expected))
		if actual != expected:
			failed.append(name)
	versions = {}
	for name in EXPECTED:
		if shutil.which(name):
			result = subprocess.run([name, '--version'], capture_output=True, text=True)
			versions[name] = dict(exit=result.returncode, stdout=result.stdout, stderr=result.stderr)
			if result.returncode or '23.1.4' not in result.stdout:
				failed.append(name+' version')
	if platform.system() != 'Linux' or platform.machine() != 'x86_64':
		failed.append('GNU/Linux x86-64 host')
	result = dict(format='astra-compiler26-exact-toolchain/1', status='BASELINE_MISMATCH' if failed else 'EXACT_BASELINE_AUTHENTICATED', files=rows, versions=versions, failures=failed, frontend_provenance='Fedora llvm-23.1.4-1.fc45.x86_64 Koji RPM; package SHA256 f1ad284d1d42569206baab982e47542641cb85cb800a771874877397647af065. HTTPS, header and payload digests verified; OpenPGP signatures absent. llvm-config and SDK anchors independently match original R5 witnesses.', host_installation_changed=False)
	a.receipt.write_text(json.dumps(result, indent=2)+'\n')
	print(result['status'])
	raise SystemExit(2 if failed else 0)


if __name__ == '__main__':
	main()
