# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Generate deterministic, task-owned inputs for the milestone 15 file indexer."""
from pathlib import Path
import argparse
import hashlib
import json
import tempfile


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_SEED = 151_064


def generate(output, seed):
	output = output.resolve()
	if output.is_relative_to(ROOT):
		raise ValueError('generated corpus must remain outside the source repository')
	output.mkdir(parents=True, exist_ok=True)
	# Never reuse a caller's files or rely on deleting a previous corpus.
	directory = Path(tempfile.mkdtemp(prefix='corpus-', dir=output))
	manifest = {
		'format': 'astra-m15-file-indexer-corpus/1',
		'seed': seed,
		'generator_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
		'inputs': [],
		'missing_input': 'missing-input.astra',
		'qualification': 'Input generation only; no compiler or application PASS.',
	}

	def write(name, data, family, utf8=True):
		path = directory / name
		with path.open('xb') as stream:
			stream.write(data)
		manifest['inputs'].append({
			'path': name, 'family': family,
			'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest(),
			'valid_utf8': utf8, 'contains_nul': b'\0' in data,
		})

	write('input-00.astra', b'', 'empty')
	write('input-01.astra', b'int alpha = 1;\r\nint beta = alpha + 2;\n',
		'ascii-and-line-endings')
	write('input-02.astra',
		'// caf\u00e9 cafe\u0301 \u0394 \u03bb \u4e2d\u6587 \U0001f642\nint unicode_sample = 42;\n'.encode(),
		'multibyte-and-combining')
	write('input-03.astra', b'int long_identifier_' + b'a' * 8193 + b' = 7;\n',
		'large-token')
	write('input-04.astra', b'int repeated = repeated + repeated;\n' * 257,
		'duplicate-identifiers')
	for index in range(5, 63):
		lines = []
		for row in range(1 + index % 19):
			digest = hashlib.sha256(f'{seed}:{index}:{row}'.encode('ascii')).digest()
			name = 'identifier_' + digest[:6].hex()
			other = 'shared_' + str(digest[6] % 17)
			lines.append(f'int {name} = {other} + {digest[7]};\n'.encode('ascii'))
		write(f'input-{index:02}.astra', b''.join(lines), 'seeded-identifiers')
		# The last code point crosses an ordinary read-buffer boundary in some
		# partitions. The consumer must retain UTF-8 decoder state between reads.
	block = ('int streaming_value = repeated + shared_0; // cafe\u0301 \U0001f642\n'
		.encode('utf-8'))
	streaming = block * ((3 * 1024 * 1024) // len(block) + 1)
	write('input-63.astra', streaming + b'int final_without_newline = 1;',
		'multimegabyte-streaming')
	write('overlong-utf8.astra', b'int before = 1;\n// \xc0\xaf\n',
		'invalid-overlong-utf8', utf8=False)
	write('surrogate-utf8.astra', b'// \xed\xa0\x80\n',
		'invalid-surrogate-utf8', utf8=False)
	write('truncated-utf8.astra', b'int before = 1;\n// \xf0\x9f\x92',
		'truncated-utf8', utf8=False)
	write('embedded-nul.astra', b'int before = 1;\0int after = 2;\n',
		'embedded-nul')
	write('truncated-source.astra', b'int before = 1;\nstring unfinished = "tail',
		'truncated-source-record')
	# This digest names the input bytes and requested cases independently of
	# their random task-owned staging directory.
	manifest['corpus_sha256'] = hashlib.sha256(json.dumps(
		manifest['inputs'], sort_keys=True, separators=(',', ':')).encode()).hexdigest()
	path = directory / 'manifest.json'
	path.write_text(json.dumps(manifest, indent='\t') + '\n')
	return path


def main():
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument('output', type=Path)
	parser.add_argument('--seed', type=int, default=DEFAULT_SEED)
	args = parser.parse_args()
	print(generate(args.output, args.seed))


if __name__ == '__main__':
	main()
