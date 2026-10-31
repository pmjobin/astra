#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Bounded fake-compiler and framed-client adversarial LSP qualification."""
from pathlib import Path
import argparse
import hashlib
import importlib.util
import json
import os
import queue
import resource
import subprocess
import sys
import tempfile
import threading
import time

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
SERVER = ROOT / 'tools/lsp/astra-lsp.py'

FAKE = '''#!/usr/bin/python3
import json,os,subprocess,sys,threading,time
from pathlib import Path
base=Path(__file__).parent
(base/'child.pid').write_text(str(os.getpid()))
mode=sys.argv[1] if len(sys.argv)>1 else ''
def write(fd,n):
 while n:
  chunk=b'x'*min(n,65536)
  n-=os.write(fd,chunk)
if mode=='finite':
 n=int(sys.argv[2]); a=threading.Thread(target=write,args=(1,n//2));a.start();write(2,n-n//2);a.join()
elif mode=='flood':
 a=threading.Thread(target=write,args=(1,64*1024**2));a.start();write(2,64*1024**2);a.join()
 (base/'completed').write_text('yes')
elif mode=='crash': sys.exit(7)
elif mode=='invalid': os.write(1,b'\\xff')
elif mode=='stall': time.sleep(60)
elif mode=='slow':
 for i in range(10):
  os.write(1,b'a'*8192);os.write(2,b'b'*8192);time.sleep(0.01)
elif mode=='descendant':
 p=subprocess.Popen([sys.executable,'-c','import time; time.sleep(60)'])
 (base/'descendant.pid').write_text(str(p.pid))
 time.sleep(60)
elif mode=='--format':
 if (base/'stall').exists(): time.sleep(60)
 sys.stdout.write(Path(sys.argv[2]).read_text() + (' ' if (base/'different').exists() else ''))
else: print(json.dumps(dict(format='astra-tooling/1',symbols=[],references=[],diagnostics=[])))
'''


def frame(message):
	body = json.dumps(message).encode() if not isinstance(message, bytes) else message
	return f'Content-Length: {len(body)}\r\n\r\n'.encode() + body


class Client:
	def __init__(self, compiler, work):
		self.exiting = False
		self.messages = queue.Queue(maxsize=256)
		self.stderr = (work / 'server.stderr').open('w')
		self.process = subprocess.Popen([sys.executable, SERVER, '--compiler', compiler,
			'--scratch-dir', work], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
			stderr=self.stderr, env=dict(os.environ, PYTHONDONTWRITEBYTECODE='1'))
		def read():
			try:
				while True:
					headers = {}
					while True:
						line = self.process.stdout.readline()
						if not line: raise EOFError()
						if line == b'\r\n': break
						key, value = line.decode().split(':', 1)
						headers[key.lower()] = value.strip()
					self.messages.put(json.loads(self.process.stdout.read(int(headers['content-length']))), timeout=5)
			except BaseException as error:
				self.messages.put(error, timeout=5)
		self.worker = threading.Thread(target=read, daemon=True)
		self.worker.start()

	def send(self, method, params=None, id=None):
		if method == 'exit': self.exiting = True
		message = dict(jsonrpc='2.0', method=method, params=params or {})
		if id is not None: message['id'] = id
		self.process.stdin.write(frame(message))
		self.process.stdin.flush()

	def receive(self, id, timeout=5):
		while True:
			message = self.messages.get(timeout=timeout)
			assert not isinstance(message, BaseException), repr(message)
			if message.get('id', object()) == id: return message

	def close(self, expected=0):
		try:
			if self.process.poll() is None and not self.exiting:
				self.send('shutdown', id=900000)
				assert 'result' in self.receive(900000)
				self.send('exit')
			assert self.process.wait(timeout=5) == expected
		finally:
			if self.process.poll() is None: self.process.kill()
			self.process.wait()
			self.process.stdin.close()
			self.worker.join(timeout=2)
			self.process.stdout.close()
			self.stderr.close()


