#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Lossless content-addressed evidence transport for the installed pm-next publisher."""
import argparse
import base64
import io
import json
import os
from pathlib import Path
import shutil
import tarfile
import sys

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT.parent/'codex/work/astra'
sys.path.insert(0,str(ROOT/'tests/selfhost-ownership-syntax-27b'))
from support import output_path, sha, write


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--qualification',type=Path,required=True)
	p.add_argument('--site',type=Path,required=True)
	p.add_argument('--runtime',type=Path,required=True)
	a = p.parse_args()
	runtime = output_path(a.runtime,WORK/'runtime'); runtime.mkdir(parents=True,exist_ok=False)
	qualification = json.loads(a.qualification.read_text()); assert qualification['status']=='PARTIAL'
	files = {}; blobs = {}; excluded = []; links = []
	def collect(root,prefix):
		for path in sorted(root.rglob('*')):
			rel = path.relative_to(root)
			if any(part.endswith('-profile') for part in rel.parts):
				if path.is_dir() and rel.parts[-1].endswith('-profile'): excluded.append(prefix+'/'+str(rel))
				continue
			if path.is_symlink():
				# Negative path tests intentionally leave symlinks. Preserve their
				# observed target as inert metadata, never follow or extract a link.
				logical = prefix+'/'+str(rel)
				observation = dict(kind='INERT_SYMLINK_OBSERVATION',logical_path=logical,target=os.readlink(path))
				data = (json.dumps(observation,sort_keys=True)+'\n').encode()
				digest = __import__('hashlib').sha256(data).hexdigest()
				files[logical+'.symlink.json'] = dict(bytes=len(data),sha256=digest,blob='blobs/'+digest,kind='INERT_SYMLINK_OBSERVATION')
				blobs[digest] = data; links.append(observation)
				continue
			if not path.is_file(): continue
			data = path.read_bytes(); digest = sha(path)
			files[prefix+'/'+str(rel)] = dict(bytes=len(data),sha256=digest,blob='blobs/'+digest)
			blobs[digest] = data
	for root in sorted((WORK/'runtime').glob('books28a2-*')):
		if root==runtime or root.name=='books28a2-tools' or root.name.startswith('books28a2-report-'): continue
		if root.is_dir(): collect(root,'runtime/'+root.name)
		elif root.is_file():
			digest = sha(root); data = root.read_bytes(); files['runtime/'+root.name]=dict(bytes=len(data),sha256=digest,blob='blobs/'+digest); blobs[digest]=data
	collect(WORK/'runtime/api-docs28a1-after-publication2','genuine-prior-G7')
	collect(a.site,'site')
	index = dict(format='astra-book-evidence/1',files=files,symlink_observations=links,excluded_browser_state=sorted(set(excluded)),scope='All recorded task execution streams, source witnesses, failed attempts, inspected screenshots and final static site. Prior G7 is separate actual after-publication evidence. Intentional negative-test links are inert metadata, never followed. Browser caches/profiles and generated native binaries are excluded; product identities and build recipes remain explicit.')
	archive = runtime/'transport.tar.xz'
	with tarfile.open(archive,'w:xz',preset=6,format=tarfile.PAX_FORMAT) as tar:
		def add(name,data):
			info = tarfile.TarInfo(name); info.size=len(data); info.mode=0o444; info.mtime=0
			tar.addfile(info,io.BytesIO(data))
		add('INDEX.json',(json.dumps(index,sort_keys=True,indent=2)+'\n').encode())
		for digest,data in sorted(blobs.items()): add('blobs/'+digest,data)
		# Independently reopen and verify every logical mapping and each blob byte.
	with tarfile.open(archive,'r:xz') as tar:
		actual = json.load(tar.extractfile('INDEX.json')); assert actual==index
		for digest,data in sorted(blobs.items()): assert tar.extractfile('blobs/'+digest).read()==data
		assert set(tar.getnames())=={'INDEX.json'}|{'blobs/'+digest for digest in blobs}
	parts = []
	data = archive.read_bytes()
	for number,offset in enumerate(range(0,len(data),1200000)):
		part = runtime/('transport-'+str(number).zfill(2)+'.json')
		raw = data[offset:offset+1200000]
		write(part,dict(format='astra-byte-transport/1',ordinal=number,base64=base64.b64encode(raw).decode()))
		parts.append(dict(path=part.name,bytes=part.stat().st_size,sha256=sha(part),decoded_bytes=len(raw)))
	write(runtime/'TRANSPORT.json',dict(format='astra-book-evidence-transport/1',archive=dict(bytes=len(data),sha256=sha(archive)),logical_files=len(files),symlink_observations=len(links),blobs=len(blobs),parts=parts,excluded_browser_state=sorted(set(excluded))))
	shutil.copyfile(a.qualification,runtime/'QUALIFICATION.json')
	shutil.copyfile(a.qualification.with_name('execution-costs.json'),runtime/'EXECUTION-COSTS.json')
	shutil.copyfile(ROOT/'docs/books/STATUS.md',runtime/'ENGINEERING.md')
	for name in ('index.html','reference/print.html','guide/print.html'):
		shutil.copyfile(a.site/name,runtime/('site-'+name.replace('/','-')))
	visual = json.loads((WORK/'runtime/books28a2-visual.json').read_text())
	for path in visual['screenshots']: shutil.copyfile(path,runtime/Path(path).name)
	attachments = []
	for path in sorted(runtime.iterdir()):
		if path.suffix not in ('.json','.md','.html','.png'): continue
		assert path.stat().st_size<=2*1024*1024,path
		attachments.append(dict(path=path.name,bytes=path.stat().st_size,sha256=sha(path)))
	write(runtime/'evidence-index.json',dict(format='pm-next-evidence/1',files=attachments))
	print(json.dumps(dict(archive_bytes=len(data),archive_sha256=sha(archive),logical_files=len(files),blobs=len(blobs),parts=len(parts),attachments=len(attachments))))


if __name__ == '__main__':
	main()
