# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Executed no-OS lexical and region-owned Astra lifecycles."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence
from guest import image, boot


def main(compiler, output):
	e = Evidence(compiler, output, 'guest-policies')
	runtime = ROOT / 'lib/runtime/runtime/allocation-12.c'
	common = e.output / 'allocation.o'
	e.run(['clang', '--target=x86_64-none-elf', '-O2', '-mno-red-zone',
		'-ffreestanding', '-fno-builtin', '-fno-stack-protector', '-std=c11',
		'-Wall', '-Wextra', '-Werror', '-pedantic', '-c', runtime, '-o', common])
	e.run(['nm', '-u', common], stdout='')
	devices = ROOT / 'lib/astra/platform/pc-devices.astra'
	apps = ROOT / 'examples/freestanding-allocation-12'
	for level in (0, 1, 2):
		boot(e, image(e, apps / 'a98-static-cleanup.astra', f'a98-O{level}', level,
			extra_sources=[devices]), 'ABba:42\n')
		boot(e, image(e, apps / 'a101-region-guest.astra', f'a101-O{level}', level,
			extra_sources=[devices], link_objects=[common]), 'ABba' * 16 + ':288\n')
	boot(e, image(e, apps / 'a98-static-cleanup.astra', 'a98-no-data', 2,
		defines=['-DASTRA_TEST_SKIP_DATA_INIT'], extra_sources=[devices]), '!')
	oracle_source = ROOT / 'tests/freestanding-allocation-12/stream-oracle.c'
	oracle = e.output / 'stream-oracle'
	e.run(['clang', '-O2', '-ffp-contract=off', '-fno-fast-math', '-std=c11',
		'-Wall', '-Wextra', '-Werror', '-pedantic', oracle_source, '-o', oracle])
	expected = e.run([oracle]).stdout
	# Independent exact-rational recurrence, bounded to 32 steps before reset.
	from fractions import Fraction
	checksums = []
	for block in range(4):
		previous = total = Fraction(0)
		for i in range(32):
			previous = previous / 2 + Fraction((block * 32 + i) % 9 + 1, 64)
			total += previous
		checksums.append(int(total * 1024))
	assert expected == 'S:' + ''.join(f'{n:06d},' for n in checksums) + 'D\n'
	for level in (0, 1, 2):
		boot(e, image(e, apps / 'a108-static-stream.astra', f'a108-O{level}', level,
			extra_sources=[devices], link_objects=[common]), expected)
		boot(e, image(e, ROOT / 'tests/freestanding-allocation-12/policy-kinds-guest.astra',
			f'policy-kinds-O{level}', level, extra_sources=[devices], link_objects=[common]),
			'12a13a3a2P4P5b5Rb4ROK\n')
	mutant = e.output / 'a108-bounds.astra'
	mutant.write_text((apps / 'a108-static-stream.astra').read_text().replace('i < len(samples)', 'i <= len(samples)', 1))
	boot(e, image(e, mutant, 'a108-bounds', 2, extra_sources=[devices],
		link_objects=[common]), 'S:PANIC:06\n', exit=253)
	kinds = (ROOT / 'tests/freestanding-allocation-12/policy-kinds-guest.astra').read_text()
	fatal = e.output / 'policy-kinds-fatal.astra'
	fatal.write_text(kinds.replace('var exhausted = try_new PoolValue(9)', 'var exhausted = new PoolValue(9)'))
	boot(e, image(e, fatal, 'policy-kinds-fatal', 2, extra_sources=[devices],
		link_objects=[common]), '12PANIC:06\n', exit=253)
	misaligned = e.output / 'policy-kinds-misaligned.astra'
	misaligned.write_text(kinds.replace('return next;', 'return next + 1;'))
	boot(e, image(e, misaligned, 'policy-kinds-misaligned', 2, extra_sources=[devices],
		link_objects=[common]), '12a13a3a2PPP?')
	e.files(oracle_source, oracle)
	e.files(runtime, runtime.with_suffix('.h'), common, devices)
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
