# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Explicit-source client in all orders, including relocated installed reuse."""
from pathlib import Path
import hashlib
import itertools
import json
import os
import re
import resource
import shutil
import subprocess
import sys
sys.dont_write_bytecode = True
import tempfile
from pipeline import collect

ROOT=Path(__file__).resolve().parents[2]
SOURCES=['types.astra','values.astra','processing.astra','main.astra']
PROVIDERS=['args-posix.o','text-posix.o','diagnostics-hosted.o']
STAGES=['syntax','semantics','core','instances','cfg','ssa','nabi','cabi','llvm']
resource.setrlimit(resource.RLIMIT_CORE,(0,0))


class Client:
	def __init__(self, example, libraries, expected, expression, view=False, extra=None, collector=None):
		self.example, self.libraries = example, libraries
		self.expected, self.expression, self.view = expected, expression, view
		self.extra, self.collector, self.commands = extra, collector, []

	def run(self,args,cwd,**kwargs):
		kwargs.setdefault('timeout', 120)
		args=list(map(str,args));self.commands.append(dict(argv=args,cwd=str(cwd)))
		return subprocess.run(args,cwd=cwd,env=dict(os.environ,CCACHE_DISABLE='1'),**kwargs)


	def checked(self,args,cwd):
		p=self.run(args,cwd,capture_output=True);assert p.returncode==0 and not p.stderr,(args,p);return p.stdout


	def permutations(self,compiler,library,support,out):
		out.mkdir(parents=True,exist_ok=False)
		# The compiler and installed sources are used from outside their source tree.
		client=Path(tempfile.mkdtemp(prefix='astra-generic-client-', dir=out))
		for name in SOURCES:shutil.copyfile(ROOT/'examples'/self.example/name,client/name)
		for name in self.libraries:
			(client/name).parent.mkdir(exist_ok=True);shutil.copyfile(library/name,client/name)
		canonical={stage:self.checked([compiler,'--dump-'+stage,*SOURCES,*self.libraries],client) for stage in STAGES}
		for stage,data in canonical.items():(out/('canonical.'+stage)).write_bytes(data)
		links=[part for name in PROVIDERS for part in ['--link-object',support/name]]
		line=next(i for i,text in enumerate((client/'main.astra').read_text().splitlines(),1) if 'var failure' in text)
		expected=f'Astra assertion failed\n  file: "main.astra"\n  line: {line}\n  expression: "{self.expression}"\n  message: ""\n'.encode()
		if self.view:
			view_line=next(i for i,text in enumerate((client/'main.astra').read_text().splitlines(),1) if 'var view_failure' in text)
			view_expected=f'Astra assertion failed\n  file: "main.astra"\n  line: {view_line}\n  expression: "slice(fixed)"\n  message: ""\n'.encode()
		rows=[]
		for i,order in enumerate(itertools.permutations(SOURCES)):
			observed = collect(self.collector, [*order, *self.libraries], out / ('order-' + str(i)), client, self.checked)
			assert {stage: data.encode() for stage, data in observed.items()} == canonical, order
			exe=client/('consumer-'+str(i));self.checked([compiler,*order,*self.libraries,*links,'-o',exe],client)
			p=self.run([exe],client,capture_output=True);assert p.returncode==0 and p.stdout==self.expected and not p.stderr,p
			view_failure = None
			if self.view:
				view_failure=self.run([exe,'failure','view'],client,capture_output=True);assert view_failure.returncode==-6 and not view_failure.stdout and view_failure.stderr==view_expected,view_failure
			forced=self.run([exe,'failure'],client,capture_output=True);assert forced.returncode==-6 and not forced.stdout and forced.stderr==expected,forced
			with open('/dev/full','wb') as sink:
				failed=self.run([exe],client,stdout=sink,stderr=subprocess.PIPE);assert failed.returncode==2 and not failed.stderr,failed
			if self.view: (out/(f'consumer-{i}.view-stderr')).write_bytes(view_failure.stderr)
			(out/(f'consumer-{i}.stdout')).write_bytes(p.stdout);(out/(f'consumer-{i}.stderr')).write_bytes(forced.stderr)
			rows.append(dict(order=order,status=p.returncode,forced=forced.returncode,view_failure=view_failure.returncode if self.view else None,handled=failed.returncode,sha256=hashlib.sha256(exe.read_bytes()).hexdigest()))
		(out/'permutations.json').write_text(json.dumps(dict(client=str(client),rows=rows),indent='\t')+'\n')
		# Keep exact recoverable inputs, executables and per-file inventories in the
		# campaign output too; the temporary working directory is deliberately retained.
		shutil.copytree(client,out/'retained-client')
		return canonical,client


	def machine_client(self,build,client,library,out):
		out.mkdir();entry=out/'client-entry.ll';rows=[]
		self.checked([build/'tests/struct-elem-1/astra-struct-elements-llvm','--emit',entry,*SOURCES,*self.libraries],client)
		providers={}
		for cc in ['gcc','clang']:
			providers[cc]=[]
			for name in PROVIDERS:
				obj=out/(cc+'-'+name);source=library/'platform'/(Path(name).stem+'.c')
				self.checked([cc,'-std=c11','-O2','-Wall','-Wextra','-Werror','-fno-stack-protector',*(['-ffreestanding'] if name=='diagnostics-hosted.o' else []),'-c',source,'-o',obj],client)
				providers[cc].append(obj)
				(out/(obj.name+'.undefined')).write_bytes(self.checked(['nm','-u',obj],client));(out/(obj.name+'.size')).write_bytes(self.checked(['size','-A',obj],client))
		ir=entry.read_text()
		for mode in ['O0','O2','O2-fma','preserved-O2']:
			inp,opt,obj=out/(mode+'-input.ll'),out/(mode+'.ll'),out/(mode+'.o')
			inp.write_text(re.sub(r'^define internal fastcc ([^\n]+) \{$',r'define fastcc \1 noinline {',ir,flags=re.M) if mode=='preserved-O2' else ir)
			self.checked(['opt','-passes=verify' if mode=='O0' else '-passes=default<O2>','-S',inp.name,'-o',opt.name],out)
			self.checked(['opt','-passes=verify','-disable-output',opt.name],out)
			self.checked(['llc','-O0' if mode=='O0' else '-O2','-filetype=obj','-relocation-model=pic',*(['-mattr=+fma'] if mode=='O2-fma' else []),opt.name,'-o',obj.name],out)
			machine=self.checked(['objdump','-dr',obj],client)
			if mode=='preserved-O2':assert re.search(rb'R_X86_64_(?:PLT32|PC32)\s+astra\.fn\.',machine),machine
			for suffix,command in [('machine',['objdump','-dr']),('symbols',['readelf','-h','-Ws','-r']),('size',['size','-A']),('undefined',['nm','-u'])]:
				(out/(mode+'.'+suffix)).write_bytes(self.checked([*command,obj],client))
			for cc in providers:
				exe=out/(mode+'-'+cc);self.checked([cc,obj,*providers[cc],'-o',exe],client)
				p=self.run([exe],client,capture_output=True);assert p.returncode==0 and p.stdout==self.expected and not p.stderr,p
				forced=self.run([exe,'failure'],client,capture_output=True);assert forced.returncode==-6 and forced.stderr==(out.parent/'installed/consumer-0.stderr').read_bytes() and not forced.stdout,forced
				with open('/dev/full','wb') as sink:
					failed=self.run([exe],client,stdout=sink,stderr=subprocess.PIPE);assert failed.returncode==2 and not failed.stderr,failed
				(out/(exe.name+'.stdout')).write_bytes(p.stdout);(out/(exe.name+'.stderr')).write_bytes(forced.stderr)
				(out/(exe.name+'.dynamic')).write_bytes(self.checked(['readelf','-d',exe],client))
				rows.append(dict(mode=mode,compiler=cc,status=p.returncode,fatal=forced.returncode,handled=failed.returncode,sha256=hashlib.sha256(exe.read_bytes()).hexdigest()))
		(out/'results.json').write_text(json.dumps(rows,indent='\t')+'\n')
		return rows


	def qualify(self,build,out):
		out.mkdir(parents=True,exist_ok=False)
		try:
			options={item['name']:item['value'] for item in json.loads(self.checked(['meson','introspect',build,'--buildoptions'],ROOT))}
			stage=out/'stage';prefix=out/'relocated/prefix';self.checked(['meson','install','-C',build,'--no-rebuild','--destdir',stage],ROOT)
			prefix.parent.mkdir();shutil.copytree(stage/Path(options['prefix']).relative_to('/'),prefix)
			def relocated(option):
				path=Path(options[option]);return prefix/(path.relative_to(options['prefix']) if path.is_absolute() else path)
			compiler=relocated('bindir')/'astrac';library=relocated('datadir')/'astra';support=relocated('libdir')/'astra/x86_64-linux'
			assert compiler.read_bytes()==(build/'astrac').read_bytes()
			for name in self.libraries: assert (library/name).read_bytes()==(ROOT/'lib/astra'/name).read_bytes()
			for name in PROVIDERS:assert (support/name).read_bytes()==(build/'lib/astra'/name).read_bytes()
			before,original=self.permutations(build/'astrac',ROOT/'lib/astra',build/'lib/astra',out/'original')
			after,installed=self.permutations(compiler,library,support,out/'installed');assert before==after
			machines=self.machine_client(build,installed,library,out/'machine')
			extra = self.extra(self, compiler, installed, library, out) if self.extra is not None else {}
			(out/'results.json').write_text(json.dumps(dict(original=str(original),installed=str(installed),orders=24,machines=machines,installed_prefix=str(prefix),configured_prefix=options['prefix'],configured_datadir=options['datadir'],configured_libdir=options['libdir'],compiler_sha256=hashlib.sha256(compiler.read_bytes()).hexdigest(),canonical={stage:hashlib.sha256(data).hexdigest() for stage,data in before.items()},**extra),indent='\t')+'\n')
		finally:(out/'commands.json').write_text(json.dumps(self.commands,indent='\t')+'\n')
		print('24 original and 24 relocated installed orders outside compiler source, 8 machine variants, exact DIAG and handled output failure')


def main(spec):
	sys.path.insert(0, str(ROOT / 'tools/qualification'))
	from output_paths import fresh_output
	build = Path(sys.argv[1]).resolve()
	collector = Path(sys.argv[3]).resolve(strict=True) if len(sys.argv) == 4 else build / 'tests/support/astra-stage-collector'
	Client(**spec, collector=collector).qualify(build, fresh_output(sys.argv[2]))
