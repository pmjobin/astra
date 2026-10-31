# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independent native processes retain policy identity and strict callees."""
from pathlib import Path
import re
import sys

import evidence as support
ROOT = support.ROOT


def main(compiler, output):
	e = support.Evidence(compiler, output, 'unit-policies')
	e.inputs(Path(__file__))
	identities = []
	for level in (0, 1, 2):
		folder = e.output/f'O{level}'
		folder.mkdir(exist_ok=True)
		producer, interface, obj = folder/'producer.astra', folder/'producer.asti', folder/'producer.o'
		producer.write_text('namespace Policy11;\n[FloatingPoint(contract="on")]\nf64 selected(f64 a,f64 b,f64 c){return a*b+c;}\nf64 strict(f64 a,f64 b,f64 c){return a*b+c;}\n')
		e.run([e.compiler, f'-O{level}', '-c', '--module', 'Policy11', '--emit-interface', interface,
			'--native-export', 'Policy11.selected', '--native-export', 'Policy11.strict', producer, '-o', obj])
		text = interface.read_text()
		assert 'floating-policy=32;' in text
		identities.append(re.search(r'^identity=(.+)$', text, re.M).group(1))
		e.files(interface, obj)
		producer.rename(folder/'producer.preserved-input')
		e.files(folder/'producer.preserved-input')
		consumer = folder/'consumer.astra'
		consumer.write_text('using Policy11;\nint main(){f64 a=selected(1.25,2.0,0.5);f64 b=strict(1.25,2.0,0.5);if(a!=3.0||b!=3.0){return 1;}return 0;}\n')
		exe = folder/'consumer'
		e.run([e.compiler, f'-O{2-level}', '--import-module', interface, consumer, '-o', exe])
		e.run([exe])
		e.run(['valgrind', '--quiet', '--error-exitcode=91', '--leak-check=full', exe])
		e.files(consumer, exe)
	assert len(set(identities)) == 1
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
