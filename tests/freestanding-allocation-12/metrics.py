# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Measured ELF/ROM/RAM/stack inventory and bounded host instruction costs."""
from pathlib import Path
import re
import struct
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence, identity


def elf_sections(path):
	data = path.read_bytes()
	assert data[:6] == b'\x7fELF\x02\x01', 'requires little-endian ELF64'
	header = struct.unpack_from('<16sHHIQQQIHHHHHH', data)
	assert header[2] == 62 and header[11] == 64
	position, count, strings_index = header[6], header[12], header[13]
	sections = [struct.unpack_from('<IIQQQQIIQQ', data, position + i * 64) for i in range(count)]
	strings = sections[strings_index]
	names = data[strings[4]:strings[4] + strings[5]]
	result = []
	for row in sections:
		name = names[row[0]:].split(b'\0', 1)[0].decode()
		result.append(dict(name=name, type=row[1], flags=row[2], address=row[3],
			bytes=row[5], alignment=row[8]))
	return result


def main(build, output):
	build = Path(build).resolve()
	e = Evidence(build / 'astrac', output, 'allocation-costs')
	root = build / 'tests/freestanding-allocation-12'
	e.data['guest'] = []
	for folder, stem in [('guest', 'a97'), ('policies', 'a98'),
		('devices', 'a99-device-order'), ('devices', 'a100-trap-return'),
		('policies', 'a101'), ('policies', 'a108'), ('policies', 'policy-kinds')]:
		for level in (0, 1, 2):
			elf = root / folder / f'{stem}-O{level}.elf'
			binary = elf.with_suffix('.bin')
			sections = elf_sections(elf)
			allocated = [s for s in sections if s['flags'] & 2]
			writable = [s for s in allocated if s['flags'] & 1]
			text = sum(s['bytes'] for s in allocated if s['flags'] & 4)
			symbols = e.run(['nm', '-n', elf]).stdout
			named = {}
			for line in symbols.splitlines():
				parts = line.split()
				if len(parts) == 3:
					named[parts[2]] = int(parts[0], 16)
			assert named['boot_stack_top'] - named['boot_stack'] == 65536
			e.run(['nm', '-u', elf], stdout='')
			e.data['guest'].append(dict(app=stem, level=level, elf=identity(elf),
				rom_binary=identity(binary), executable_bytes=text,
				allocated_section_bytes=sum(s['bytes'] for s in allocated),
				writable_bytes=sum(s['bytes'] for s in writable),
				bss_bytes=sum(s['bytes'] for s in allocated if s['type'] == 8),
				stack_reserved_bytes=65536, stack_guard_address=named['stack_guard'],
				sections=allocated))
			e.files(elf, binary, Path(str(elf) + '.map'))
	owners = root / 'owners'
	e.data['host'] = []
	for app in ('a101', 'a102', 'a103', 'a104', 'a105', 'a106'):
		product = owners / f'{app}-O2'
		libraries = e.run(['ldd', product]).stdout
		assert not re.search(r'lib(glib|gobject|stdc\+\+|gcc_s|pthread|unwind)', libraries)
		e.data['host'].append(dict(app=app, product=identity(product),
			sections=elf_sections(product), dynamic_dependencies=libraries))
		e.files(product)
	e.data['instructions'] = []
	trace = '11,22,33,' + ''.join(f'{100+i},{200+i},{-200-i},{-100-i},' for i in range(12)) + '-11,-33,-22,44,-44,\n'
	for level in (0, 1, 2):
		product = owners / f'a101-O{level}'
		counter = e.output / f'a101-O{level}.callgrind'
		e.run(['valgrind', '--tool=callgrind', '--callgrind-out-file=' + str(counter),
			product], expected=42, stdout=trace)
		match = re.search(r'^summary: (\d+)$', counter.read_text(), re.M)
		assert match
		e.data['instructions'].append(dict(app='a101', level=level,
			product=identity(product), instructions=int(match[1]), counter=identity(counter)))
		e.files(product, counter)
	e.data['scope'] = 'Guest bytes are exact linked section/flat-image sizes. Stack is a 64 KiB reservation with the executed startup guard, not a measured peak stack-pointer bound. Callgrind counts the complete hosted process, including C observers, I/O and system startup, at fixed C -O2 and each public Astra optimization level. These are costs, not a claimed policy speedup or guest cycle measurement.'
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
