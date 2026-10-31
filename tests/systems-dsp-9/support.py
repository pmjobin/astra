# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Ordinary qualification subprocesses with complete command and file receipts."""
from pathlib import Path
import hashlib
import json
import os
import shutil
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]


def identity(path):
	path = Path(path).resolve()
	data = path.read_bytes()
	return dict(path=str(path), bytes=len(data), sha256=hashlib.sha256(data).hexdigest())


class Evidence:
	def __init__(self, compiler, output, name):
		self.compiler = Path(compiler).resolve()
		self.output = Path(output).resolve()
		assert not self.output.is_relative_to(ROOT)
		self.output.mkdir(parents=True, exist_ok=True)
		self.path = self.output / (name + '.json')
		if self.path.exists():
			attempts = self.output/'attempts'
			attempts.mkdir(exist_ok=True)
			index = 1
			while (attempts/f'{name}-{index}.json').exists():
				index += 1
			shutil.copyfile(self.path, attempts/f'{name}-{index}.json')
		self.data = dict(name=name, compiler=identity(self.compiler), commands=[], files=[])
		self.save()

	def save(self):
		self.path.write_text(json.dumps(self.data, indent=2) + '\n')

	def run(self, command, *, expected=0, stdout=None, contains=None, timeout=180, env=None, cwd=None):
		command = [str(value) for value in command]
		start = time.monotonic()
		result = subprocess.run(command, cwd=cwd or ROOT, capture_output=True, text=True,
			timeout=timeout, env=dict(os.environ, CCACHE_DISABLE='1', PYTHONDONTWRITEBYTECODE='1', **(env or {})))
		row = dict(command=command, exit=result.returncode, expected_exit=expected,
			seconds=time.monotonic()-start, stdout=result.stdout, stderr=result.stderr,
			expected_stdout=stdout, required_text=contains)
		if cwd is not None:
			row['cwd'] = str(Path(cwd).resolve())
		self.data['commands'].append(row)
		self.save()
		assert result.returncode == expected, row
		if stdout is not None:
			assert result.stdout == stdout, row
		if contains is not None:
			assert contains in result.stdout + result.stderr, row
		return result

	def files(self, *paths):
		current = {row['path']: row for row in self.data['files']}
		for path in paths:
			row = identity(path)
			current[row['path']] = row
		self.data['files'] = [current[path] for path in sorted(current)]
		self.save()

	def complete(self):
		assert identity(self.compiler) == self.data['compiler'], 'compiler changed during qualification'
		self.data['status'] = 'PASS'
		self.save()
		print(f"PASS: {self.data['name']}: {len(self.data['commands'])} commands")
