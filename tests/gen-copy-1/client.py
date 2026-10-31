# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""All source orders, relocated installation and exact family observations."""
from pathlib import Path
import sys
sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tests/support'))
from installed_client import main


SPEC = dict(example='generic-copyable-values', libraries=['base/diagnostics.astra', 'hosted/text.astra'],
	expected=b'generic records: 7; snapshots independent\n', expression='identity(records[0])', view=False)


if __name__ == '__main__':
	main(SPEC)
