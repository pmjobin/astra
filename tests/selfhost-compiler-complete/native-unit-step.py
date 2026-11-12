#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Stage exact native dependencies and invoke the unchanged original compiler."""
from pathlib import Path
import json
import os
import re
import shutil
import subprocess
import sys

from run import C0_SHA256, WORK, sha


def main():
	request = json.loads(sys.argv[1])
	compiler = Path(request['compiler'])
	assert sha(compiler) == C0_SHA256
	work = Path(request['work'])
	assert work.resolve().is_relative_to((WORK/'build').resolve()) and work.is_dir()
	for name, source in request['dependencies'].items():
		assert re.fullmatch(r'[A-Za-z0-9_-]+\.(asti|o)', name), name
		target = work/name
		assert not target.exists(), target
		shutil.copyfile(source, target)
		assert sha(target) == sha(source)
		target.chmod(0o444)
	args = [str(compiler), '-'+request['mode']]
	if request.get('namespace'):
		args += ['-c', '--module', request['namespace'], '--emit-interface', str(work/(request['id']+'.asti'))]
		for name in request['exports']:
			args += ['--native-export', name]
	for name in request['imports']:
		args += ['--import-module', str(work/(name+'.asti'))]
	args += request['sources']
	for name in request.get('link_objects', []):
		args += ['--link-object', name]
	args += ['-o', str(work/(request['id']+('.o' if request.get('namespace') else '.elf')))]
	code = subprocess.call(args, cwd=work, env=dict(os.environ, CCACHE_DISABLE='1'))
	assert sha(compiler) == C0_SHA256
	raise SystemExit(code)


if __name__ == '__main__':
	main()
