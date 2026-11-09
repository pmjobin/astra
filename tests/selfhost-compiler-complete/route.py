#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Route inherited qualification recipes and children into explicit task leaves."""
import argparse
import importlib.util
import os
from pathlib import Path
import sys

from run import ROOT, WORK


def main():
	p = argparse.ArgumentParser(description=__doc__, add_help=False)
	p.add_argument('--build-root', type=Path, default=os.environ.get('ASTRA_COMPILER26_BUILD'))
	p.add_argument('--runtime-root', type=Path, default=os.environ.get('ASTRA_COMPILER26_RUNTIME'))
	a, remaining = p.parse_known_args()
	assert a.build_root and a.runtime_root and remaining
	for path, parent in ((a.build_root, WORK/'build'), (a.runtime_root, WORK/'runtime')):
		assert path.is_absolute() and path.resolve().is_relative_to(parent.resolve()) and path.is_dir()
		assert all(not entry.is_symlink() for entry in (path, *path.parents))
	assert (a.runtime_root/'initial.json').is_file()
	os.environ['ASTRA_COMPILER26_BUILD'] = str(a.build_root)
	os.environ['ASTRA_COMPILER26_RUNTIME'] = str(a.runtime_root)
	os.environ['PM_CODEX_BUILD_DIR'] = str(a.build_root.parent)
	os.environ['PM_CODEX_RUNTIME_DIR'] = str(a.runtime_root.parent)
	sys.path.insert(0, str(ROOT/'tests/selfhost-effects'))
	import state
	original = state.bounded_run
	entry = ROOT/'tests/selfhost-effects/r5-resume.py'
	def run(argv, **kwargs):
		return original([Path(__file__) if str(arg) == str(entry) else arg for arg in argv], **kwargs)
	state.bounded_run = run
	spec = importlib.util.spec_from_file_location('compiler26_qualification_route', entry)
	module = importlib.util.module_from_spec(spec)
	spec.loader.exec_module(module)
	module.RUNTIME = a.runtime_root.resolve()
	module.BUILD = a.build_root.resolve()
	module.PRIOR = WORK/'runtime/effects25-r5'
	sys.argv = [str(Path(__file__)), *remaining]
	module.main()


if __name__ == '__main__':
	main()
