# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Run unchanged predecessor oracles with genuine public O2 compilation."""
from pathlib import Path
import importlib.util
import json
import subprocess
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
compiler, emitter, output = map(lambda p: Path(p).resolve(), sys.argv[1:])
output.mkdir(parents=True, exist_ok=True)
original_run = subprocess.run
commands = []


def public_run(argv, *args, **kwargs):
	argv = list(map(str, argv))
	if argv[0] == str(compiler) and not any(x.startswith('--dump-') or x in ['--check', '--parse'] for x in argv[1:]):
		argv.insert(1, '-O2')
		commands.append(argv)
		(output / 'public-O2-commands.json').write_text(json.dumps(commands, indent=2) + '\n')
	return original_run(argv, *args, **kwargs)


spec = importlib.util.spec_from_file_location('previous_corpus', ROOT / 'tests/application-runtime-1/execute.py')
previous = importlib.util.module_from_spec(spec)
spec.loader.exec_module(previous)
subprocess.run = public_run
previous.main(compiler, emitter, output)
assert len(commands) >= 8
