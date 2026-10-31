#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Stdio LSP using astrac's checked symbol identities and source formatter."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import queue
import re
import select
import signal
import shutil
import subprocess
import sys
import tempfile
import threading
import time
from urllib.parse import unquote, urlparse

MAX_BODY = 16 * 1024 * 1024
MAX_DOCUMENT = 2 * 1024 * 1024
MAX_QUEUED = 128
MAX_QUEUE_BYTES = 32 * 1024 * 1024
MAX_DOCUMENTS = 128
MAX_WORKSPACE = 32 * 1024 * 1024
PROGRESS_TIMEOUT = 30


def unique_object(pairs):
	result = {}
	for key, value in pairs:
		if key in result:
			raise ValueError('duplicate JSON key')
		result[key] = value
	return result


def decode_message(body):
	def invalid_constant(value):
		raise ValueError('invalid JSON constant')
	message = json.loads(body.decode('utf-8'), object_pairs_hook=unique_object,
		parse_constant=invalid_constant)
	# JSON escapes can encode unpaired surrogates even in a valid UTF-8 frame.
	pending = [message]
	while pending:
		value = pending.pop()
		if isinstance(value, str):
			value.encode('utf-8')
		elif isinstance(value, dict):
			pending.extend(value.keys())
			pending.extend(value.values())
		elif isinstance(value, list):
			pending.extend(value)
	return message


class FrameInput:
	# Raw descriptor reads let the daemon receiver stop with the process without
	# leaving Python's buffered stdin lock held during interpreter finalization.
	def __init__(self):
		self.pending = bytearray()
		self.deadline = None

	def begin_frame(self):
		self.deadline = time.monotonic() + PROGRESS_TIMEOUT if self.pending else None

	def receive(self, length):
		if os.name == 'posix':
			remaining = None if self.deadline is None else max(0, self.deadline - time.monotonic())
			if not select.select([0], [], [], remaining)[0]:
				raise ValueError('incomplete protocol frame exceeded progress deadline')
		data = os.read(0, length)
		self.deadline = time.monotonic() + PROGRESS_TIMEOUT
		return data

	def readline(self, limit):
		while b'\n' not in self.pending and len(self.pending) < limit:
			data = self.receive(8192)
			if not data:
				break
			self.pending.extend(data)
		index = self.pending.find(b'\n')
		end = min(index + 1 if index >= 0 else len(self.pending), limit)
		result = bytes(self.pending[:end])
		del self.pending[:end]
		return result

	def read(self, length):
		while len(self.pending) < length:
			data = self.receive(min(65536, length - len(self.pending)))
			if not data:
				break
			self.pending.extend(data)
		result = bytes(self.pending[:length])
		del self.pending[:length]
		return result


class RpcError(Exception):
	def __init__(self, code, message):
		self.code, self.message = code, message


def require(condition, message):
	if not condition:
		raise RpcError(-32602, message)


def local_path(uri):
	require(isinstance(uri, str), 'expected a file URI')
	parts = urlparse(uri)
	require(parts.scheme == 'file' and parts.netloc in ('', 'localhost') and not parts.query and not parts.fragment,
		'only local file URIs are supported')
	return Path(unquote(parts.path)).absolute()


def line_starts(text):
	return [0] + [m.end() for m in re.finditer(r'\r\n|\r|\n', text)]


