# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Extend the existing receipts with environment and source conservation."""
from pathlib import Path
import importlib.util

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT/'tests/systems-dsp-9/support.py'
spec = importlib.util.spec_from_file_location('numerical_parent_evidence', BASE)
parent = importlib.util.module_from_spec(spec)
spec.loader.exec_module(parent)


class Evidence(parent.Evidence):
	def __init__(self, *args):
		super().__init__(*args)
		self.frozen = {}
		self.inputs(BASE, Path(__file__))

	def inputs(self, *paths):
		for path in paths:
			path = Path(path).resolve()
			self.frozen[str(path)] = parent.identity(path)
		self.files(*paths)

	def run(self, command, **kwargs):
		before = len(self.data['commands'])
		try:
			return super().run(command, **kwargs)
		finally:
			if len(self.data['commands']) > before:
				self.data['commands'][-1]['environment_overrides'] = kwargs.get('env', {})
				self.save()

	def complete(self):
		for path, identity in self.frozen.items():
			assert parent.identity(path) == identity, 'source changed during qualification: '+path
		self.data['frozen_inputs'] = self.frozen
		super().complete()
