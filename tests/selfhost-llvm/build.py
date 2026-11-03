#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Build the LLVM component with the established exact-product recipe."""
import argparse
import ctypes
import importlib.util
import json
import os
import re
import shutil
from pathlib import Path
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('core_build', ROOT/'tests/selfhost-coreir/build.py')
core = importlib.util.module_from_spec(spec)
spec.loader.exec_module(core)


def sources():
	return [*sorted((ROOT/'compiler/core').glob('*.astra')), *sorted((ROOT/'compiler/cfg').glob('*.astra')), ROOT/'tests/selfhost-coreir/mutations.astra', ROOT/'tests/selfhost-cfg/mutations.astra', *sorted((ROOT/'compiler/ssa').glob('*.astra')), ROOT/'tests/selfhost-ssa/predecessor.astra', ROOT/'tests/selfhost-ssa/mutations.astra', ROOT/'tests/selfhost-ssa/graphs.astra', ROOT/'tests/selfhost-llvm/ssa-cli.astra', *sorted((ROOT/'compiler/backend/llvm').glob('*.astra'))]


def main():
	p = argparse.ArgumentParser()
	for key in ('compiler', 'build', 'runtime'):
		p.add_argument('--'+key, type=Path, required=True)
	p.add_argument('--mode', action='append')
	p.add_argument('--check', action='store_true')
	a = p.parse_args()
	assert all(not x.resolve().is_relative_to(ROOT) for x in (a.build, a.runtime))
	a.build.mkdir(parents=True, exist_ok=True)
	attempt = a.runtime/('build-'+str(time.time_ns()))
	attempt.mkdir(parents=True)
	def capture(argv, name, details=None):
		if argv is None:
			(attempt/(name+'.json')).write_text(json.dumps(details, indent=2)+'\n')
			return b''
		if a.check and name.startswith('ownflow-'):
			argv = [*argv[:2], argv[2], '--dump-cfg', *argv[4:argv.index('--link-object')]]
		start = time.monotonic()
		r = subprocess.run(list(map(str, argv)), cwd=a.build, capture_output=True, env=dict(os.environ, CCACHE_DISABLE='1'))
		(attempt/(name+'.stdout')).write_bytes(r.stdout); (attempt/(name+'.stderr')).write_bytes(r.stderr)
		(attempt/(name+'.json')).write_text(json.dumps(dict(argv=list(map(str, argv)), exit=r.returncode, monotonic_start=start, monotonic_end=time.monotonic()), indent=2)+'\n')
		print(name, r.returncode, flush=True)
		assert r.returncode == 0, r.stderr.decode(errors='replace').split('Command being timed')[0][:3000]
		if a.check and name.startswith('ownflow-'): raise SystemExit(0)
		return r.stdout
	version = subprocess.check_output(['llvm-config', '--version'], text=True).strip()
	assert version == '22.1.8', version
	flags = subprocess.check_output(['llvm-config', '--cflags'], text=True).split()
	libdir = Path(subprocess.check_output(['llvm-config', '--libdir'], text=True).strip())
	shim = a.build/'llvm-capi.o'
	deps = subprocess.check_output(['gcc', *flags, '-M', ROOT/'compiler/backend/llvm/capi.c'], text=True).replace('\\\n', ' ').split(':', 1)[1].split()
	gcc = Path(shutil.which('gcc')).resolve()
	actual_gcc = gcc
	if gcc.name == 'ccache':
		actual_gcc = next((Path(entry)/'gcc').resolve() for entry in os.get_exec_path() if (Path(entry)/'gcc').is_file() and (Path(entry)/'gcc').resolve().name != 'ccache')
	cc1 = Path(subprocess.check_output(['gcc', '-print-prog-name=cc1'], text=True).strip()).resolve()
	identity = dict(inputs={p: core.base.sha(p) for p in deps}, tools={str(p): core.base.sha(p) for p in (gcc, actual_gcc, cc1)}, flags=['-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', *flags], environment={k: os.environ.get(k) for k in ('PATH','CPATH','C_INCLUDE_PATH','LIBRARY_PATH','CCACHE_COMPILER','CCACHE_PATH')})
	cache = shim.with_suffix('.identity.json')
	old = json.loads(cache.read_text()) if cache.exists() else None
	if not shim.exists() or old != dict(inputs=identity, sha256=core.base.sha(shim)):
		capture(['gcc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', *flags, '-c', ROOT/'compiler/backend/llvm/capi.c', '-o', shim], 'llvm-capi')
		cache.write_text(json.dumps(dict(inputs=identity, sha256=core.base.sha(shim)), indent=2)+'\n')
	defined = set(re.findall(r'\b(llvm(?:12|13)_\w+)$', subprocess.check_output(['nm', '--defined-only', shim], text=True), re.M))
	library = ctypes.CDLL(str(libdir/'libLLVM-22.so'))
	imports = re.findall(r'extern\(C\) (?:void\*|u64|int|void|f32|f64) (\w+)\(', (ROOT/'compiler/backend/llvm/capi.astra').read_text())
	missing = [name for name in imports if name not in defined and not hasattr(library, name)]
	assert not missing, ('missing qualified LLVM C ABI symbols', missing)
	(attempt/'llvm-symbols.json').write_text(json.dumps(dict(library=core.base.sha(libdir/'libLLVM-22.so'), imports=imports, shim_symbols=sorted(defined)), indent=2)+'\n')
	products = core.base.build(a.compiler.resolve(), a.build.resolve(), capture, a.mode or ('O0', 'O2'), consumer=ROOT/'tests/selfhost-llvm/query.astra', with_flow=True, extra_sources=sources(), product_prefix='astra-llvm-', link_objects=[shim], link_libraries=['LLVM-22'], link_inputs=[libdir/'libLLVM-22.so', *map(Path, deps), Path(__file__), ROOT/'tests/selfhost-typecore/build.py', ROOT/'tests/selfhost-coreir/build.py'])
	(attempt/'products.json').write_text(json.dumps(products, indent=2)+'\n')


if __name__ == '__main__':
	main()
