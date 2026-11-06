#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Compare original method bytes/ASTs and preserve complete throwing caller identities."""
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import time
from corpus import method
from state import ROOT, RUNTIME, BUILD, PRIOR, C0, COHORTS, read, sha, digest


def find(tree, tag, name):
	if not isinstance(tree,list): return []
	matched = tree[:1] == [tag] and (['name',name] in tree or tag == 'class' and tree[1:2] == [name])
	return ([tree] if matched else [])+[found for child in tree for found in find(child,tag,name)]


def main():
	leaf = RUNTIME/'source-witness-v2'; leaf.mkdir(exist_ok=False); commands = []; rows = {}
	spec = importlib.util.spec_from_file_location('syntax',ROOT/'tests/selfhost-classstorage/abi-probe.py'); probe = importlib.util.module_from_spec(spec); spec.loader.exec_module(probe)
	def syntax(path,name):
		argv = [C0,'--dump-syntax',path]; start = time.monotonic(); r = subprocess.run(['/usr/bin/time','-v','-o',leaf/(name+'.time'),*map(str,argv)],cwd=BUILD,capture_output=True,timeout=60)
		(leaf/(name+'.stdout')).write_bytes(r.stdout); (leaf/(name+'.stderr')).write_bytes(r.stderr); commands.append(dict(name=name,argv=list(map(str,argv)),exit=r.returncode,start=start,end=time.monotonic())); (leaf/'commands.json').write_text(json.dumps(commands,indent=2)+'\n'); assert r.returncode == 0
		return probe.syntax(r.stdout.decode())
	selection = read(RUNTIME/'corpus-v6/selection.json'); view = Path(selection[0]['sources'][0]['path']); view_ast = syntax(view,'native-view')
	previous = read(RUNTIME.parent/'membercall22/facts-v2/result.json')['cohorts']
	for name in COHORTS:
		old = previous[name]; caller = old['enclosing_function']; path = Path(old['first_stop']['path']); raw = path.read_bytes()[caller['start']:caller['end']]
		assert b'throws Error' in raw.split(b'{',1)[0] and hashlib.sha256(raw).hexdigest() == old['enclosing_bytes_sha256']
		ast = syntax(path,name+'-caller'); selected = find(ast,'function',caller['name']); assert len(selected) == 1 and digest(selected[0]) == old['enclosing_AST_sha256']
		model = Path(old['FlowGraph_source']); methods = {}
		for method_name,spelling in [('slot_for','int slot_for('),('add','int add('),('room','bool room(')]:
			body = method(model,spelling); assert body in view.read_text()
			selected = find(view_ast,'method',method_name); assert len(selected) == 1
			if method_name in old['method_ASTs']: assert selected[0] == old['method_ASTs'][method_name]
			methods[method_name] = dict(bytes=len(body.encode()),sha256=hashlib.sha256(body.encode()).hexdigest(),C0_AST_sha256=digest(selected[0]))
		rows[name] = dict(call_node=old['call_node']['node'],first_stop=old['first_stop'],call_bytes_hex=old['call_bytes_hex'],caller=caller,caller_bytes_sha256=old['enclosing_bytes_sha256'],caller_AST_sha256=old['enclosing_AST_sha256'],original_caller_native_status='DEFERRED: throws Error; no recoverable effect ABI authorized',methods=methods)
	assert 'graph.slot_for(checked_target(checked, direct, checked.bindings.program.arena.get_token_identifier(direct)))' in view.read_text()
	assert 'graph.add(bad)' in Path(selection[2]['sources'][0]['path']).read_text()
	helper = (RUNTIME.parent/'membercall22/reference-v4/original-checked-target.astra').read_text(); assert helper in view.read_text()
	(leaf/'result.json').write_text(json.dumps(dict(status='PASS',cohorts=rows,view_disclosure=read(RUNTIME/'corpus-v6/views.json'),helper_sha256=hashlib.sha256(helper.encode()).hexdigest(),commands=commands),indent=2)+'\n'); print('Four original throwing caller ASTs/bytes preserved; three unchanged method bodies and original checked_target retained')


if __name__ == '__main__':
	main()