def utf16_position(text, byte_offset):
	# The compiler's offsets are bytes, independent of editor character encoding.
	prefix = text.encode('utf-8')[:byte_offset].decode('utf-8')
	starts = line_starts(prefix)
	return {'line': len(starts) - 1, 'character': len(prefix[starts[-1]:].encode('utf-16-le')) // 2}


def byte_position(text, position):
	require(isinstance(position, dict), 'expected a position')
	line, character = position.get('line'), position.get('character')
	require(type(line) is int and type(character) is int and line >= 0 and character >= 0, 'invalid position')
	starts = line_starts(text)
	require(line < len(starts), 'line outside document')
	end = starts[line + 1] if line + 1 < len(starts) else len(text)
	content = text[starts[line]:end].rstrip('\r\n')
	units, characters = 0, 0
	for c in content:
		if units >= character:
			break
		units += 2 if ord(c) > 0xffff else 1
		characters += 1
	require(units == character, 'position outside line or inside a UTF-16 surrogate pair')
	return len(text[:starts[line] + characters].encode('utf-8'))


class Server:
	def __init__(self, compiler, scratch):
		self.compiler, self.scratch = compiler, scratch
		self.initialized = False
		self.shutdown = False
		self.root = None
		self.documents = {}
		self.document_bytes = 0
		self.texts = {}
		self.index = {'symbols': [], 'references': [], 'diagnostics': []}
		self.dirty = True
		self.cancelled = set()
		self.pending_requests = set()
		self.state_lock = threading.Lock()
		self.queued_bytes = 0
		self.inbox = queue.Queue(maxsize=MAX_QUEUED)
		self.input_done = threading.Event()
		self.stop_requested = threading.Event()
		self.input_failure = None

	def send(self, value):
		body = json.dumps(value, ensure_ascii=False, separators=(',', ':')).encode('utf-8')
		require(len(body) <= MAX_BODY, 'protocol response exceeds finite limit')
		frame = f'Content-Length: {len(body)}\r\n\r\n'.encode('ascii') + body
		if os.name != 'posix':
			sys.stdout.buffer.write(frame)
			sys.stdout.buffer.flush()
			return
		os.set_blocking(1, False)
		remaining = memoryview(frame)
		deadline = time.monotonic() + PROGRESS_TIMEOUT
		while remaining:
			if not select.select([], [1], [], max(0, deadline - time.monotonic()))[1]:
				raise OSError('protocol output exceeded progress deadline')
			try:
				written = os.write(1, remaining[:65536])
			except BlockingIOError:
				continue
			remaining = remaining[written:]
			deadline = time.monotonic() + PROGRESS_TIMEOUT

	def notify(self, method, params):
		self.send({'jsonrpc': '2.0', 'method': method, 'params': params})

	def log(self, message):
		self.notify('window/logMessage', {'type': 2, 'message': message})

	def reader(self):
		stream = FrameInput()
		try:
			while True:
				stream.begin_frame()
				headers = {}
				size = 0
				while True:
					line = stream.readline(8193)
					if not line:
						if size:
							raise ValueError('truncated protocol header')
						return
					size += len(line)
					if size > 8192 or not line.endswith(b'\r\n'):
						raise ValueError('invalid or oversized protocol header')
					if line == b'\r\n':
						break
					key, value = line.decode('ascii').rstrip('\r\n').split(':', 1)
					key = key.lower()
					if key in headers:
						raise ValueError('duplicate protocol header')
					headers[key] = value.strip()
				n = int(headers.get('content-length', '-1'))
				if not 0 <= n <= MAX_BODY:
					raise ValueError('invalid Content-Length')
				body = stream.read(n)
				if len(body) != n:
					raise ValueError('truncated protocol body')
				try:
					message = decode_message(body)
				except (ValueError, UnicodeError, RecursionError):
					self.enqueue(RpcError(-32700, 'invalid JSON body'), 0)
					continue
				if isinstance(message, dict) and message.get('method') == '$/cancelRequest':
					params = message.get('params', {})
					if isinstance(params, dict) and type(params.get('id')) in (int, str):
						with self.state_lock:
							if params['id'] in self.pending_requests:
								self.cancelled.add(params['id'])
					continue
				self.enqueue(body, n, message)
				if isinstance(message, dict) and message.get('method') in ('shutdown', 'exit'):
					self.stop_requested.set()
		except (OSError, ValueError, UnicodeError, RpcError) as error:
			self.input_failure = error if isinstance(error, RpcError) else RpcError(-32700, str(error))
			self.stop_requested.set()
		finally:
			self.input_done.set()

	def enqueue(self, body, size, message=None):
		with self.state_lock:
			require(self.queued_bytes + size <= MAX_QUEUE_BYTES and not self.inbox.full(),
				'protocol queue exceeds finite limit; connection closed')
			request_id = message.get('id') if isinstance(message, dict) else None
			if type(request_id) in (str, int):
				require(request_id not in self.pending_requests, 'duplicate outstanding request id; connection closed')
				self.pending_requests.add(request_id)
			self.queued_bytes += size
			self.inbox.put_nowait((body, size))

	def invoke(self, arguments, request_id=None):
		process = subprocess.Popen([str(self.compiler), *map(str, arguments)],
			stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
			start_new_session=os.name == 'posix')
		deadline = time.monotonic() + 30
		chunks = queue.Queue(maxsize=4)
		stopped = threading.Event()
		outputs = [bytearray(), bytearray()]
		def drain(stream, channel):
			try:
				while not stopped.is_set():
					data = stream.read1(65536)
					while not stopped.is_set():
						try:
							chunks.put((channel, data), timeout=0.05)
							break
						except queue.Full:
							continue
					if not data:
						return
			except OSError as error:
				while not stopped.is_set():
					try:
						chunks.put((channel, error), timeout=0.05)
						return
					except queue.Full:
						continue
		workers = [threading.Thread(target=drain, args=(stream, i), daemon=True)
			for i, stream in enumerate((process.stdout, process.stderr))]
		finished = set()
		try:
			for worker in workers:
				worker.start()
			while True:
				if self.stop_requested.is_set():
					raise RpcError(-32800, 'compiler request interrupted by connection shutdown')
				if request_id in self.cancelled:
					raise RpcError(-32800, 'request cancelled')
				if time.monotonic() > deadline:
					raise RpcError(-32803, 'compiler request exceeded 30 seconds')
				if len(finished) == 2 and process.poll() is not None:
					try:
						return process.returncode, outputs[0].decode('utf-8'), outputs[1].decode('utf-8')
					except UnicodeError as error:
						raise RpcError(-32803, 'invalid compiler output encoding') from error
				try:
					channel, data = chunks.get(timeout=0.05)
				except queue.Empty:
					continue
				if isinstance(data, OSError):
					raise data
				if not data:
					finished.add(channel)
					continue
				require(sum(map(len, outputs)) + len(data) <= MAX_BODY, 'compiler response exceeds finite limit')
				outputs[channel].extend(data)
		finally:
			stopped.set()
			# The new session belongs solely to this invocation. Kill the group even
			# if its leader exited while a descendant still holds a pipe open.
			if os.name == 'posix':
				try:
					os.killpg(process.pid, signal.SIGKILL)
				except ProcessLookupError:
					pass
			elif process.poll() is None:
				process.kill()
			process.wait()
			for worker in workers:
				if worker.ident is not None:
					worker.join(timeout=1)
			process.stdout.close()
			process.stderr.close()

	def inputs(self):
		paths = set()
		options = []
		auxiliary_bytes = 0
		if self.root is not None:
			config = self.root / 'astra-project.json'
			if config.exists():
				require(config.stat().st_size <= MAX_DOCUMENT, 'oversized project configuration')
				with config.open('rb') as stream:
					body = stream.read(MAX_DOCUMENT + 1)
				require(len(body) <= MAX_DOCUMENT, 'oversized project configuration')
				data = decode_message(body)
				require(isinstance(data, dict) and data.keys() <= {'sources', 'vapi', 'native_modules'}, 'invalid project configuration')
				for key in ('sources', 'vapi', 'native_modules'):
					values = data.get(key, [])
					require(isinstance(values, list) and len(values) <= 128, 'invalid project input list')
					for name in values:
						require(isinstance(name, str) and name and not Path(name).is_absolute() and '..' not in Path(name).parts,
							'project inputs must be explicit relative paths without parent traversal')
						path = (self.root / name).absolute()
						if key == 'sources':
							paths.add(path)
						else:
							require(path.is_file(), 'invalid project auxiliary input')
							auxiliary_bytes += path.stat().st_size
							require(auxiliary_bytes <= MAX_WORKSPACE, 'workspace inputs exceed 32 MiB')
							options += ['--vapi' if key == 'vapi' else '--import-module', str(path)]
		for uri in self.documents:
			paths.add(local_path(uri))
		require(len(paths) <= 128, 'project exceeds 128 source files')
		texts = {}
		source_bytes = 0
		for path in sorted(paths):
			uri = path.as_uri()
			if uri in self.documents:
				text = self.documents[uri]['text']
			else:
				require(path.is_file() and path.stat().st_size <= MAX_DOCUMENT, 'invalid or oversized source input')
				with path.open('rb') as stream:
					text = stream.read(MAX_DOCUMENT + 1).decode('utf-8')
			length = len(text.encode('utf-8'))
			require(length <= MAX_DOCUMENT, 'document exceeds 2 MiB')
			source_bytes += length
			require(source_bytes <= MAX_BODY, 'project sources exceed 16 MiB')
			require(source_bytes + auxiliary_bytes <= MAX_WORKSPACE, 'workspace inputs exceed 32 MiB')
			texts[uri] = text
		return texts, options

	def refresh(self, request_id=None):
		if not self.dirty:
			return
		texts, options = self.inputs()
		self.texts = texts
		index = {'symbols': [], 'references': [], 'diagnostics': []}
		if texts:
			with tempfile.TemporaryDirectory(prefix='astra-lsp-', dir=self.scratch) as temporary:
				mapping, sources = {}, []
				for i, (uri, text) in enumerate(sorted(texts.items())):
					path = Path(temporary) / f'input-{i:04d}.astra'
					path.write_bytes(text.encode('utf-8'))
					mapping[str(path)] = uri
					sources.append(path)
				status, out, err = self.invoke(['--tooling-index', *options, *sources], request_id)
				if out:
					try:
						index = decode_message(out.encode('utf-8'))
					except (ValueError, UnicodeError, RecursionError) as error:
						raise RpcError(-32803, 'invalid compiler tooling output') from error
					require(isinstance(index, dict) and index.get('format') == 'astra-tooling/1'
						and all(isinstance(index.get(key), list) for key in ('symbols', 'references', 'diagnostics')),
						'incompatible compiler tooling schema')
				else:
					index['diagnostics'] = [{'uri': next(iter(texts)), 'start': 0, 'end': 0, 'message': err.strip() or f'compiler exited {status}'}]
				for category in ('symbols', 'references', 'diagnostics'):
					for item in index[category]:
						if 'file' in item:
							item['uri'] = mapping.get(item['file'], Path(item['file']).absolute().as_uri())
		self.index = index
		self.dirty = False
		for uri in texts:
			diagnostics = []
			for item in index['diagnostics']:
				if item['uri'] == uri:
					diagnostics.append({'range': self.range(item), 'message': item['message'], 'severity': 1, 'source': 'astrac'})
			params = {'uri': uri, 'diagnostics': diagnostics}
			if uri in self.documents:
				params['version'] = self.documents[uri]['version']
			self.notify('textDocument/publishDiagnostics', params)

	def range(self, item):
		text = self.texts.get(item['uri'], '')
		return {'start': utf16_position(text, item['start']), 'end': utf16_position(text, item['end'])}

	def location(self, item):
		return {'uri': item['uri'], 'range': self.range(item)}

	def selected(self, uri, position):
		require(uri in self.texts, 'document is not in the checked project')
		offset = byte_position(self.texts[uri], position)
		for category in ('references', 'symbols'):
			matches = [i for i in self.index[category] if i['uri'] == uri and i['start'] <= offset < i['end']]
			if matches:
				item = min(matches, key=lambda i: i['end'] - i['start'])
				return next((s for s in self.index['symbols'] if s['id'] == item['id']), None)
		return None

	def dispatch(self, method, params, request_id):
		require(isinstance(params, dict), 'params must be an object')
		if method == 'initialize':
			require(not self.initialized, 'server already initialized')
			root_uri = params.get('rootUri')
			self.root = local_path(root_uri) if root_uri else None
			self.initialized = True
			return {'serverInfo': {'name': 'astra-lsp', 'version': '1'}, 'capabilities': {
				'positionEncoding': 'utf-16', 'textDocumentSync': {'openClose': True, 'change': 1},
				'hoverProvider': True, 'definitionProvider': True, 'referencesProvider': True,
				'completionProvider': {'resolveProvider': False}, 'documentFormattingProvider': True}}
		if not self.initialized:
			raise RpcError(-32002, 'server not initialized')
		if method == 'shutdown':
			self.shutdown = True
			return None
		if self.shutdown:
			raise RpcError(-32600, 'server has shut down')
		if method in ('initialized', '$/setTrace', 'textDocument/didSave'):
			return None
		if method == 'workspace/didChangeWatchedFiles':
			self.dirty = True
			self.refresh()
			return None
		if method not in ('textDocument/didOpen', 'textDocument/didChange', 'textDocument/didClose',
			'textDocument/formatting', 'textDocument/hover', 'textDocument/definition',
			'textDocument/references', 'textDocument/completion'):
			raise RpcError(-32601, 'method not supported')
		document = params.get('textDocument', {})
		require(isinstance(document, dict) and isinstance(document.get('uri'), str), 'textDocument.uri required')
		uri = local_path(document['uri']).as_uri()
		if method in ('textDocument/didOpen', 'textDocument/didChange'):
			version = document.get('version')
			require(type(version) is int, 'integer document version required')
			if method.endswith('didOpen'):
				require(uri not in self.documents, 'document already open')
				text = document.get('text')
			else:
				require(uri in self.documents, 'document is not open')
				require(version > self.documents[uri]['version'], 'stale document version ignored')
				changes = params.get('contentChanges')
				require(isinstance(changes, list) and len(changes) == 1 and isinstance(changes[0], dict)
					and changes[0].keys() == {'text'}, 'full synchronization requires exactly one text replacement')
				text = changes[0]['text']
			require(isinstance(text, str) and len(text.encode('utf-8')) <= MAX_DOCUMENT, 'invalid/oversized document text')
			length = len(text.encode('utf-8'))
			previous = self.documents.get(uri, {}).get('bytes', 0)
			require(len(self.documents) + (uri not in self.documents) <= MAX_DOCUMENTS, 'too many open documents')
			require(self.document_bytes - previous + length <= MAX_BODY, 'open documents exceed 16 MiB')
			self.documents[uri] = {'text': text, 'version': version, 'bytes': length}
			self.document_bytes += length - previous
			self.dirty = True
			self.refresh()
			return None
		if method == 'textDocument/didClose':
			closed = self.documents.pop(uri, None)
			if closed is not None:
				self.document_bytes -= closed['bytes']
			self.notify('textDocument/publishDiagnostics', {'uri': uri, 'diagnostics': []})
			self.dirty = True
			return None
		if method == 'textDocument/formatting':
			require(uri in self.documents, 'formatting requires an open document')
			text = self.documents[uri]['text']
			with tempfile.TemporaryDirectory(prefix='astra-format-', dir=self.scratch) as temporary:
				path = Path(temporary) / 'document.astra'
				path.write_bytes(text.encode('utf-8'))
				status, formatted, err = self.invoke(['--format', path], request_id)
				require(status == 0, err.strip() or 'source cannot be formatted')
			return [] if formatted == text else [{'range': {'start': {'line': 0, 'character': 0},
				'end': utf16_position(text, len(text.encode('utf-8')))}, 'newText': formatted}]
		if method not in ('textDocument/hover', 'textDocument/definition', 'textDocument/references', 'textDocument/completion'):
			raise RpcError(-32601, 'method not supported')
		self.refresh(request_id)
		if method == 'textDocument/completion':
			require(uri in self.texts, 'document is not in the project')
			offset = byte_position(self.texts[uri], params['position'])
			items = []
			for s in self.index['symbols']:
				if s['kind'] in ('local', 'parameter', 'field', 'property') and not (
					s['uri'] == uri and s.get('scope_start', s['start']) <= offset <= s.get('scope_end', s['end'])):
					continue
				if s['kind'] == 'local' and s['end'] > offset:
					continue
				items.append({'label': s['name'], 'detail': s['detail'], 'kind': 3 if s['kind'] == 'function' else 6})
			return {'isIncomplete': False, 'items': items}
		symbol = self.selected(uri, params['position'])
		if symbol is None:
			return [] if method != 'textDocument/hover' else None
		if method == 'textDocument/hover':
			return {'contents': {'kind': 'plaintext', 'value': symbol['detail']}}
		if method == 'textDocument/definition':
			return [self.location(symbol)]
		context = params.get('context', {})
		require(isinstance(context, dict), 'references context must be an object')
		include = context.get('includeDeclaration', False)
		items = [s for s in self.index['references'] if s['id'] == symbol['id']]
		if include:
			items.append(symbol)
		return [self.location(s) for s in items]

	def run(self):
		threading.Thread(target=self.reader, daemon=True).start()
		while True:
			if self.input_failure is not None:
				failure = self.input_failure
				self.send({'jsonrpc': '2.0', 'id': None, 'error': {'code': failure.code, 'message': failure.message}})
				return 1
			try:
				body, size = self.inbox.get(timeout=0.05)
			except queue.Empty:
				if self.input_failure is not None:
					continue
				if self.input_done.is_set():
					return 0 if self.shutdown else 1
				continue
			with self.state_lock:
				self.queued_bytes -= size
			message = body if isinstance(body, RpcError) else decode_message(body)
			if isinstance(message, RpcError):
				self.send({'jsonrpc': '2.0', 'id': None, 'error': {'code': message.code, 'message': message.message}})
				continue
			if not isinstance(message, dict) or message.get('jsonrpc') != '2.0' or not isinstance(message.get('method'), str):
				self.finish_request(message.get('id') if isinstance(message, dict) else None)
				self.send({'jsonrpc': '2.0', 'id': None, 'error': {'code': -32600, 'message': 'invalid request'}})
				continue
			request_id = message.get('id')
			if 'id' in message and type(request_id) not in (int, str):
				self.send({'jsonrpc': '2.0', 'id': None, 'error': {'code': -32600, 'message': 'invalid request id'}})
				continue
			if message['method'] == 'exit':
				return 0 if self.shutdown else 1
			response = None
			try:
				if request_id in self.cancelled:
					raise RpcError(-32800, 'request cancelled')
				result = self.dispatch(message['method'], message.get('params', {}), request_id)
				if 'id' in message:
					response = {'jsonrpc': '2.0', 'id': request_id, 'result': result}
			except (RpcError, OSError, ValueError, UnicodeError, KeyError, TypeError) as error:
				code = error.code if isinstance(error, RpcError) else -32602
				text = error.message if isinstance(error, RpcError) else str(error)
				if 'id' in message:
					response = {'jsonrpc': '2.0', 'id': request_id, 'error': {'code': code, 'message': text}}
				else:
					self.log(text)
			finally:
				self.finish_request(request_id)
			if response is not None:
				self.send(response)

	def finish_request(self, request_id):
		if type(request_id) in (str, int):
			with self.state_lock:
				self.cancelled.discard(request_id)
				self.pending_requests.discard(request_id)


def main():
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument('--version', action='version', version='astra-lsp 1')
	sibling = Path(__file__).resolve().with_name('astrac')
	parser.add_argument('--compiler', default=str(sibling) if sibling.is_file() else shutil.which('astrac') or 'astrac')
	parser.add_argument('--scratch-dir', type=Path)
	args = parser.parse_args()
	try:
		return Server(Path(shutil.which(args.compiler) or args.compiler).resolve(strict=True), args.scratch_dir).run()
	except (OSError, ValueError) as error:
		print(f'astra-lsp: {error}', file=sys.stderr)
		return 1


if __name__ == '__main__':
	raise SystemExit(main())
