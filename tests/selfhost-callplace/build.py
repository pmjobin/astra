#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Use the qualified LLVM recipe with a separate CALLPLACE mutation consumer."""
import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('llvm_build', ROOT/'tests/selfhost-llvm/build.py')
base = importlib.util.module_from_spec(spec); spec.loader.exec_module(base)
original = base.core.base.build


def build(*args, **kwargs):
	kwargs['consumer'] = ROOT/'tests/selfhost-callplace/query.astra'
	kwargs['extra_sources'] = [*kwargs['extra_sources'], ROOT/'tests/selfhost-callplace/check.astra']
	kwargs['link_inputs'] = [*kwargs['link_inputs'], Path(__file__)]
	return original(*args, **kwargs)


if __name__ == '__main__':
	base.core.base.build = build
	base.main()
