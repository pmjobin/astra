# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Current Sequence inputs, independent of unavailable historical receipts."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/support'))
from input_guard import InputGuard


def sequence_guard(compiler, prefix, profile, extra_inputs=()):
	prefix = Path(prefix).resolve(strict=True)
	here = Path(__file__).resolve().parent
	app = ROOT / 'examples/runtime-composition-17'
	inputs = [*here.glob('sequence*'), *app.glob('sequence*'), app / 'build-sequence.py',
		ROOT / 'tests/systems-dsp-9/support.py', ROOT / 'tests/concurrency-runtime-13/sanitizers.py',
		prefix / 'lib/liburing.a', *[p for p in (prefix / 'include').rglob('*') if p.is_file()], *extra_inputs]
	return InputGuard(ROOT, compiler, ROOT / 'docs/runtime-composition-17-freeze-3.json', profile, inputs)
