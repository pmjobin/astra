# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""All source orders, relocated installation and exact family observations."""
from pathlib import Path
import sys
sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tests/support'))
from installed_client import main


def library_control(runner, compiler, installed, library, out):
	pure=installed/'pure.astra';pure.write_text('struct K{int x;f64 y;}owned T[] relay<T>(owned T[] a){return move a;}int main(){K k={x=17,y=2.0d};var a=filled_array(3,k);var b=clone_array(a);a[0].x=31;release a;var c=relay(move b);if(c[0].x!=17){return 1;}c=clone_array(c);return 0;}\n')
	runner.checked([compiler,pure.name,library/'base/buffers.astra',library/'base/slices.astra','-o','pure'],installed)
	assert runner.checked([installed/'pure'],installed)==b''
	missing=runner.run([compiler,pure.name,library/'base/buffers.astra','--dump-semantics'],installed,capture_output=True)
	(out/'missing-slices.stdout').write_bytes(missing.stdout);(out/'missing-slices.stderr').write_bytes(missing.stderr)
	assert missing.returncode==1 and b"unknown function 'fill'" in missing.stderr,missing
	return dict(pure=str(installed/'pure'))


SPEC = dict(example='generic-owned-arrays', libraries=['base/buffers.astra', 'base/slices.astra', 'base/diagnostics.astra', 'hosted/text.astra'],
	expected=b'generic arrays: 7; owners and snapshots independent\n', expression='fixed[0]', view=True, extra=library_control)


if __name__ == '__main__':
	main(SPEC)
