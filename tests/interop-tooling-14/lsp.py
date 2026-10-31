#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Drive a real server/compiler process with an independent framed LSP client."""
from pathlib import Path
import hashlib
import json
import os
import queue
import shutil
import subprocess
import sys
import tempfile
import threading

ROOT = Path(__file__).resolve().parents[2]
EXAMPLE = ROOT / 'examples/interop-tooling-14/editor-project'


def main(compiler_arg, output_arg):
	compiler = Path(compiler_arg).resolve()
	output = Path(output_arg).resolve()
	assert not output.is_relative_to(ROOT)
	output.mkdir(parents=True, exist_ok=True)
	work = Path(tempfile.mkdtemp(prefix='lsp-', dir=output))
	project = work / 'project'
	shutil.copytree(EXAMPLE, project)
	scratch = work / 'scratch'
	scratch.mkdir()
	rows, messages = [], []
	receipt = {'compiler_sha256': hashlib.sha256(compiler.read_bytes()).hexdigest(), 'checks': rows,
		'messages': messages, 'sources': {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in EXAMPLE.iterdir()}}
	def save():
		(work / 'checks.json').write_text(json.dumps(receipt, indent=2, ensure_ascii=False) + '\n')
	def run(command, expected=0):
		p = subprocess.run(list(map(str, command)), cwd=work, capture_output=True, text=True, timeout=90,
			env=dict(os.environ, CCACHE_DISABLE='1', PYTHONDONTWRITEBYTECODE='1'))
		rows.append({'command': list(map(str, command)), 'exit': p.returncode, 'expected_exit': expected, 'stdout': p.stdout, 'stderr': p.stderr})
		save()
		assert p.returncode == expected, rows[-1]
		return p.stdout
	for level in ('0', '1', '2'):
		product = work / ('program-O' + level)
		run([compiler, '-O' + level, *sorted(project.glob('*.astra')), '-o', product])
		run([product])
	index = json.loads(run([compiler, '--tooling-index', *sorted(project.glob('*.astra'))]))
	assert index['format'] == 'astra-tooling/1' and not index['diagnostics']
	explanation = run([compiler, '--explain-semantics', *sorted(project.glob('*.astra'))])
	assert 'intrusive shared owner' in explanation and 'assignment moves' in explanation and 'clone acquires' in explanation
	assert any(s['name'] == 'Editor14.answer' for s in index['symbols'])
	assert any(s['name'] == 'Other14.answer' for s in index['symbols'])
	run([compiler, '--tooling-index', '--runtime=none', project / 'main.astra'], expected=2)
	server = ROOT / 'tools/lsp/astra-lsp.py'
	stderr = (work / 'server.stderr').open('w')
	process = subprocess.Popen([sys.executable, server, '--compiler', compiler, '--scratch-dir', scratch],
		stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=stderr, cwd=project)
	incoming = queue.Queue()
	def read():
		try:
			while True:
				headers = {}
				while True:
					line = process.stdout.readline()
					if not line:
						raise EOFError('server stdout ended')
					if line == b'\r\n':
						break
					key, value = line.decode('ascii').strip().split(':', 1)
					headers[key.lower()] = value.strip()
				incoming.put(json.loads(process.stdout.read(int(headers['content-length']))))
		except BaseException as error:
			incoming.put(error)
	threading.Thread(target=read, daemon=True).start()
	def raw(body):
		process.stdin.write(f'Content-Length: {len(body)}\r\n\r\n'.encode() + body)
		process.stdin.flush()
	def send(method, params, id=None):
		message = {'jsonrpc': '2.0', 'method': method, 'params': params}
		if id is not None:
			message['id'] = id
		messages.append({'sent': message})
		raw(json.dumps(message, ensure_ascii=False).encode('utf-8'))
	def receive_until(predicate):
		while True:
			message = incoming.get(timeout=45)
			assert not isinstance(message, BaseException), message
			messages.append({'received': message})
			save()
			if predicate(message):
				return message
	next_id = 1
	def request(method, params, error=None):
		nonlocal next_id
		id = next_id
		next_id += 1
		send(method, params, id)
		message = receive_until(lambda m: m.get('id') == id)
		if error is not None:
			assert message.get('error', {}).get('code') == error, message
		else:
			assert 'result' in message, message
		return message.get('result')
	uri = (project / 'main.astra').as_uri()
	text = (project / 'main.astra').read_text()
	line = text.splitlines()[4]
	character = len(line[:line.index('answer')].encode('utf-16-le')) // 2
	position = {'line': 4, 'character': character + 1}
	params = {'textDocument': {'uri': uri}, 'position': position}
	def diagnostics(version):
		return receive_until(lambda m: m.get('method') == 'textDocument/publishDiagnostics'
			and m['params']['uri'] == uri and m['params'].get('version') == version)['params']['diagnostics']
	try:
		request('textDocument/hover', params, -32002)
		caps = request('initialize', {'rootUri': project.as_uri(), 'capabilities': {}})['capabilities']
		assert caps['positionEncoding'] == 'utf-16' and caps['textDocumentSync']['change'] == 1
		assert not caps.get('renameProvider')
		send('initialized', {})
		send('textDocument/didOpen', {'textDocument': {'uri': uri, 'languageId': 'astra', 'version': 1, 'text': text}})
		assert diagnostics(1) == []
		hover = request('textDocument/hover', params)
		assert 'Editor14.answer' in hover['contents']['value']
		definition = request('textDocument/definition', params)
		assert len(definition) == 1 and definition[0]['uri'] == (project / 'library.astra').as_uri()
		references = request('textDocument/references', {**params, 'context': {'includeDeclaration': True}})
		assert len(references) == 2 and any(i['uri'] == uri and i['range']['start']['character'] == character for i in references)
		completion = request('textDocument/completion', params)
		assert any(i['label'] == 'Editor14.answer' for i in completion['items'])
		request('workspace/unsupported', {}, -32601)
		request('textDocument/references', {**params, 'context': []}, -32602)
		astral = len(line[:line.index('💙')].encode('utf-16-le')) // 2
		request('textDocument/hover', {**params, 'position': {'line': 4, 'character': astral + 1}}, -32602)
		bad = text.replace('answer(cell', 'missing(cell')
		send('textDocument/didChange', {'textDocument': {'uri': uri, 'version': 2}, 'contentChanges': [{'text': bad}]})
		errors = diagnostics(2)
		assert len(errors) == 1 and 'missing' in errors[0]['message'] and errors[0]['range']['start']['character'] == character
		send('textDocument/didChange', {'textDocument': {'uri': uri, 'version': 1}, 'contentChanges': [{'text': text}]})
		receive_until(lambda m: m.get('method') == 'window/logMessage' and 'stale' in m['params']['message'])
		send('textDocument/didChange', {'textDocument': {'uri': uri, 'version': 3}, 'contentChanges': [{'text': text}]})
		assert diagnostics(3) == []
		send('textDocument/didChange', {'textDocument': {'uri': uri, 'version': 4}, 'contentChanges': [{'range': {}, 'text': 'invalid'}]})
		receive_until(lambda m: m.get('method') == 'window/logMessage' and 'full synchronization' in m['params']['message'])
		assert 'Editor14.answer' in request('textDocument/hover', params)['contents']['value']
		spaces = text.replace('\t', '    ')
		send('textDocument/didChange', {'textDocument': {'uri': uri, 'version': 4}, 'contentChanges': [{'text': spaces}]})
		assert diagnostics(4) == []
		edits = request('textDocument/formatting', {'textDocument': {'uri': uri}, 'options': {'tabSize': 4, 'insertSpaces': False}})
		assert len(edits) == 1 and edits[0]['newText'] == text
		raw(b'{')
		receive_until(lambda m: m.get('error', {}).get('code') == -32700)
		raw(b'null')
		receive_until(lambda m: m.get('error', {}).get('code') == -32600)
		spaced_line = spaces.splitlines()[4]
		params = {**params, 'position': {'line': 4,
			'character': len(spaced_line[:spaced_line.index('answer')].encode('utf-16-le')) // 2 + 1}}
		send('$/cancelRequest', {'id': next_id})
		# ADR 0168: unknown IDs cannot reserve cancellation state for future work.
		assert 'Editor14.answer' in request('textDocument/hover', params)['contents']['value']
		request('textDocument/hover', params)
		send('textDocument/didClose', {'textDocument': {'uri': uri}})
		receive_until(lambda m: m.get('method') == 'textDocument/publishDiagnostics' and m['params']['uri'] == uri and not m['params']['diagnostics'])
		request('shutdown', {})
		send('exit', {})
		assert process.wait(timeout=10) == 0
		assert (project / 'main.astra').read_text() == text
		assert not list(scratch.iterdir())
		receipt['status'] = 'PASS'
		save()
		print(f'PASS: compiler index, policy inspection, O0/O1/O2 execution and {len(messages)} real LSP messages; evidence {work}')
	finally:
		if process.poll() is None:
			process.kill()
			process.wait()
		stderr.close()


if __name__ == '__main__':
	main(*sys.argv[1:])
