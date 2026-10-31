# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Preserved out-of-source attempts for ordinary qualification recipes.

The selector records a path only. It never asserts that a test passed.
"""
from pathlib import Path
import json
import os
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SELECTOR = '.astra-current-output.json'


def fresh_output(requested):
	base = Path(requested).resolve()
	assert not base.is_relative_to(ROOT), 'qualification output must stay outside source'
	base.mkdir(parents=True, exist_ok=True)
	container = Path(tempfile.mkdtemp(prefix='attempt-', dir=base))
	output = container / 'output'
	selection = {'format': 'astra-qualification-output/1', 'output': str(output.relative_to(base))}
	data = json.dumps(selection, indent='\t') + '\n'
	(container / 'selection.json').write_text(data)
	with tempfile.NamedTemporaryFile(mode='w', dir=base, prefix='.selection-', delete=False) as stream:
		stream.write(data)
		temporary = Path(stream.name)
	os.replace(temporary, base / SELECTOR)
	# Existing recipes create this new leaf themselves, including their usual
	# exclusive mkdir checks. Every previous file and attempt remains untouched.
	return output


def current_output(requested):
	base = Path(requested).resolve()
	selector = base / SELECTOR
	if not selector.exists():
		return base
	assert selector.is_file() and not selector.is_symlink()
	selection = json.loads(selector.read_text())
	assert selection['format'] == 'astra-qualification-output/1'
	relative = Path(selection['output'])
	assert not relative.is_absolute() and '..' not in relative.parts
	output = base / relative
	assert output.resolve().is_relative_to(base) and output.is_dir() and not output.is_symlink()
	return output
