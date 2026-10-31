# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Bind the Braid regression and explicit historical replay to their inputs."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'tests/support'))
from input_guard import InputGuard as FreezeGuard


def current_include_flags(output):
	"""Resolve legacy quoted fixture includes without changing the sealed bytes."""
	routing = Path(output).resolve() / 'current-includes'
	assert not routing.is_relative_to(ROOT)
	search = routing / 'a/b/c'
	search.mkdir(parents=True, exist_ok=True)
	(routing / 'lib').mkdir(exist_ok=True)
	alias = routing / 'lib/astra'
	if not alias.is_symlink():
		alias.symlink_to(ROOT / 'lib/runtime', target_is_directory=True)
	assert alias.resolve(strict=True) == ROOT / 'lib/runtime'
	return ['-iquote', search]


def braid_guard(compiler, profile, prefix=None, extra_inputs=()):
	here = Path(__file__).resolve().parent
	inputs = [path for path in here.iterdir() if path.is_file()]
	inputs += [ROOT / 'tests/systems-dsp-9/support.py', ROOT / 'tests/concurrency-runtime-13/sanitizers.py']
	inputs.extend(extra_inputs)
	if prefix is not None:
		prefix = Path(prefix).resolve(strict=True)
		inputs += [prefix / 'lib/liburing.a', *[p for p in (prefix / 'include').rglob('*') if p.is_file()]]
	return FreezeGuard(ROOT, compiler, ROOT / 'docs/runtime-composition-17-freeze-4.json', profile, inputs)
