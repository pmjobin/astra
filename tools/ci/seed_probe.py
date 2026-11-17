#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Short PR lane: authenticated seed emits and runs new native objects."""
import argparse
import ctypes
import json
from pathlib import Path

from common import ROOT, clean_environment, external, identify, require, run, sha, verify, write
from trust import seed_manifest


def main():
	p = argparse.ArgumentParser(description=__doc__)
	for key in ('seed', 'library', 'library_receipt', 'output'):
		p.add_argument('--'+key.replace('_', '-'), type=Path, required=True)
	a = p.parse_args()
	manifest = seed_manifest(ROOT/'tools/ci/seed-linux.json')
	verify(a.seed, manifest)
	receipt = json.loads(a.library_receipt.read_text())
	verify(a.library, receipt['library'])
	require(receipt['status'] == 'LLVM_DYLIB_BUILT_NOT_QUALIFIED', 'diagnostic dependency is not the smoke baseline')
	require(receipt['archive_sha256'] == json.loads((ROOT/'tools/ci/llvm-linux.json').read_text())['archive']['sha256'], 'LLVM provenance mismatch')
	lock = json.loads((ROOT/'tools/ci/llvm-linux.json').read_text())
	require(bool(receipt['inputs']), 'LLVM archive provenance is empty')
	require(all(lock['files']['lib/'+Path(name).name]['sha256'] == digest for name, digest in receipt['inputs'].items()), 'untrusted LLVM archive input')
	out = external(a.output)
	env = clean_environment()
	env['LD_LIBRARY_PATH'] = str(a.library.resolve().parent)
	llvm = ctypes.CDLL(str(a.library.resolve()))
	llvm.LLVMGetVersion.argtypes = [ctypes.POINTER(ctypes.c_uint)]*3
	llvm.LLVMGetVersion.restype = None
	version = [ctypes.c_uint() for unused in range(3)]
	llvm.LLVMGetVersion(*[ctypes.byref(field) for field in version])
	require([field.value for field in version] == [23, 1, 4], 'wrong actual LLVM C API version')
	help_text, _ = run([a.seed, '--help'], out/'help', env)
	require(b'Explicit sources form one program' in help_text, 'not an Astra seed')
	run(['cc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-c', ROOT/'tests/install/abi.c', '-o', out/'abi.o'], out/'c-abi-provider', env)
	products = []
	for mode in ('O0', 'O2'):
		for name, foreign, expected in [('main', [], b''), ('owners', [out/'abi.o'], b'Astra C ABI: 5 drops, sum 30\n')]:
			label = name+'-'+mode
			obj, exe = out/(label+'.o'), out/label
			run([a.seed, '-c', '-'+mode, '-o', obj, ROOT/('tests/install/'+name+'.astra')], out/(label+'-compile'), env)
			require(obj.read_bytes()[:5] == b'\x7fELF\x02', 'not a native ELF object')
			run(['cc', '-no-pie', obj, *foreign, '-o', exe], out/(label+'-link'), env)
			stdout, stderr = run([exe], out/(label+'-run'), env)
			require(stdout == expected and not stderr, 'unexpected program streams')
			products.append(dict(profile=mode, case=name, object=identify(obj), executable=identify(exe), expected_stdout=expected.decode()))
		for name, diagnostic in [('type', b'type'), ('owner', b'SSA verification failed')]:
			for sentinel in (False, True):
				obj = out/('bad-'+name+'-'+mode+'.o')
				if sentinel:
					obj.write_bytes(b'CI_REFUSAL_SENTINEL\n')
				_, stderr = run([a.seed, '-c', '-'+mode, '-o', obj, ROOT/('tests/install/negative-'+name+'.astra')], out/('negative-'+name+'-'+mode+'-'+str(sentinel)), env, expected=1)
				require(diagnostic in stderr and (obj.read_bytes() == b'CI_REFUSAL_SENTINEL\n' if sentinel else not obj.exists()), 'negative did not preserve output contract')
	write(out/'result.json', dict(status='AUTHENTICATED_SEED_NATIVE_SMOKE_PASS', seed=identify(a.seed), seed_identity=manifest['id'], producer=manifest['producer'], llvm_c_api_version=[23, 1, 4], library=identify(a.library), products=products, fixture_inputs={str(p.relative_to(ROOT)):identify(p) for p in sorted((ROOT/'tests/install').iterdir()) if p.name in ('main.astra', 'owners.astra', 'abi.c', 'negative-type.astra', 'negative-owner.astra')}, current_compiler_generations_built=0, strict_compiler_memory='NOT_QUALIFIED_ORIGINAL_LLVM_ARTIFACT_REMAINS_NOT_PASS', public_release=False, scope='The authenticated 27-D Stage3 O2 seed, produced by Stage2 O2, compiles four fresh native targets with exact original LLVM 23.1.4. O0/O2 compile/link/execute, C ABI/drop observations and eight diagnostic/output refusals only. No current compiler generation, full strict-memory qualification, installer, Windows or release PASS.'))


if __name__ == '__main__':
	main()
