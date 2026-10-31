# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Calibrate the existing lifetime observer using safe static-resource probes.

These are C observer protocol controls, not generated-Astra execution evidence.
No corrupted IR or native object is emitted or executed. Resources are entries
in the observer's static table, so the duplicate probe cannot access freed heap.
"""
from pathlib import Path
import argparse
import hashlib
import json
import resource
import signal
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def main():
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument('build_output', type=Path)
	parser.add_argument('runtime_output', type=Path)
	args = parser.parse_args()
	build, output = args.build_output.resolve(), args.runtime_output.resolve()
	assert not build.is_relative_to(ROOT) and not output.is_relative_to(ROOT)
	build.mkdir(parents=True, exist_ok=True)
	output.mkdir(parents=True, exist_ok=True)
	folder = Path(tempfile.mkdtemp(prefix='lifetime-sensors-', dir=build))
	out = Path(tempfile.mkdtemp(prefix='lifetime-sensors-', dir=output))
	observer = ROOT / 'tests/own-field/companion.c'
	source = folder / 'probe.c'
	source.write_text('''/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <stdint.h>
#include <string.h>
extern void *of_make(int32_t);
extern void of_release(void *);
extern void of_release_other(void *);
extern int32_t of_live(void);
int main(int argc, char **argv) {
	if (argc != 2) { return 2; }
	void *value = of_make(211);
	if (!strcmp(argv[1], "missing")) { return of_live() == 1 ? 31 : 32; }
	if (!strcmp(argv[1], "wrong-domain")) { of_release_other(value); return 33; }
	of_release(value);
	if (!strcmp(argv[1], "duplicate")) { of_release(value); return 34; }
	return of_live();
}
''')
	binary = folder / 'probe'
	command = ['cc', '-std=c11', '-O2', '-UNDEBUG', '-Wall', '-Wextra', '-Werror', str(observer), str(source), '-o', str(binary)]
	compiled = subprocess.run(command, capture_output=True)
	assert compiled.returncode == 0 and not compiled.stdout and not compiled.stderr
	receipt = dict(format='astra-m15-lifetime-observer-sensors/1',
		sources={str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in [observer, source, Path(__file__)]},
		compile_command=command, binary_sha256=hashlib.sha256(binary.read_bytes()).hexdigest(), checks=[],
		scope='Existing C lifetime monitor controls only; separate emitted-Astra Valgrind and ASan receipts provide language memory evidence.')

	def no_core():
		resource.setrlimit(resource.RLIMIT_CORE, (0, 0))

	for mode, expected, trace in [('normal', 0, b'+211\n-211\n'), ('missing', 31, b'+211\n'),
		('duplicate', -signal.SIGABRT, b'+211\n-211\n'), ('wrong-domain', -signal.SIGABRT, b'+211\n')]:
		result = subprocess.run([binary, mode], cwd=folder, capture_output=True, timeout=10, preexec_fn=no_core)
		passed = result.returncode == expected and result.stdout == trace
		if expected == -signal.SIGABRT:
			passed &= b'resource && resource->alive && resource->domain == domain' in result.stderr
		else:
			passed &= not result.stderr
		receipt['checks'].append(dict(mode=mode, exit=result.returncode, expected_exit=expected,
			stdout=result.stdout.decode(), stderr=result.stderr.decode(), passed=bool(passed)))
		assert passed, receipt['checks'][-1]
	receipt['all_passed'] = True
	(out / 'checks.json').write_text(json.dumps(receipt, indent='\t') + '\n')
	print(out / 'checks.json')


if __name__ == '__main__':
	main()