def main():
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument('output', type=Path)
	parser.add_argument('--deadlines', action='store_true', help='also exercise the unchanged actual 30-second deadlines')
	args = parser.parse_args()
	out = args.output.resolve()
	assert not out.is_relative_to(ROOT)
	out.mkdir(parents=True, exist_ok=True)
	out = Path(tempfile.mkdtemp(prefix='lsp-', dir=out))
	fake = out / 'compiler.py'
	fake.write_text(FAKE)
	fake.chmod(0o700)
	spec = importlib.util.spec_from_file_location('astra_lsp', SERVER)
	lsp = importlib.util.module_from_spec(spec)
	spec.loader.exec_module(lsp)
	receipt = {'server_sha256': hashlib.sha256(SERVER.read_bytes()).hexdigest(), 'checks': []}
	# ru_maxrss can retain an ancestor's high-water value across fork/exec.
	# Sample the actual resident working sets of this test and its live children.
	sampling_done = threading.Event()
	peaks = {'sampled_parent_rss_kib': 0, 'sampled_tree_rss_kib': 0, 'sampled_live_children': 0}
	def sample():
		while not sampling_done.is_set():
			pending = [os.getpid()]; rss = 0; live = 0
			while pending:
				pid = pending.pop()
				try:
					status = Path(f'/proc/{pid}/status').read_text()
					resident = next((int(line.split()[1]) for line in status.splitlines() if line.startswith('VmRSS:')), 0)
					if pid == os.getpid(): peaks['sampled_parent_rss_kib'] = max(peaks['sampled_parent_rss_kib'], resident)
					elif resident: live += 1
					rss += resident
					pending.extend(map(int, Path(f'/proc/{pid}/task/{pid}/children').read_text().split()))
				except (OSError, ValueError): pass
			peaks['sampled_tree_rss_kib'] = max(peaks['sampled_tree_rss_kib'], rss)
			peaks['sampled_live_children'] = max(peaks['sampled_live_children'], live)
			sampling_done.wait(0.01)
	sampler = threading.Thread(target=sample, daemon=True); sampler.start()
	def check(name, action):
		start = time.monotonic()
		try:
			action()
		except BaseException as error:
			receipt['checks'].append(dict(name=name, passed=False, error=repr(error), seconds=time.monotonic()-start))
			(out / 'checks.json').write_text(json.dumps(receipt, indent=2) + '\n')
			raise
		receipt['checks'].append(dict(name=name, passed=True, seconds=time.monotonic()-start,
			inherited_ru_maxrss_kib=resource.getrusage(resource.RUSAGE_SELF).ru_maxrss, **peaks))
		(out / 'checks.json').write_text(json.dumps(receipt, indent=2) + '\n')
		print(name, 'PASS', flush=True)
	def refused(action, contains):
		try: action()
		except lsp.RpcError as error: assert contains in error.message, error.message
		else: raise AssertionError('expected refusal: ' + contains)
	def conserved():
		pid = int((out / 'child.pid').read_text())
		assert not Path(f'/proc/{pid}').exists(), f'compiler child survived: {pid}'
	def finite(n):
		s = lsp.Server(fake, out)
		if n <= lsp.MAX_BODY:
			status, stdout, stderr = s.invoke(['finite', n])
			assert status == 0 and len(stdout) + len(stderr) == n
		else: refused(lambda: s.invoke(['finite', n]), 'finite limit')
		conserved()
	for n in [lsp.MAX_BODY-1, lsp.MAX_BODY, lsp.MAX_BODY+1]:
		check(f'combined-output-{n}', lambda n=n: finite(n))
	def flood():
		refused(lambda: lsp.Server(fake,out).invoke(['flood']), 'finite limit')
		assert not (out / 'completed').exists()
		conserved()
	check('simultaneous-flood-stopped-before-completion', flood)
	def crash():
		assert lsp.Server(fake,out).invoke(['crash']) == (7, '', '')
		conserved()
	check('preserve-child-exit', crash)
	def slow():
		status, stdout, stderr = lsp.Server(fake,out).invoke(['slow'])
		assert status==0 and stdout=='a'*81920 and stderr=='b'*81920
		conserved()
	check('slow-concurrent-streams',slow)
	check('invalid-output-encoding', lambda: refused(lambda: lsp.Server(fake,out).invoke(['invalid']), 'encoding'))
	def cancellation(mode):
		s = lsp.Server(fake, out)
		timer = threading.Timer(0.15, lambda: s.cancelled.add(17))
		timer.start()
		try: refused(lambda: s.invoke([mode], 17), 'cancelled')
		finally: timer.join()
		conserved()
		if mode == 'descendant':
			pid = int((out / 'descendant.pid').read_text())
			p = Path(f'/proc/{pid}/stat')
			assert not p.exists() or p.read_text().split(') ', 1)[1].startswith('Z'), 'live descendant survived'
	check('cancel-stalled-child', lambda: cancellation('stall'))
	check('cancel-descendant-group-no-live-survivor', lambda: cancellation('descendant'))
	def queue_limits():
		s = lsp.Server(fake,out)
		for i in range(lsp.MAX_QUEUED): s.enqueue(b'{}', 2, {'id':i})
		refused(lambda: s.enqueue(b'{}',2,{'id':1000}), 'queue')
		assert len(s.pending_requests)==lsp.MAX_QUEUED and s.inbox.qsize()==lsp.MAX_QUEUED
		s = lsp.Server(fake,out)
		for i in range(2): s.enqueue(b'x'*lsp.MAX_BODY,lsp.MAX_BODY)
		refused(lambda: s.enqueue(b'x',1), 'queue')
	check('queue-count-and-byte-boundaries',queue_limits)
	def documents():
		s = lsp.Server(fake,out); s.initialized=True
		s.refresh=lambda *args: None
		s.notify=lambda *args: None
		def opened(i,text): s.dispatch('textDocument/didOpen', {'textDocument':{'uri':(out/f'{i}.astra').as_uri(),'version':1,'text':text}},None)
		for i in range(8): opened(i,'x'*lsp.MAX_DOCUMENT)
		refused(lambda: opened(8,'x'), '16 MiB')
		assert len(s.documents)==8 and s.document_bytes==lsp.MAX_BODY
		for i in range(8): s.dispatch('textDocument/didClose',{'textDocument':{'uri':(out/f'{i}.astra').as_uri()}},None)
		assert s.document_bytes==0
		for i in range(lsp.MAX_DOCUMENTS): opened(i,'')
		refused(lambda: opened(129,''), 'too many')
	check('aggregate-document-bytes-count-and-close',documents)
	def workspace():
		s = lsp.Server(fake,out); s.root=out
		config=out/'astra-project.json'; vapi=out/'large.vapi'; source=out/'tiny.astra'
		with vapi.open('wb') as stream: stream.truncate(lsp.MAX_WORKSPACE)
		config.write_text(json.dumps({'vapi':['large.vapi'],'sources':['tiny.astra']}))
		source.write_text('x')
		refused(s.inputs,'32 MiB')
		source.write_text('')
		assert s.inputs()[0]=={source.as_uri():''}
		with vapi.open('wb') as stream: stream.truncate(lsp.MAX_WORKSPACE+1)
		refused(s.inputs,'32 MiB')
		config.unlink(); vapi.unlink(); source.unlink()
	check('workspace-aggregate-input-boundary',workspace)
	def protocol():
		c = Client(fake,out)
		try:
			for body in [b'{"jsonrpc":"2.0","method":"initialize","method":"exit","id":1}',
				b'{"jsonrpc":"2.0","method":"initialize","params":{"x":"\\ud800"},"id":1}']:
				c.process.stdin.write(frame(body)); c.process.stdin.flush()
				assert c.receive(None)['error']['code']==-32700
			c.send('initialize',id=1); assert 'result' in c.receive(1)
			uri=(out/'document.astra').as_uri()
			c.send('textDocument/didOpen',{'textDocument':dict(uri=uri,version=1,text='int main() { return 0; }\n')})
			c.send('textDocument/hover',{'textDocument':{'uri':uri},'position':{'line':0,'character':0}},2)
			assert 'result' in c.receive(2)
			(out/'stall').touch()
			c.send('textDocument/formatting',{'textDocument':{'uri':uri}},3)
			c.send('textDocument/formatting',{'textDocument':{'uri':uri}},4)
			c.send('$/cancelRequest',{'id':4}); c.send('$/cancelRequest',{'id':3})
			assert c.receive(3)['error']['code']==-32800
			assert c.receive(4)['error']['code']==-32800
			(out/'stall').unlink()
			for i in range(1000): c.send('$/cancelRequest',{'id':10000+i})
			c.send('$/cancelRequest',{'id':3})
			c.send('textDocument/formatting',{'textDocument':{'uri':uri}},3)
			assert c.receive(3)['result']==[]
			(out/'stall').touch()
			c.send('textDocument/formatting',{'textDocument':{'uri':uri}},5)
			c.send('shutdown',id=6)
			assert c.receive(5)['error']['code']==-32800
			assert c.receive(6)['result'] is None
			c.send('exit')
		finally:
			c.close()
			(out/'stall').unlink(missing_ok=True)
		conserved()
	check('framed-json-cancel-queue-id-reuse-shutdown',protocol)
	def malformed_eof():
		for wire in [b'Content-Length: 100\r\n',b'Content-Length: 100\r\n\r\n{}',
			b'Content-Length: 2\r\nContent-Length: 2\r\n\r\n{}',b'Bad\n',
			b'Content-Length: 16777217\r\n\r\n']:
			p=subprocess.run([sys.executable,SERVER,'--compiler',fake,'--scratch-dir',out],
				input=wire,capture_output=True,timeout=5)
			assert p.returncode==1 and b'"code":-32700' in p.stdout,(wire,p)
	check('truncated-duplicate-malformed-oversized-frames',malformed_eof)
	def overload():
		c=Client(fake,out)
		try:
			c.send('initialize',id=1);c.receive(1)
			uri=(out/'document.astra').as_uri()
			c.send('textDocument/didOpen',{'textDocument':dict(uri=uri,version=1,text='int main() { return 0; }\n')})
			c.send('textDocument/hover',{'textDocument':{'uri':uri},'position':{'line':0,'character':0}},2)
			c.receive(2)
			(out/'stall').touch()
			c.send('textDocument/formatting',{'textDocument':{'uri':uri}},3)
			# All remaining work is queued behind this compiler invocation.
			for i in range(140):
				try: c.send('textDocument/hover',{'textDocument':{'uri':uri},'position':{'line':0,'character':0}},10+i)
				except BrokenPipeError: break
			assert 'queue' in c.receive(None)['error']['message']
			assert c.process.wait(timeout=5)==1
		finally:
			c.close(expected=1);(out/'stall').unlink(missing_ok=True)
		conserved()
	check('public-queue-overload-closes-explicitly',overload)
	if args.deadlines:
		check('actual-30-second-compiler-deadline',lambda: refused(lambda: lsp.Server(fake,out).invoke(['stall']), '30 seconds'))
		def partial():
			c = Client(fake,out)
			try:
				c.process.stdin.write(b'Content-Length: 100\r\n\r\n{'); c.process.stdin.flush()
				assert 'deadline' in c.receive(None,timeout=35)['error']['message']
				assert c.process.wait(timeout=5)==1
			finally: c.close(expected=1)
		check('actual-30-second-partial-frame-deadline',partial)
		def blocked_output():
			(out/'different').touch()
			p=subprocess.Popen([sys.executable,SERVER,'--compiler',fake,'--scratch-dir',out],
				stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
			try:
				uri=(out/'large.astra').as_uri()
				messages=[dict(jsonrpc='2.0',method='initialize',id=1),
					dict(jsonrpc='2.0',method='textDocument/didOpen',params={'textDocument':dict(uri=uri,version=1,text='x'*(2*1024**2))}),
					dict(jsonrpc='2.0',method='textDocument/formatting',id=2,params={'textDocument':{'uri':uri}})]
				for m in messages: p.stdin.write(frame(m));p.stdin.flush()
				# No stdout consumer: the server must release its blocked write itself.
				assert p.wait(timeout=35)==1
				assert b'output exceeded progress deadline' in p.stderr.read()
				conserved()
			finally:
				if p.poll() is None: p.kill()
				p.wait();p.stdin.close();p.stdout.close();p.stderr.close()
				(out/'different').unlink(missing_ok=True)
		check('actual-30-second-output-backpressure-deadline',blocked_output)
	sampling_done.set();sampler.join()
	receipt['resource_scope'] = '10 ms /proc RSS samples of this test and descendants while parentage is visible; ru_maxrss may include inherited history; short-lived peaks may be missed'
	(out/'checks.json').write_text(json.dumps(receipt,indent=2)+'\n')
	print(out/'checks.json')


if __name__=='__main__': main()
