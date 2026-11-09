#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Build the current complete observer in milestone26-owned output leaves."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import sys

from run import BASE, ROOT, WORK, git, sha, write


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--mode', choices=('O0', 'O2'), required=True)
	p.add_argument('--version', required=True)
	p.add_argument('--build', type=Path, required=True)
	p.add_argument('--runtime', type=Path, required=True)
	a = p.parse_args()
	assert a.version.isalnum()
	for path, parent in ((a.build, WORK/'build'), (a.runtime, WORK/'runtime')):
		assert path.is_absolute() and path.resolve().is_relative_to(parent.resolve())
		assert all(not entry.is_symlink() for entry in (path, *path.parents))
		path.mkdir(parents=True, exist_ok=True)
	intake = WORK/'runtime/native-current/pm-next-intake.json'
	record = json.loads(intake.read_text())
	assert record['milestone_id'] == 'ASTRA-SELFHOST-COMPILER-COMPLETE-26' and record['base_commit'] == BASE
	assert not record['published']
	assert git('merge-base', '--is-ancestor', BASE, 'HEAD') == b''
	context = dict(purpose='Milestone26 current compiler build; no historical qualification is rerun or promoted', submission_sha256=record['submission_sha256'], base_commit=BASE, wrapper_sha256=sha(Path(__file__)), inherited_recipe_sha256=sha(ROOT/'tests/selfhost-effects/r5-resume.py'))
	initial = a.runtime/'initial.json'
	if initial.exists():
		assert json.loads(initial.read_text()) == context
	else:
		write(initial, context)
		# Reuse the authored full build graph, with every mutation redirected to
		# this task. The historical input seed remains read-only in the capsule.
	sys.path.insert(0, str(ROOT/'tests/selfhost-effects'))
	path = ROOT/'tests/selfhost-effects/r5-resume.py'
	spec = importlib.util.spec_from_file_location('compiler26_full_build_route', path)
	module = importlib.util.module_from_spec(spec)
	spec.loader.exec_module(module)
	module.RUNTIME = a.runtime.resolve()
	module.BUILD = a.build.resolve()
	module.PRIOR = WORK/'runtime/effects25-r5'
	os.environ['PM_CODEX_BUILD_DIR'] = str(a.build.parent)
	os.environ['PM_CODEX_RUNTIME_DIR'] = str(a.runtime.parent)
	sys.argv = [str(Path(__file__)), 'recover-full-build', '--mode', a.mode, '--version', a.version]
	module.main()


if __name__ == '__main__':
	main()
