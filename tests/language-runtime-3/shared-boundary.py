# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Unique Class owners cannot be copied or retained as persistent unowned fields."""
from pathlib import Path
import json
import subprocess
import sys


def main(compiler, output):
	compiler, output = Path(compiler).resolve(), Path(output).resolve()
	assert not output.is_relative_to(Path(__file__).resolve().parents[2])
	output.mkdir(parents=True, exist_ok=True)
	payload = 'class Payload{int value;init(int value){this.value=value;}}'
	cases = {
		'copy-unique': (payload+'int main(){var first=new Payload(7);var second=first;return second.value;}', 'persistent alias'),
		'retain-borrow': (payload+'class Strong{Payload value;init(Payload value){this.value=value;}}', 'object-reference fields are unsupported'),
	}
	rows = []
	for name, (source, message) in cases.items():
		path = output/(name+'.astra'); path.write_text(source+'\n')
		command = [str(compiler), '--check', str(path)]
		p = subprocess.run(command, capture_output=True, text=True, timeout=30)
		rows.append(dict(command=command, exit=p.returncode, stdout=p.stdout, stderr=p.stderr))
		assert p.returncode == 1 and message in p.stderr, rows[-1]
	(output/'shared-boundary.json').write_text(json.dumps(dict(status='PASS',
		claim='These refusals preserve unique ownership; they do not implement shared/weak lifetimes.', checks=rows), indent=2)+'\n')
	print('2 unique-ownership boundary probes refused; Shared/Weak use separate authorities')


if __name__ == '__main__':
	main(*sys.argv[1:])
