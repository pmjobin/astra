#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Real local Chromium reading, keyboard, responsive and print-media evidence."""
import argparse
import base64
import json
import os
from pathlib import Path
import subprocess
import sys
import time
from urllib.request import urlopen

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT.parent/'codex/work/astra'
sys.path.insert(0,str(ROOT/'tests/selfhost-ownership-syntax-27b'))
from support import execute, output_path, sha, write

CDP = r'''
(async () => {
 const ws = new WebSocket(process.argv[1]);
 await new Promise((resolve,reject) => { ws.onopen=resolve; ws.onerror=reject; });
 let serial=0; const pending=new Map();
 ws.onmessage=event => { const row=JSON.parse(event.data); if (row.id) { const pair=pending.get(row.id); pending.delete(row.id); if(row.error) pair[1](Error(JSON.stringify(row.error))); else pair[0](row.result); } };
 const cmd=(method,params={}) => new Promise((resolve,reject) => { const id=++serial; pending.set(id,[resolve,reject]); ws.send(JSON.stringify({id,method,params})); });
 const evaluate=async expression => { const row=await cmd('Runtime.evaluate',{expression,returnByValue:true}); if(row.exceptionDetails) throw Error(JSON.stringify(row.exceptionDetails)); return row.result.value; };
 await cmd('Page.enable');
 await cmd('Emulation.setScriptExecutionDisabled',{value:true});
 for(let i=0;i<100;i++) { if(await evaluate('document.readyState')==='complete') break; await new Promise(r=>setTimeout(r,50)); }
 await cmd('Input.dispatchKeyEvent',{type:'keyDown',key:'Tab',code:'Tab',windowsVirtualKeyCode:9});
 await cmd('Input.dispatchKeyEvent',{type:'keyUp',key:'Tab',code:'Tab',windowsVirtualKeyCode:9});
 const first=await evaluate('document.activeElement.textContent');
 if(first!=='Skip to content') throw Error('first Tab does not reach skip link: '+first);
 await cmd('Input.dispatchKeyEvent',{type:'keyDown',key:'Enter',code:'Enter',windowsVirtualKeyCode:13});
 await cmd('Input.dispatchKeyEvent',{type:'keyUp',key:'Enter',code:'Enter',windowsVirtualKeyCode:13});
 const focused=await evaluate('document.activeElement.id');
 if(focused!=='content') throw Error('skip link did not focus main: '+focused);
 await cmd('Input.dispatchKeyEvent',{type:'keyDown',key:'Tab',code:'Tab',windowsVirtualKeyCode:9});
 await cmd('Input.dispatchKeyEvent',{type:'keyUp',key:'Tab',code:'Tab',windowsVirtualKeyCode:9});
 const next=await evaluate('document.activeElement.tagName');
 if(next!=='A') throw Error('content link not keyboard reachable');
 await cmd('Emulation.setDeviceMetricsOverride',{width:390,height:844,deviceScaleFactor:1,mobile:true});
 const mobile=await evaluate('({width:innerWidth,scroll:document.documentElement.scrollWidth})');
 if(mobile.scroll>mobile.width) throw Error('horizontal page overflow '+JSON.stringify(mobile));
 await cmd('Emulation.setEmulatedMedia',{media:'print'});
 const media=await evaluate('matchMedia("print").matches');
 if(!media) throw Error('print media not active');
 const chapterBreak=await evaluate('getComputedStyle(document.querySelector(".chapter + .chapter")).breakBefore');
 const codeWrap=await evaluate('getComputedStyle(document.querySelector("pre")).whiteSpace');
 if(chapterBreak!=='page' || codeWrap!=='pre-wrap') throw Error('print pagination/code wrapping missing');
 await evaluate('scrollTo(0,0)');
 const shot=await cmd('Page.captureScreenshot',{format:'png'});
 await cmd('Emulation.setEmulatedMedia',{media:''});
 const chapters=JSON.parse(process.argv[2]);
 const chapterChecks=[];
 for (let at=0;at<chapters.length;at++) {
  const chapter=chapters[at];
  await cmd('Page.navigate',{url:chapter.url});
  let loaded=false;
  for(let i=0;i<200;i++) {
   if(await evaluate('document.readyState === "complete" && document.URL === '+JSON.stringify(chapter.url))) { loaded=true; break; }
   await new Promise(r=>setTimeout(r,50));
  }
  if(!loaded) throw Error('chapter did not load: '+chapter.url);
  const actual=await evaluate('({width:innerWidth,scroll:document.documentElement.scrollWidth,nav:[...document.querySelectorAll(".desktop-toc nav ol a")].map(a=>a.textContent),previous:document.querySelector("a[rel=prev]")?.href||null,next:document.querySelector("a[rel=next]")?.href||null,text:document.querySelector("main").textContent.length})');
  if(actual.scroll>actual.width || actual.text<500) throw Error('unreadable mobile chapter: '+chapter.url);
  if(JSON.stringify(actual.nav)!==JSON.stringify(chapters.map(c=>c.title))) throw Error('chapter navigation order differs');
  if(actual.previous!==(chapters[at-1]?.url||null) || actual.next!==(chapters[at+1]?.url||null)) throw Error('previous/next chapter mismatch');
  chapterChecks.push({url:chapter.url,...actual});
 }
 console.log(JSON.stringify({first,focused,next,mobile,printMedia:media,chapterBreak,codeWrap,chapterChecks,printScreenshot:shot.data}));
 ws.close();
})().catch(error => { console.error(error.stack); process.exitCode=1; });
'''


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--site',type=Path,required=True)
	p.add_argument('--runtime',type=Path,required=True)
	a = p.parse_args()
	runtime = output_path(a.runtime,WORK/'runtime'); runtime.mkdir(parents=True,exist_ok=False)
	assert a.site.is_absolute() and (a.site/'guide/print.html').is_file()
	browser = Path('/usr/bin/chromium-browser')
	version = subprocess.check_output([browser,'--version'],text=True).strip()
	flags = [str(browser),'--headless=new','--disable-gpu','--no-first-run','--no-default-browser-check','--disable-background-networking','--disable-component-update','--disable-sync']
	commands = []; screenshots = {}
	def run(label,argv):
		result = execute(argv,runtime/label,timeout=60)
		commands.append(dict(label=label,argv=list(map(str,argv)),result=result)); write(runtime/'commands.json',commands)
		assert result['status']=='EXPECTED_OUTCOME',(label,(runtime/label/'stderr').read_text())
		return (runtime/label/'stdout').read_text()
	control = runtime/'javascript-control.html'
	control.write_text('<!doctype html><p id="probe">NO_SCRIPT</p><script>document.getElementById("probe").textContent="SCRIPT_RAN";</script>')
	for disabled in (False,True):
		label = 'script-disabled' if disabled else 'script-enabled'; profile = runtime/(label+'-profile')
		(profile/'Default').mkdir(parents=True)
		if disabled: (profile/'Default/Preferences').write_text(json.dumps({'profile':{'default_content_setting_values':{'javascript':2}}}))
		dom = run(label,[*flags,'--user-data-dir='+str(profile),'--dump-dom',control.as_uri()])
		assert ('<p id="probe">NO_SCRIPT</p>' if disabled else '<p id="probe">SCRIPT_RAN</p>') in dom
	chapters = [row for row in json.loads((ROOT/'docs/chapters.json').read_text())['chapters'] if row.get('book') == 'guide']
	pages = [('reference-desktop','1280,900','reference/README.html'),('api-library-desktop','1280,900','api/library.html'),('api-compiler-desktop','1280,900','api/compiler.html')]
	pages += [(row['id'],'390,844' if row['number'] % 2 else '1280,900',str(Path(row['source']).with_suffix('.html'))) for row in chapters]
	for label,size,page in pages:
		profile = runtime/(label+'-profile'); (profile/'Default').mkdir(parents=True)
		(profile/'Default/Preferences').write_text(json.dumps({'profile':{'default_content_setting_values':{'javascript':2}}}))
		png = runtime/(label+'.png')
		dom = run(label,[*flags,'--user-data-dir='+str(profile),'--window-size='+size,'--screenshot='+str(png),'--dump-dom',(a.site/page).as_uri()])
		title = 'Astra API reference</title>' if page.startswith('api/') else 'Astra 28-A2</title>'
		assert 'id="content"' in dom and title in dom and png.read_bytes().startswith(b'\x89PNG\r\n\x1a\n')
		screenshots[str(png)] = sha(png)
	profile = runtime/'keyboard-profile'; (profile/'Default').mkdir(parents=True)
	(profile/'Default/Preferences').write_text(json.dumps({'profile':{'default_content_setting_values':{'javascript':2}}}))
	argv = [*flags,'--user-data-dir='+str(profile),'--remote-debugging-port=0',(a.site/'guide/print.html').as_uri()]
	with (runtime/'keyboard-browser.stdout').open('wb') as out,(runtime/'keyboard-browser.stderr').open('wb') as err:
		process = subprocess.Popen(argv,stdout=out,stderr=err)
		try:
			portfile = profile/'DevToolsActivePort'
			deadline = time.monotonic()+30
			while not portfile.exists() and time.monotonic()<deadline:
				assert process.poll() is None,'browser exited before debugger opened'
				time.sleep(.05)
			port = int(portfile.read_text().splitlines()[0])
			with urlopen('http://127.0.0.1:'+str(port)+'/json/list',timeout=10) as response: pages = json.load(response)
			page = next(row for row in pages if row['type']=='page' and row['url'].startswith('file:'))
			(runtime/'keyboard-recipe.js.txt').write_text(CDP)
			chapter_inputs = [dict(url=(a.site/Path(row['source']).with_suffix('.html')).as_uri(),title=row['title']) for row in chapters]
			result = json.loads(run('keyboard-and-print',['node','-e',CDP,page['webSocketDebuggerUrl'],json.dumps(chapter_inputs)]))
			png = runtime/'print-preview.png'; png.write_bytes(base64.b64decode(result.pop('printScreenshot'),validate=True))
			screenshots[str(png)] = sha(png)
		finally:
			process.terminate()
			try: process.wait(timeout=10)
			except subprocess.TimeoutExpired: process.kill(); process.wait()
	write(runtime/'result.json',dict(status='BOOK_BROWSER_EXECUTED_PENDING_VISUAL_INSPECTION',browser_version=version,browser_launcher_sha256=sha(browser),commands_sha256=sha(runtime/'commands.json'),keyboard_and_print=result,screenshots=screenshots,scope='Actual local Chromium, JavaScript enabled/disabled controls, native Tab/Enter focus, mobile overflow and print-media screenshot. Screenshots need visual inspection; host browser/fonts are observational dependencies, not pixel determinism.'))
	print('Browser, keyboard and print-media checks executed; inspect screenshots')


if __name__ == '__main__':
	main()
