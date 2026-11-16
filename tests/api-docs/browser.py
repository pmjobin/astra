#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Local static-preview browser evidence, with actual JavaScript-disabled controls."""
import argparse
from html.parser import HTMLParser
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT.parent/'codex/work/astra'
sys.path.insert(0, str(ROOT/'tests/selfhost-ownership-syntax-27b'))
from support import execute, output_path, sha, write


class Anchors(HTMLParser):
	def __init__(self):
		super().__init__()
		self.ids = []

	def handle_starttag(self, tag, attributes):
		for key,value in attributes:
			if key == 'id': self.ids.append(value)


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--html', type=Path, required=True)
	p.add_argument('--runtime', type=Path, required=True)
	p.add_argument('--chromium', type=Path, default=Path('/usr/bin/chromium-browser'))
	a = p.parse_args()
	assert a.html.is_absolute() and a.html.is_file() and a.chromium.is_absolute()
	runtime = output_path(a.runtime, WORK/'runtime')
	runtime.mkdir(parents=True, exist_ok=False)
	(runtime/'executed-recipe.py.txt').write_bytes(Path(__file__).read_bytes())
	before = sha(a.html)
	parsed = Anchors()
	parsed.feed(a.html.read_text())
	assert parsed.ids
	version = subprocess.check_output([a.chromium, '--version'], text=True).strip()
	control = runtime/'javascript-control.html'
	control.write_text('<!doctype html><p id="probe">NO_SCRIPT</p><script>document.getElementById("probe").textContent="SCRIPT_RAN";</script>')
	commands = []
	def browser(label, url, size='1280,900', disabled=True, screenshot=False):
		profile = runtime/(label+'-profile')
		(profile/'Default').mkdir(parents=True)
		if disabled:
			(profile/'Default/Preferences').write_text(json.dumps({'profile':{'default_content_setting_values':{'javascript':2}}}))
		argv = [a.chromium, '--headless=new', '--disable-gpu', '--no-first-run', '--no-default-browser-check', '--disable-background-networking', '--disable-component-update', '--disable-sync', '--run-all-compositor-stages-before-draw', '--virtual-time-budget=1000', '--user-data-dir='+str(profile), '--window-size='+size, '--dump-dom']
		png = runtime/(label+'.png')
		if screenshot: argv.append('--screenshot='+str(png))
		argv.append(url)
		env = dict(os.environ)
		env.pop('LD_PRELOAD', None)
		result = execute(argv, runtime/label, timeout=60, env=env)
		commands.append(dict(label=label, argv=list(map(str, argv)), result=result, screenshot_sha256=sha(png) if png.exists() else None))
		write(runtime/'commands.json', commands)
		assert result['status'] == 'EXPECTED_OUTCOME'
		if screenshot: assert png.read_bytes().startswith(b'\x89PNG\r\n\x1a\n')
		return (runtime/label/'stdout').read_text()
	assert '<p id="probe">SCRIPT_RAN</p>' in browser('script-enabled-control', control.as_uri(), disabled=False)
	assert '<p id="probe">NO_SCRIPT</p>' in browser('script-disabled-control', control.as_uri())
	for label,size,url in [('desktop', '1280,900', a.html.as_uri()), ('mobile', '390,844', a.html.as_uri()), ('fragment', '390,844', a.html.as_uri()+'#'+parsed.ids[-1])]:
		dom = browser(label, url, size=size, screenshot=True)
		assert 'astra-api-docs/1' in dom and parsed.ids[-1] in dom
	assert sha(a.html) == before
	write(runtime/'result.json', dict(status='LOCAL_STATIC_BROWSER_EXECUTION_PASS_PENDING_VISUAL_INSPECTION', HTML_sha256=before, browser=str(a.chromium), launcher_sha256=sha(a.chromium.resolve()), version=version, commands_sha256=sha(runtime/'commands.json'), scope='Actual local-file Chromium with positive/negative JavaScript controls, desktop/mobile/fragment rendering. Screenshots require visual inspection; browser/fonts are observational host dependencies, not pixel reproducibility or a deployment.'))
	print('Local static browser executed; inspect desktop.png, mobile.png and fragment.png')


if __name__ == '__main__':
	main()
