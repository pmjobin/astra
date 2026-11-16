#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Observe local fragment layout through Chromium; page JavaScript stays disabled.

The optional host-only websockets package transports DevTools messages. Neither
documentation extraction nor the renderer depends on a browser or this package.
"""
import argparse
import base64
from html.parser import HTMLParser
import importlib.metadata
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import urllib.request
from websockets.sync.client import connect
from websockets.exceptions import ConnectionClosed

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT.parent/'codex/work/astra'
sys.path.insert(0, str(ROOT/'tests/selfhost-ownership-syntax-27b'))
from support import output_path, sha, write


class Targets(HTMLParser):
	def __init__(self):
		super().__init__()
		self.ids = []

	def handle_starttag(self, tag, attributes):
		for key,value in attributes:
			if key == 'id' and tag == 'section': self.ids.append(value)


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--html', type=Path, required=True)
	p.add_argument('--runtime', type=Path, required=True)
	p.add_argument('--chromium', type=Path, default=Path('/usr/bin/chromium-browser'))
	a = p.parse_args()
	assert a.html.is_absolute() and a.html.is_file()
	runtime = output_path(a.runtime, WORK/'runtime')
	runtime.mkdir(parents=True, exist_ok=False)
	(runtime/'executed-recipe.py.txt').write_bytes(Path(__file__).read_bytes())
	before = sha(a.html)
	parsed = Targets()
	parsed.feed(a.html.read_text())
	assert parsed.ids
	target = parsed.ids[-1]
	profile = runtime/'profile'
	(profile/'Default').mkdir(parents=True)
	(profile/'Default/Preferences').write_text(json.dumps({'profile':{'default_content_setting_values':{'javascript':2}}}))
	argv = [str(a.chromium), '--headless=new', '--disable-gpu', '--no-first-run', '--no-default-browser-check', '--disable-background-networking', '--disable-component-update', '--disable-sync', '--remote-debugging-port=0', '--user-data-dir='+str(profile), 'about:blank']
	write(runtime/'argv.json', argv)
	protocol = []
	with (runtime/'stdout').open('wb') as out, (runtime/'stderr').open('wb') as err:
		child = subprocess.Popen(['/usr/bin/time', '-v', '-o', runtime/'time.txt', '--', *argv], stdout=out, stderr=err, start_new_session=True)
		try:
			deadline = time.monotonic()+15
			while not (profile/'DevToolsActivePort').exists():
				assert time.monotonic() < deadline and child.poll() is None
				time.sleep(.05)
			port = (profile/'DevToolsActivePort').read_text().splitlines()[0]
			opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
			meta = json.loads(opener.open('http://127.0.0.1:'+port+'/json/version', timeout=10).read())
			with connect(meta['webSocketDebuggerUrl'], proxy=None, open_timeout=10) as ws:
				sequence = 0
				def call(method, params=None, session=None):
					nonlocal sequence
					sequence += 1
					request = dict(id=sequence, method=method, params=params or {})
					if session: request['sessionId'] = session
					protocol.append(dict(request=request))
					ws.send(json.dumps(request))
					while True:
						reply = json.loads(ws.recv(timeout=15))
						if method != 'Page.captureScreenshot': protocol.append(dict(response=reply))
						if reply.get('id') == sequence:
							assert 'error' not in reply, reply
							return reply.get('result', {})
				tid = call('Target.createTarget', {'url':'about:blank'})['targetId']
				sid = call('Target.attachToTarget', {'targetId':tid, 'flatten':True})['sessionId']
				call('Page.enable', session=sid)
				call('DOM.enable', session=sid)
				call('Emulation.setDeviceMetricsOverride', dict(width=390, height=844, deviceScaleFactor=1, mobile=False), sid)
				call('Page.navigate', {'url':a.html.as_uri()+'#'+target}, sid)
				time.sleep(1)
				metrics = call('Page.getLayoutMetrics', session=sid)
				root = call('DOM.getDocument', session=sid)['root']['nodeId']
				node = call('DOM.querySelector', {'nodeId':root, 'selector':'#'+target}, sid)['nodeId']
				assert node
				box = call('DOM.getBoxModel', {'nodeId':node}, sid)['model']
				assert metrics['cssLayoutViewport']['pageY'] > 0 and 0 <= box['content'][1] < 844
				capture = call('Page.captureScreenshot', {'format':'png', 'captureBeyondViewport':False}, sid)
				(runtime/'fragment.png').write_bytes(base64.b64decode(capture['data'], validate=True))
				try: call('Browser.close')
				except ConnectionClosed: pass
			child.wait(timeout=10)
		finally:
			if child.poll() is None:
				os.killpg(child.pid, 15)
				child.wait(timeout=10)
	assert sha(a.html) == before
	write(runtime/'protocol.json', protocol)
	modules = {str(Path(module.__file__).resolve()):sha(module.__file__) for name,module in sys.modules.items() if name.startswith('websockets') and getattr(module, '__file__', None)}
	write(runtime/'result.json', dict(status='LOCAL_FRAGMENT_LAYOUT_AND_CAPTURE_PASS_PENDING_VISUAL_INSPECTION', HTML_sha256=before, target=target, metrics=metrics, box=box, screenshot_sha256=sha(runtime/'fragment.png'), protocol_sha256=sha(runtime/'protocol.json'), chromium_version=meta['Browser'], browser_exit=child.returncode, websockets_version=importlib.metadata.version('websockets'), host_transport_modules=modules, scope='Actual local Chromium fragment scrolling with page scripts disabled; screenshot requires visual inspection. Optional host observation dependency only; no deployment or runtime dependency of documentation tools.'))
	print('Fragment layout and capture observed; inspect fragment.png')


if __name__ == '__main__':
	main()
