# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""All source orders, relocated installation and exact family observations."""
from pathlib import Path
import sys
sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tests/support'))
from installed_client import main


SPEC = dict(example='generic-slices', libraries=['base/slices.astra', 'base/diagnostics.astra', 'hosted/text.astra'],
	expected=b'generic slices: 7; snapshots independent\n', expression='fixed[0]', view=True)


if __name__ == '__main__':
	main(SPEC)
