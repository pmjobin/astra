#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Rebind exact captured tool bytes in an ephemeral namespace after host updates."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import time
import urllib.request
from state import ROOT, load_module, read, sha


def package(url, wanted):
	with urllib.request.urlopen(url, timeout=60) as response:
		data = response.read()
		metadata = dict(url=url, final_url=response.url, headers=dict(response.headers), bytes=len(data), sha256=hashlib.sha256(data).hexdigest())
	result = subprocess.run(['rpm2cpio'], input=data, capture_output=True, check=True)
	archive, offset, found = result.stdout, 0, {}
	while offset + 110 <= len(archive):
		header = archive[offset:offset+110]; assert header[:6] in (b'070701', b'070702')
		fields = [int(header[6+i*8:14+i*8], 16) for i in range(13)]
		size, namesize = fields[6], fields[11]
		name = archive[offset+110:offset+110+namesize-1].decode()
		offset = (offset+110+namesize+3) & ~3
		if name in wanted: found[name] = archive[offset:offset+size]
		offset = (offset+size+3) & ~3
		if name == 'TRAILER!!!': break
	assert set(found) == set(wanted)
	return metadata, found


def main():
	p = argparse.ArgumentParser(); p.add_argument('mode', choices=('prepare', 'run')); p.add_argument('--version', required=True); p.add_argument('--component', type=Path, required=True); p.add_argument('--command', nargs=argparse.REMAINDER)
	a = p.parse_args(); assert a.version.isalnum()
	paths = load_module('capsule_paths', ROOT/'tests/selfhost-effects/recover-build.py')
	leaf = paths.RUNTIME/('toolchain-capsule-'+a.version)
	identity_path = a.component.with_suffix('.identity.json'); identity = read(identity_path)
	assert sha(a.component) == identity['sha256']
	expected = dict(identity['identity']['sources'])
	for name, digest in identity['identity']['tools'].items():
		assert name not in expected or expected[name] == digest
		expected[name] = digest
	if a.mode == 'prepare':
		leaf.mkdir(); mappings, observations, packages = [], [], []
		witnesses = paths.RUNTIME.parent/'effects25-r5/canonical-input-witnesses/blobs'
		obtain = {
			'/usr/lib64/llvm23/bin/llvm-config': ('https://kojipkgs.fedoraproject.org/packages/llvm/23.1.4/1.fc45/x86_64/llvm-devel-23.1.4-1.fc45.x86_64.rpm', './usr/lib64/llvm23/bin/llvm-config'),
			'/usr/lib64/libpcre2-8.so.0.15.0': ('https://kojipkgs.fedoraproject.org/packages/pcre2/10.47/1.fc45.2/x86_64/pcre2-10.47-1.fc45.2.x86_64.rpm', './usr/lib64/libpcre2-8.so.0.15.0'),
		}
		for name, digest in expected.items():
			path = Path(name); actual = sha(path) if path.is_file() else None
			if actual == digest: continue
			assert not path.is_relative_to(ROOT), name
			observations.append(dict(path=name, expected_sha256=digest, current_sha256=actual, current_resolved_path=str(path.resolve())))
			witness = witnesses/digest
			if not witness.is_file():
				url, member = obtain[name]; metadata, found = package(url, [member]); packages.append(metadata)
				assert hashlib.sha256(found[member]).hexdigest() == digest, name
				witness = leaf/digest; witness.write_bytes(found[member]); witness.chmod(0o755 if name.endswith('llvm-config') else 0o644)
			assert sha(witness) == digest
			mappings.append(dict(path=name, resolved_path=str(path.resolve()), witness=str(witness), sha256=digest, bytes=witness.stat().st_size))
		assert len(mappings) == 4
		result = dict(status='EXACT_CAPTURED_TOOLCHAIN_CAPSULE', component_identity=str(identity_path), component_identity_sha256=sha(identity_path), observations=observations, mappings=mappings, packages=packages, limitation='Host packages were updated externally to LLVM23.1.5 and PCRE2. Exact original bytes are independently hash-matched, then mounted read-only only inside a temporary child namespace. No host package, installed workflow, source, product identity or historical receipt is modified or repinned. Downloaded RPMs are decoded in memory; only the exact required ELF members are retained, with package URL/hash/headers recorded.')
		(leaf/'result.json').write_text(json.dumps(result, indent=2)+'\n')
		print(result['status'], len(mappings), flush=True)
		return
	result = read(leaf/'result.json'); assert result['status'] == 'EXACT_CAPTURED_TOOLCHAIN_CAPSULE' and result['component_identity_sha256'] == sha(identity_path)
	command = a.command[1:] if a.command[:1] == ['--'] else a.command; assert command
	before = {row['path']: sha(row['path']) if Path(row['path']).is_file() else None for row in result['mappings']}
	temporary = leaf/'tmp'; temporary.mkdir(exist_ok=True)
	argv = ['bwrap', '--die-with-parent', '--unshare-user', '--ro-bind', '/', '/', '--dev-bind', '/dev', '/dev', '--proc', '/proc', '--bind', str(paths.RUNTIME), str(paths.RUNTIME), '--bind', str(paths.BUILD), str(paths.BUILD), '--bind', str(temporary), '/tmp', '--setenv', 'TMPDIR', str(temporary), '--overlay-src', '/usr/lib64', '--tmp-overlay', '/usr/lib64']
	for row in result['mappings']:
		assert sha(row['witness']) == row['sha256'] == expected[row['path']]
		argv += ['--ro-bind', row['witness'], row['resolved_path']]
		if row['path'].endswith('libpcre2-8.so.0.15.0'):
			# The current SONAME symlink selects a different filename. Bind both
			# paths so the exact captured dependency is actually loaded as well.
			argv += ['--ro-bind', row['witness'], str(Path('/usr/lib64/libpcre2-8.so.0').resolve())]
	argv += ['--', *command]
	start = time.monotonic(); run = subprocess.run(argv, cwd=ROOT)
	after = {row['path']: sha(row['path']) if Path(row['path']).is_file() else None for row in result['mappings']}
	assert before == after
	receipt = dict(argv=argv, exit=run.returncode, monotonic_start=start, monotonic_end=time.monotonic(), capsule_sha256=sha(leaf/'result.json'), host_before=before, host_after=after)
	(leaf/('run-'+str(time.time_ns())+'.json')).write_text(json.dumps(receipt, indent=2)+'\n')
	raise SystemExit(run.returncode)


if __name__ == '__main__':
	main()
