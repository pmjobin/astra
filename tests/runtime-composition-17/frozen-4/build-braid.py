#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Build the frozen weighted range-alignment product using explicit source and output paths."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import subprocess
import time
from freeze_guard import braid_guard, current_include_flags

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent


def main():
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument('--compiler', type=Path, required=True)
	parser.add_argument('--uring-prefix', type=Path, required=True)
	parser.add_argument('--output', type=Path, required=True)
	parser.add_argument('--optimization', choices=['0', '1', '2'], default='2')
	parser.add_argument('--regression', action='store_true', help='current source replay; no historical frozen-challenge credit')
	parser.add_argument('--c-source', type=Path, action='append', default=[])
	parser.add_argument('--c-flag', action='append', default=[])
	parser.add_argument('--link-flag', action='append', default=[])
	args = parser.parse_args()
	compiler = args.compiler.resolve(strict=True); prefix = args.uring_prefix.resolve(strict=True)
	guard = braid_guard(compiler, 'regression' if args.regression else 'frozen', prefix, args.c_source)
	output = args.output.resolve(); assert not output.is_relative_to(ROOT)
	output.mkdir(parents=True, exist_ok=True)
	sources = [HERE / ('braid-' + name + '.astra') for name in ['model', 'common', 'setup', 'workers', 'service']]
	sources += [ROOT / 'lib/astra/hosted/network.astra', ROOT / 'lib/astra/async/payload.astra']
	vapis = [ROOT / 'lib/bindings/memory/contexts.vapi', ROOT / 'lib/bindings/async/composition.vapi', ROOT / 'lib/bindings/async/payload.vapi', HERE / 'braid-host.vapi']
	providers = [HERE / 'braid-host.c', HERE / 'braid-provider.c', ROOT / 'lib/runtime/async/composed.c', ROOT / 'lib/runtime/async/linux.c', ROOT / 'lib/runtime/runtime/context-17.c', ROOT / 'lib/runtime/platform/network-posix.c', ROOT / 'lib/runtime/platform/text-posix.c', ROOT / 'lib/runtime/platform/args-posix.c']
	providers.append(ROOT / 'lib/runtime/runtime/monitors-13.c')
	providers += [path.resolve(strict=True) for path in args.c_source]
	obj = output / ('braid-service-O' + args.optimization + '.o'); product = obj.with_suffix('')
	commands = [
		[compiler, '-O' + args.optimization, '--entry-object', *sources, *[value for path in vapis for value in ['--vapi', path]], '-o', obj],
		['cc', '-O2', '-g', '-std=c11', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', *current_include_flags(output), *args.c_flag, obj, *providers, '-isystem', prefix / 'include', prefix / 'lib/liburing.a', *args.link_flag, '-o', product],
	]
	receipt = dict(commands=[], files=[], original_freeze=4, regression_only=args.regression,
		qualification_guard=guard.record())
	for command in commands:
		guard.check()
		command = [str(value) for value in command]; start = time.monotonic()
		result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, env=dict(os.environ, CCACHE_DISABLE='1', PYTHONDONTWRITEBYTECODE='1'))
		receipt['commands'].append(dict(command=command, exit=result.returncode, stdout=result.stdout, stderr=result.stderr, seconds=time.monotonic() - start))
		(output / ('build-O' + args.optimization + '.json')).write_text(json.dumps(receipt, indent=2) + '\n')
		if result.returncode: raise RuntimeError(receipt['commands'][-1])
	guard.check()
	for path in [compiler, *sources, *vapis, *providers, HERE / 'braid-provider.h', prefix / 'lib/liburing.a', obj, product, Path(__file__)]:
		receipt['files'].append(dict(path=str(path), sha256=hashlib.sha256(path.read_bytes()).hexdigest()))
	(output / ('build-O' + args.optimization + '.json')).write_text(json.dumps(receipt, indent=2) + '\n')
	print(product)


if __name__ == '__main__':
	main()
