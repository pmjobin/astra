# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independent reference for the file indexer's external document/index format."""
from pathlib import Path
from dataclasses import dataclass
import argparse
import bisect
import hashlib
import json
import os
import re
import sys


IDENTIFIER = re.compile(rb'[A-Za-z_][A-Za-z_0-9]*')


class RejectedDocument(ValueError):
	pass


@dataclass(frozen=True)
class Word:
	text: str
	count: int
	first_byte: int
	first_line: int
	first_column: int


@dataclass(frozen=True)
class Document:
	byte_count: int
	scalar_count: int
	line_count: int
	word_count: int
	words: tuple[Word, ...]


def analyze(data: bytes) -> Document:
	try:
		text = data.decode('utf-8', errors='strict')
	except UnicodeDecodeError as error:
		raise RejectedDocument('invalid-utf8') from error
	if b'\0' in data:
		raise RejectedDocument('embedded-nul')

	newlines = [offset for offset, byte in enumerate(data) if byte == 10]
	counts = {}
	first = {}
	for match in IDENTIFIER.finditer(data):
		word = match.group()
		counts[word] = counts.get(word, 0) + 1
		if word not in first:
			offset = match.start()
			line = bisect.bisect_left(newlines, offset)
			start = 0 if line == 0 else newlines[line - 1] + 1
			column = len(data[start:offset].decode('utf-8')) + 1
			first[word] = (offset, line + 1, column)
	words = tuple(Word(word.decode('ascii'), counts[word], *first[word])
		for word in sorted(counts))
	return Document(len(data), len(text), len(newlines) + int(bool(data) and data[-1] != 10),
		sum(counts.values()), words)


def escaped_path(path: str) -> str:
	return ''.join(chr(byte) if 33 <= byte <= 126 and byte != 37 else f'%{byte:02X}'
		for byte in os.fsencode(path))


def render(paths: list[str]) -> bytes:
	lines = ['astra-index\t1']
	successes = errors = total_bytes = total_words = 0
	for path in paths:
		label = escaped_path(path)
		try:
			try:
				data = Path(path).read_bytes()
			except OSError as error:
				raise RejectedDocument('read') from error
			result = analyze(data)
		except RejectedDocument as error:
			lines.append(f'error\t{label}\t{error}')
			errors += 1
			continue
		lines.append(f'file\t{label}\t{result.byte_count}\t{result.scalar_count}'
			f'\t{result.line_count}\t{result.word_count}\t{len(result.words)}')
		for word in result.words:
			lines.append(f'word\t{label}\t{word.text}\t{word.count}\t{word.first_byte}'
				f'\t{word.first_line}\t{word.first_column}')
		successes += 1
		total_bytes += result.byte_count
		total_words += result.word_count
	lines.append(f'summary\t{successes}\t{errors}\t{total_bytes}\t{total_words}')
	return ('\n'.join(lines) + '\n').encode('ascii')


def self_check():
	result = analyze('int alpha=alpha;\r\nλ beta alpha'.encode())
	assert result == Document(31, 30, 2, 5, (
		Word('alpha', 3, 4, 1, 5), Word('beta', 1, 21, 2, 3), Word('int', 1, 0, 1, 1)))
	assert analyze(b'') == Document(0, 0, 0, 0, ())
	assert analyze(b'\r\n\n').line_count == 2
	for data, code in [(b'\xc0\xaf', 'invalid-utf8'), (b'\xed\xa0\x80', 'invalid-utf8'),
		(b'\xf0\x9f\x92', 'invalid-utf8'), (b'before\0after', 'embedded-nul')]:
		try:
			analyze(data)
		except RejectedDocument as error:
			assert str(error) == code
		else:
			raise AssertionError(code)
	assert escaped_path('a b%\tλ') == 'a%20b%25%09%CE%BB'


def main():
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument('paths', nargs='*')
	parser.add_argument('--output', type=Path)
	parser.add_argument('--self-check', action='store_true')
	args = parser.parse_args()
	if args.self_check:
		self_check()
	if args.paths or not args.self_check:
		output = render(args.paths)
		if args.output:
			args.output.write_bytes(output)
			print(json.dumps(dict(path=str(args.output), bytes=len(output),
				sha256=hashlib.sha256(output).hexdigest())))
		else:
			sys.stdout.buffer.write(output)


if __name__ == '__main__':
	main()
