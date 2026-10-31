# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Bind current regression inputs independently of optional historical receipts."""
from pathlib import Path
import hashlib
import json
import re
import shutil
import subprocess


def sha(path):
	with Path(path).open('rb') as source:
		return hashlib.file_digest(source, 'sha256').hexdigest()


def dependencies(binary):
	result = subprocess.run(['ldd', str(binary)], capture_output=True, text=True)
	return {Path(name).resolve() for name in re.findall(r'/[^\s()]+', result.stdout) if Path(name).is_file()}


class InputGuard:
	def __init__(self, root, compiler, freeze_path, profile, extra_inputs=()):
		assert profile in ('frozen', 'regression'), 'invalid qualification profile'
		self.root = Path(root).resolve()
		self.compiler = Path(compiler).resolve(strict=True)
		self.profile = profile
		self.freeze_path = Path(freeze_path) if freeze_path is not None else None
		self.freeze = None
		paths = {self.compiler, Path(__file__).resolve(), *dependencies(self.compiler)}
		if profile == 'frozen':
			assert self.freeze_path is not None and self.freeze_path.is_file(), 'historical evidence unavailable; select current regression explicitly'
			self.freeze = json.loads(self.freeze_path.read_text())
			inventory = self.freeze.get('source_files', self.freeze.get('source_inventory'))
			assert inventory, 'historical source inventory missing'
			paths.update(self.root / name for name in inventory)
			paths.update(Path(name) for name in self.freeze.get('host_dependencies', {}))
			paths.add(self.freeze_path)
		else:
			names = subprocess.check_output(['git', 'ls-files', '-z', '--cached', '--others', '--exclude-standard', '--', 'bootstrap', 'compiler', 'lib', 'meson.build', 'meson.options'], cwd=self.root).split(b'\0')
			paths.update(self.root / name.decode() for name in names if name)
		self.tools = {}
		for tool in ('gcc', 'cc', 'clang', 'opt', 'llc', 'llvm-config', 'ar', 'ld', 'nm',
			'valgrind', 'strace', 'pkg-config', 'g-ir-scanner', 'g-ir-compiler', 'python3'):
			command = shutil.which(tool)
			if command:
				path = Path(command).resolve()
				self.tools[tool] = path
				paths.add(path)
				paths.update(dependencies(path))
		paths.update(Path(path).resolve(strict=True) for path in extra_inputs)
		self.inputs = {str(path): sha(path) for path in sorted(paths)}
		self.check()

	def check(self):
		assert all(shutil.which(tool) and Path(shutil.which(tool)).resolve() == path
			for tool, path in self.tools.items()), 'qualification tool resolution changed during replay'
		assert all(Path(path).is_file() and sha(path) == digest for path, digest in self.inputs.items()), 'qualification input changed during replay'
		if self.freeze is not None:
			inventory = self.freeze.get('source_files', self.freeze.get('source_inventory'))
			for name, expected in inventory.items():
				assert sha(self.root / name) == expected['sha256'], 'historical frozen source changed: ' + name
			compilers = [self.freeze[key]['sha256'] for key in ('compiler', 'primary_compiler', 'strict_compiler') if key in self.freeze]
			assert compilers and sha(self.compiler) in compilers, 'historical frozen compiler changed'
			for name, expected in self.freeze.get('host_dependencies', {}).items():
				assert sha(name) == expected['sha256'], 'historical frozen dependency changed: ' + name

	def bind(self, evidence):
		original_run = evidence.run
		def checked_run(*args, **kwargs):
			self.check()
			return original_run(*args, **kwargs)
		evidence.run = checked_run

	def record(self):
		return {'profile': self.profile, 'regression_only': self.profile == 'regression',
			'original_freeze': self.freeze.get('freeze') if self.freeze is not None else None,
			'freeze_sha256': sha(self.freeze_path) if self.freeze is not None else None,
			'compiler_sha256': sha(self.compiler), 'current_inputs': self.inputs,
			'scope': 'Current regression; no historical challenge credit' if self.profile == 'regression' else 'Historical freeze identities enforced'}
