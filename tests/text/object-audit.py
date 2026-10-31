# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Qualified object bytes and text-free baseline identity; internal test seams only."""
from pathlib import Path
import json
import re
import sys

sys.dont_write_bytecode = True
from qualify import run, sha, object_file


def main():
	build = Path(sys.argv[1]).resolve(); baseline = Path(sys.argv[2]).resolve(); out = Path(sys.argv[3]).resolve(); out.mkdir(parents=True, exist_ok=True)
	qualified = build / 'text-1/qualification'; records = {}
	for mode in ['O0', 'O2', 'fma']:
		obj = qualified / ('pure-' + mode + '.o'); dest = out / ('pure-' + mode + '.rodata')
		# An explicit output prevents GNU objcopy from rewriting the input object.
		run(['objcopy', '--dump-section', '.rodata=' + str(dest), obj, out / ('pure-' + mode + '.inspection.o')]); assert dest.read_bytes() == b'a\0b\xc3\xa9'
		ir = (qualified / ('pure-' + mode + '.ll')).read_text()
		assert 'store ' not in ir and 'global_ctors' not in ir and 'global_dtors' not in ir
		assert run(['nm', '-u', obj]) == '' and len(re.findall('define internal .*@astra.text.equal', ir)) == 1
		assert not any(x in run(['nm', '-g', obj]) for x in ['APP_NAME', 'astra.text.'])
		sections = run(['readelf', '-SW', obj]); readonly = next(line for line in sections.splitlines() if ' .rodata ' in line)
		assert ' W' not in readonly
		records['pure-' + mode] = dict(object_bytes=obj.stat().st_size, sections=sections, symbols=run(['nm', '-a', obj]), literal_hex=dest.read_bytes().hex(), helper_count=1)
	source = out / 'text-free.astra'; source.write_text('int input(int x){return x+1;}')
	ir = [run([c / 'astrac', '--dump-llvm', source]) for c in [baseline, build]]
	assert ir[0] == ir[1] and 'astra.text' not in ir[1]
	for mode in ['O0', 'O2', 'fma']:
		objects = [object_file(text, out / ('text-free-' + str(i) + '-' + mode), mode) for i, text in enumerate(ir)]
		assert objects[0].read_bytes() == objects[1].read_bytes() and run(['nm', '-u', objects[1]]) == ''
		records['text-free-' + mode] = dict(sha256=sha(objects[1].read_bytes()), object_bytes=objects[1].stat().st_size, symbols=run(['nm', '-a', objects[1]]))
	(out / 'object-audit.json').write_text(json.dumps(records, indent='\t') + '\n')
	print('readonly exact bytes, one helper, no imports/ctors/stores, text-free baseline objects PASS')


if __name__ == '__main__':
	main()
