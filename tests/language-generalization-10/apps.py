# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Public integrated applications; each receipt names one actual qualified app."""
from pathlib import Path
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
APPS = ROOT/'examples/language-generalization-10'


def main(compiler_path, output_path, application):
	compiler, output = Path(compiler_path).resolve(), Path(output_path).resolve()
	assert not output.is_relative_to(ROOT)
	output.mkdir(parents=True, exist_ok=True)
	out = Path(tempfile.mkdtemp(prefix=application+'-', dir=output))
	sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
	text_library = [ROOT/'lib/astra'/name for name in ['base/errors.astra', 'collections/bag.astra',
		'collections/vector.astra', 'text/utf8-message.astra', 'text/utf8-byte-builder.astra',
		'hosted/text.astra', 'hosted/text-ops.astra', 'text/unicode-scalars.astra']]
	providers = [APPS/'resources.c', *[ROOT/'lib/runtime/platform'/name for name in ['args-posix.c', 'text-posix.c', 'text-ops-posix.c']]]
	api = APPS/'resources.vapi'
	application_sources = {'a73': 'a73-document.astra', 'a74': 'a74-router.astra', 'a75': 'a75-archive.astra', 'a76': 'a76-pipeline.astra', 'a77': 'a77-analyzer.astra', 'a78': 'a78-cache.astra', 'a79': 'a79-jobs.astra', 'a80': 'a80-null-workflow.astra', 'a81': 'a81-inspector.astra', 'a83': 'a83-diagnostics.astra', 'a84': 'a84-stream.astra'}
	assert application in application_sources, 'application has not been implemented in this recipe'
	if application == 'a79':
		text_library.append(ROOT/'lib/astra/async/virtual.astra')
	if application == 'a83':
		text_library += [ROOT/'lib/astra/hosted/files.astra', ROOT/'lib/astra/text/scalar-format.astra']
		providers.append(ROOT/'lib/runtime/platform/files-posix.c')
	if application == 'a84':
		text_library += [ROOT/'lib/astra/memory/byte-arena.astra', ROOT/'lib/astra/text/scalar-format.astra']
	source = APPS/application_sources[application]
	if application == 'a81':
		text_library.append(APPS/'a81-model.astra')
	inputs = ['--vapi', api, *text_library, source]
	provider_headers = [provider.with_suffix('.h') for provider in providers if provider.with_suffix('.h').is_file()]
	receipt = dict(application=application, status='IN_PROGRESS', compiler=str(compiler), compiler_sha256=sha(compiler),
		sources={str(path.relative_to(ROOT)): sha(path) for path in [source, api, *text_library, *providers, *provider_headers, Path(__file__).resolve()]}, checks=[], products={})

	def run(argv, expected=0, diagnostic=None, memory=False, stdout=b''):
		argv = list(map(str, argv))
		result = subprocess.run(argv, cwd=ROOT, capture_output=True, timeout=90,
			env=dict(os.environ, CCACHE_DISABLE='1', PYTHONDONTWRITEBYTECODE='1'))
		passed = result.returncode == expected and (stdout is None or result.stdout == stdout)
		if diagnostic:
			passed &= diagnostic.encode() in result.stderr
			passed &= all(word not in result.stderr for word in [b'internal ', b'assertion', b'CRITICAL'])
		elif memory:
			passed &= all(word in result.stderr for word in [b'ERROR SUMMARY: 0 errors', b'in use at exit: 0 bytes in 0 blocks', b'(suppressed: 0 from 0)'])
		else:
			passed &= not result.stderr
		receipt['checks'].append(dict(command=argv, expected_exit=expected, actual_exit=result.returncode,
			stdout=result.stdout.decode(errors='replace'), stderr=result.stderr.decode(errors='replace'), passed=bool(passed),
			astra_inputs={arg: sha(Path(arg)) for arg in argv if arg.endswith('.astra') and Path(arg).is_file()}))
		(out/'checks.json').write_text(json.dumps(receipt, indent=2)+'\n')
		assert passed, receipt['checks'][-1]
		return result.stdout

	if application == 'a81':
		metadata = out/'inspector-metadata.astra'
		run([compiler, '--emit-native-descriptors', '--descriptor-module', 'Inspector',
			'--describe', 'SensorReading', '--describe', 'SensorPoint', '--describe', 'SensorScale',
			'--vapi', api, *text_library, '-o', metadata])
		assert 'calibration' not in metadata.read_text(), 'private state entered descriptors'
		receipt['products'][str(metadata)] = sha(metadata)
		text_library.append(metadata)
		inputs = ['--vapi', api, *text_library, source]
		receipt['sources'][str((APPS/'a81-minimal.astra').relative_to(ROOT))] = sha(APPS/'a81-minimal.astra')
	run([compiler, '--format', '--check', source])
	for stage in ['--check', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-llvm']:
		run([compiler, stage, *inputs], stdout=None)
	objects = []
	for provider in providers:
		obj = out/(provider.stem+'.o'); objects.append(obj)
		run(['cc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-c', provider, '-o', obj])
	links = [item for obj in objects for item in ['--link-object', obj]]
	if application == 'a79':
		provider = compiler.parent/'lib/astra/async-virtual.o'
		links += ['--link-object', provider]
		receipt['async_provider_sha256'] = sha(provider)

	def document_oracle(left, label, right, failure):
		# Derive rollback from the construction sequence, independently of IR order.
		rows, owners = [], []
		steps = [(0, '+'+str(left), '-'+str(left)), (1, None, 'E'+str(1000+left)),
			(4, '+'+str(left+100), '-'+str(left+100)), (6, '+'+str(right), '-'+str(right)),
			(7, None, 'E'+str(1000+right)), (10, '+'+str(right+100), '-'+str(right+100))]
		for stage, created, retired in steps:
			if failure >= 0 and stage >= failure:
				break
			if created:
				rows.append(created)
			owners.append(retired)
		if failure >= 0:
			rows += list(reversed(owners))+['document stage', 'N0']
			return ('\n'.join(rows)+'\n').encode(), 2
		rows += ['N'+str(left*3+right*5)]
		# The selected leaf moves to the result; remaining document owners retire.
		rows += ['-'+str(right+100), 'E'+str(1000+right), '-'+str(right), '-'+str(left+100)]
		rows += ['N'+str(left*22+len(label.encode())+4), 'E'+str(1000+left), '-'+str(left), 'N0']
		return ('\n'.join(rows)+'\n').encode(), 0
	def archive_oracle(text):
		rows, values = [], []
		parts = text.split(',')
		if not 3 <= len(parts) <= 16:
			return b'archive count\nN0\n', 2
		for part in parts:
			value = int(part)
			error = 'archive range' if not 1 <= value <= 40 else 'duplicate archive key' if value in values else None
			if error:
				rows += ['-'+str(code+100) for code in reversed(values)]
				for code in reversed(values):
					rows += ['E'+str(2000+code), '-'+str(code)]
				return ('\n'.join(rows+[error, 'N0'])+'\n').encode(), 2
			values.append(value); rows += ['+'+str(value), '+'+str(value+100)]
		rows += ['N'+str(sum((index+1)*code+index for index, code in enumerate(values))),
			'N'+str(sum((index+1)*code for index, code in enumerate(values))), 'N'+str(values[1]*3)]
		replacement = values[0]+80
		rows += ['+'+str(replacement), 'E'+str(2000+values[0]), '-'+str(values[0]), '+'+str(replacement+100), '-'+str(values[0]+100)]
		remaining = [replacement, *values[2:]]
		ordinals = [len(values), *range(2, len(values))]
		rows += ['N'+str(sum((index+1)*code+ordinal for index, (code, ordinal) in enumerate(zip(remaining, ordinals)))),
			'N'+str(sum((index+1)*code for index, code in enumerate(remaining)))]
		rows += ['-'+str(code+100) for code in remaining]
		packet_total = sum(code*3+1+(len('replacement') if index == 0 else len(str(code))) for index, code in enumerate(remaining))
		rows += ['N'+str(packet_total), 'N'+str(len(remaining)*2), '-'+str(values[1]+100), 'E'+str(2000+values[1]), '-'+str(values[1])]
		for code in reversed(remaining):
			rows += ['E'+str(2000+code), '-'+str(code)]
		return ('\n'.join(rows+['N0'])+'\n').encode(), 0
	def router_oracle(commands):
		rows, pending, total = [], ('empty', None), 0
		def retire(value):
			if value[0] in ['L', 'P']:
				rows.append('-'+str(value[1]))
		def dispatch(value):
			retire(value)
			if value[0] == 'L':
				return value[1]*3
			if value[0] == 'P':
				return value[1]*5+3+len(('P:'+str(value[1])).encode())
			return len(value[1].encode())*3 if value[0] == 'T' else 0
		for command in commands.split('|'):
			if command == 'emit':
				value = dispatch(pending); total += value
				rows.append('N'+str(value)); pending = ('empty', None)
				continue
			if command == 'fail':
				rows += ['router checked failure', 'E700']; continue
			if command == 'empty':
				next_value = ('empty', None)
			else:
				kind, payload = command.split(':', 1)
				next_value = (kind, payload if kind == 'T' else int(payload))
				if kind in ['L', 'P']:
					if not 1 <= next_value[1] <= 80:
						rows += ['router range', 'E700']; continue
					rows.append('+'+str(next_value[1]))
			retire(pending); pending = next_value
		final = dispatch(pending)
		rows += ['N'+str(final), 'N'+str(total+final), 'N0']
		return ('\n'.join(rows)+'\n').encode(), 0
	def pipeline_oracle(seed, count, failure):
		if not (1 <= seed <= 40 and 0 <= count <= 10 and -1 <= failure <= 10):
			return b'pipeline range\nN0\n', 2
		rows, selected = ['+'+str(seed)], []
		position, state = -1, seed
		def advance():
			nonlocal position, state
			position += 1
			if position >= count:
				return False
			if position == failure:
				raise RuntimeError('generator step')
			state = (state*7+3) % 97
			return True
		try:
			while advance():
				if state % 3 == 0:
					continue
				selected.append((position, state+seed))
				if len(selected) == 3:
					break
			checksum = sum((index+1)*value*weight for index, value in selected for weight in [2, 3])
			rows += [f'N{len(selected)}', f'N{checksum}', 'N30', f'N{position}']
			tail = 0
			while advance():
				if position % 2:
					tail += state
			rows += [f'N{tail}', f'E{3000+seed}', f'-{seed}', 'N0']
			return ('\n'.join(rows)+'\n').encode(), 0
		except RuntimeError as error:
			return ('\n'.join(rows+[f'E{3000+seed}', f'-{seed}', str(error), 'N0'])+'\n').encode(), 2
	def analyzer_oracle(text, start, count, mode):
		rows = [b'+77']
		encoded = text.encode()
		if mode == 'bad':
			rows += [encoded, f'N{len(encoded)}'.encode(), f'N{len(encoded)+2}'.encode(), b'-77', b'invalid UTF-8', b'N0']
			return b'\n'.join(rows)+b'\n', 2
		value = text+('\0' if mode == 'nul' else '')
		rows += [f'N{len(value.encode())}'.encode(), f'N{len(value)}'.encode(), f'N{encoded.find(b"|")}'.encode()]
		if start < 0 or count < 0 or start+count > len(value):
			return b'\n'.join(rows+[b'-77', b'text scalar range', b'N0'])+b'\n', 2
		rows += [value[start:start+count].encode()]
		total, invalid = 0, 0
		for token in value.split('|'):
			parsed = int(token) if re.fullmatch(r'-?[0-9]+', token) else None
			if parsed is not None and -2147483648 <= parsed <= 2147483647:
				rows += [f'N{parsed}'.encode()]; total += parsed
			else:
				rows += [token.encode()]; invalid += 1
		rows += [f'N{total}'.encode(), f'N{invalid}'.encode(), f'N{sum((index+1)*ord(char) for index,char in enumerate(value))}'.encode(), b'-77', b'N0']
		return b'\n'.join(rows)+b'\n', 0
	def cache_oracle(seed, count, retry):
		if not (1 <= seed <= 30 and 0 <= count <= 6):
			return b'cache range\nN0\n', 2
		rows = []
		allocate = lambda s,c: [f'+{s+i}' for i in range(c)]
		retire = lambda s,c: [f'-{s+i}' for i in reversed(range(c))]
		metric = lambda s,c: c+sum((i+1)*((s+i)**2+s+i+c) for i in range(c))
		rows += allocate(seed, count)
		if retry:
			rows += retire(seed, count)+['cache retry', 'N-1']
		else:
			rows += [f'N{metric(seed,count)}']
		rows += allocate(seed+60, count+1)+[f'N{metric(seed+60,count+1)}']
		if retry:
			rows += allocate(seed, count)
		rows += [f'N{metric(seed,count)}', f'N{metric(seed+60,count+1)}', f'N{2 if retry else 1}', 'N1', 'N1', 'N0', f'N{metric(seed,count)}']
		rows += [f'E{4000+seed}']+retire(seed,count)+[f'E{4060+seed}']+retire(seed+60,count+1)+['N0']
		return ('\n'.join(rows)+'\n').encode(), 0
	def jobs_oracle(seed, count, delay):
		if not (1 <= seed <= 20 and 1 <= count <= 4 and 2 <= delay <= 4):
			return b'job range\nN0\n', 2
		rows = []
		for job, (key, size) in enumerate([(seed,count), (seed+30,count+1), (seed+60,count)]):
			allocate = [f'+{key+i}' for i in range(size)]
			retire = [f'-{key+i}' for i in reversed(range(size))]
			rows += allocate+retire+allocate+[f'E{5000+key}']
			if job != 2:
				rows += [f'E{5100+key}']
			rows += [f'E{5200+key}']+retire
			if job == 0:
				rows += [f'N{sum((i+1)*(4*key+2*i) for i in range(size))}']
			if job == 1:
				rows += ['job failure', 'E5990']
		return ('\n'.join(rows+['E5991','N0'])+'\n').encode(), 0
	def workflow_oracle(seed, count, present, twice):
		if not (1 <= seed <= 40 and 0 <= count <= 6):
			return b'workflow range\nN0\n', 2
		code = (lambda value: value*2) if twice else (lambda value: value+1)
		metric = count+code(0)+seed+sum((code(seed+i)+seed)*(i+1) for i in range(count))
		rows = [f'N{metric if present else -1}', 'N-1', f'N{count if present else -1}']
		if present:
			rows += ['N-2']
		rows += [f'+{seed}', f'N{seed*7}', f'N{seed*7}', f'E{6000+seed}', f'-{seed}', 'N1', 'N0']
		return ('\n'.join(rows)+'\n').encode(), 0
	def inspector_oracle(name, member, raw, bias):
		schemas = {'SensorReading': ('class',['raw','adjusted','shifted']), 'SensorPoint': ('record',['x','y']), 'SensorScale': ('interface',['invoke'])}
		if name not in schemas:
			return b'+81\n-81\nunknown native type name\nN0\n', 2
		kind, members = schemas[name]
		if member not in members:
			return b'+81\n-81\nunknown selected member\nN0\n', 2
		identifier = 2166136261
		for byte in f'Inspector::{kind}::{name}'.encode():
			identifier = ((identifier ^ byte)*16777619)&0xffffffff
		identifier = (identifier&0x7fffffff) or 1
		value = {'raw':raw, 'adjusted':2*raw-bias, 'shifted':raw+2*bias+2, 'x':raw+1, 'y':raw+bias, 'invoke':3*raw+bias}[member]
		rows = ['+81',name,kind,member,'int(int)' if member in ['shifted','invoke'] else 'int',
			f'N{identifier}',f'N{members.index(member)}',f'N{len(members)}',f'N{value}',f'N{len(name.encode())}','-81','N0']
		return ('\n'.join(rows)+'\n').encode(), 0
	def diagnostics_oracle(data):
		try:
			text = data.decode('utf-8')
		except UnicodeDecodeError:
			return b'+83\n-83\ninvalid UTF-8\nN0\n', 2
		rows = []
		for line, value in enumerate(text.split('\n'),1):
			if not value:
				continue
			if len(value) < 2 or value[:2] not in ['E:','W:','I:']:
				return b'+83\n-83\ndiagnostic prefix\nN0\n', 2
			severity = {'E':3,'W':2,'I':1}[value[0]]
			rows.append((line,severity,value[2:]))
		score = sum(line*severity+len(body) for line,severity,body in rows)
		report = [f'diagnostics={len(rows)} score={score}']
		report += [f'{line}:{severity} bytes={len(body.encode())} scalars={len(body)} {body}' for line,severity,body in rows]
		report += [f'bytes={sum(len(body.encode()) for _,_,body in rows)} scalars={sum(len(body) for _,_,body in rows)}']
		return b'+83\n'+('\n'.join(report)+'\n').encode()+b'-83\nN0\n', 0
	if application == 'a83':
		file_cases = []
		for index,data in enumerate(['E:bad λ\nW:near🙂\n\nI:ok\n'.encode(), b'I:a\0b\nE:\xc3\xa9\n', b'', b'\n\n',
			b'E:kept\nQ:bad\n', b'W:kept\nI:\xf0\x9f', b'I:\xc0\xaf']):
			path=out/f'diagnostics-{index}.txt';path.write_bytes(data)
			file_cases.append(([path],*diagnostics_oracle(data)))
			receipt.setdefault('file_inputs',{})[str(path)] = dict(sha256=sha(path),hex=data.hex())
		file_cases.append(([out/'missing.txt'],b'+83\n-83\nfile I/O\nN0\n',2))
	def stream_oracle(seed,csv,capacity,mode):
		if not (1 <= seed <= 40 and 0 <= capacity <= 80 and mode in ['plain','probe']):
			return b'stream range\nN0\n',2
		fields=csv.split(',')
		if not 1 <= len(fields) <= 8:
			return b'stream count\nN0\n',2
		rows=[f'+{seed}']; state=seed; samples=[]; checksum=0
		def failure(message):
			return ('\n'.join(rows+[f'-{seed}',message,'N0'])+'\n').encode(),2
		for index,field in enumerate(fields):
			if not re.fullmatch(r'-?[0-9]+',field):
				return failure('invalid signed decimal')
			value=int(field)
			if not -100 <= value <= 100:
				return failure('stream sample range')
			if 8*(index+1)>capacity:
				return failure('arena capacity exhausted')
			state=(state*17+abs(value)+index)%65521+value+100
			clipped=min(4294967295,4294967280+abs(value))
			if mode=='probe' and index==0:
				rows+=['E8401']
			samples.append((state,clipped))
			encoded=state.to_bytes(4,'little')+clipped.to_bytes(4,'little')
			checksum+=sum((index+1)*(lane+1)*byte for lane,byte in enumerate(encoded))
		rows += [f'N{checksum}',f'N{len(fields)*8}','N9']
		rows += [f'{state}:{clipped}' for state,clipped in samples]+['','N0']
		if mode=='probe':
			rows+=['E8402']
		return ('\n'.join(rows+[f'-{seed}','N0'])+'\n').encode(),0

	for level in ['-O0', '-O1', '-O2']:
		executable = out/(application+level)
		run([compiler, level, *inputs, *links, '-o', executable]); receipt['products'][str(executable)] = sha(executable)
		if application == 'a73':
			cases = [(3, 'λ', 41, 'right', failure) for failure in range(-1, 14)]
			cases += [(7, 'root🙂', 53, '葉', -1)]
			cases = [([f'{left}/{label}/{right}/{other_label}', failure], *document_oracle(left, label, right, failure)) for left, label, right, other_label, failure in cases]
		elif application == 'a74':
			cases = [([commands], *router_oracle(commands)) for commands in [
				'L:3|T:été|P:5|emit|fail|L:7|emit', 'T:λ🙂|emit|P:9|fail|emit|L:4|empty',
				'emit|empty|emit', 'P:6|L:8|emit', 'L:4|fail|emit', 'L:2|P:0|emit',
				'L:3|L:3|emit|P:4|P:4|emit|L:5|P:5|emit']]
		elif application == 'a75':
			cases = [([text], *archive_oracle(text)) for text in ['2,4,6,8,10', '3,7,11', '31,11,40,20', '1,2,1', '1,2,41', '1,2']]
		elif application == 'a76':
			cases = [([seed, count, failure], *pipeline_oracle(seed, count, failure)) for seed, count, failure in [
				(1, 10, -1), (7, 8, -1), (3, 0, -1), (4, 6, 0), (5, 10, 8), (9, 10, 3), (1, 11, -1)]]
		elif application == 'a77':
			cases = [([text, start, count, mode], *analyzer_oracle(text, start, count, mode)) for text, start, count, mode in [
				('12|λ🙂|-7|004|x', 3, 2, 'plain'), ('é|23|42|', 0, 2, 'plain'), ('', 0, 0, 'plain'),
				('3|4', 1, 3, 'nul'), ('a|2147483648|-2147483648|2147483647', 0, 1, 'plain'),
				('split🙂', 0, 1, 'bad'), ('λ🙂|7', 4, 1, 'plain'), ('1|2', -1, 2, 'plain')]]
		elif application == 'a78':
			cases = [([seed, count, int(retry)], *cache_oracle(seed, count, retry)) for seed, count, retry in [
				(2,3,True), (7,2,False), (4,0,True), (3,6,False), (0,2,False)]]
		elif application == 'a79':
			cases = [([seed,count,delay], *jobs_oracle(seed,count,delay)) for seed,count,delay in [(2,2,2),(7,4,3),(11,1,4),(3,0,2)]]
		elif application == 'a80':
			cases = [([seed,count,int(present),int(twice)], *workflow_oracle(seed,count,present,twice)) for seed,count,present,twice in [
				(3,4,True,False),(7,2,True,True),(9,3,False,False),(2,0,True,True),(0,2,True,False)]]
		elif application == 'a81':
			cases = [([name,member,raw,bias], *inspector_oracle(name,member,raw,bias)) for name,member,raw,bias in [
				('SensorReading','raw',17,4), ('SensorReading','adjusted',-5,7), ('SensorReading','shifted',12,-2),
				('SensorPoint','y',31,9), ('SensorScale','invoke',11,3), ('unknown','raw',1,2), ('SensorReading','calibration',1,2)]]
		elif application == 'a83':
			cases = file_cases
		else:
			cases = [([seed,csv,capacity,mode],*stream_oracle(seed,csv,capacity,mode)) for seed,csv,capacity,mode in [
				(3,'1,-7,20,100',32,'plain'),(11,'-100,0,9,16,37',40,'probe'),(7,'3',8,'probe'),
				(2,'1,2,3',16,'plain'),(4,'8,101',16,'probe'),(5,'1,bad',16,'plain'),(0,'1',8,'plain')]]
		for arguments, expected, status in cases:
			run([executable, *arguments], expected=status, stdout=expected)
			run(['valgrind', '--default-suppressions=no', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', '--error-exitcode=99', executable, *arguments], expected=status, stdout=expected, memory=True)
		if application == 'a73':
			run([executable, '3/label/41', '-1'], expected=2, stdout=b'document needs id/name/id/name\nN0\n')
		if application == 'a81':
			minimal = out/('minimal'+level)
			run([compiler, level, '--vapi', api, *[item for item in text_library if item != metadata], APPS/'a81-minimal.astra', *links, '-o', minimal])
			receipt['products'][str(minimal)] = sha(minimal)
			run([minimal, '17', '4'], stdout=b'N30\n')
			run(['valgrind', '--default-suppressions=no', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', '--error-exitcode=99', minimal, '17', '4'], memory=True, stdout=b'N30\n')
			strings = run(['strings', minimal], stdout=None)
			assert all(name not in strings for name in [b'NativeMetadata_', b'SensorReading', b'SensorPoint', b'SensorScale', b'unknown native type'])
			dependencies = run(['readelf', '-d', minimal], stdout=None)
			assert all(name not in dependencies.lower() for name in [b'glib',b'gobject',b'uring',b'pcre',b'regex'])
	controls = [(name, 'number(document.version);', replacement, diagnostic) for name, replacement, diagnostic in [
		('owning-tree-copy', 'var alias = document;', 'copyable field graph'),
		('owned-field-alias', 'var alias = document.selected.leaf.lease;', 'owning record Resource field'),
	]] if application == 'a73' else [
		('enum-discriminator', 'var pending = RoutedEvent.Empty();', 'RoutedEvent forged = 2; var pending = RoutedEvent.Empty();', 'enum value requires explicit construction'),
		('enum-owner-copy', 'pending = move next;', 'pending = next;', 'move'),
	] if application == 'a74' else [
		('aggregate-copy', 'packets.append(move packet)', 'packets.append(packet)', 'move'),
		('iteration-relocation', 'total = total + archive_asset_code(value) * weight;', 'bool changed = values.reserve(64); total = total + archive_asset_code(value) * weight;', 'borrow overlaps'),
	] if application == 'a75' else [
		('iterator-owner-death', 'if (pulse.value % 3 == 0)', 'release generator; if (pulse.value % 3 == 0)', 'active receiver or foreach collection'),
		('iterator-view-escape', 'int main(string[] args)', 'int[] escape(PulseGenerator value){return value.state;} int main(string[] args)', 'result lifetime'),
	] if application == 'a76' else [
		('analysis-copy', 'var input = move report.input;', 'var duplicate = report; var input = move report.input;', 'copyable field graph'),
		('builder-backing', 'var original = builder.snapshot();', 'number(len(builder.backing)); var original = builder.snapshot();', 'private'),
	] if application == 'a77' else [
		('cache-steal', 'return cache_size(this.entries) + this.checksum;', 'var stolen = move this.entries; return cache_size(stolen);', 'move'),
		('cache-copy', 'return cache_size(this.entries) + this.checksum;', 'var alias = this.entries; return cache_size(alias);', 'borrowed'),
	] if application == 'a78' else [
		('suspended-loan', 'int main(string[] args)', 'async int retain(Vector<WorkChunk> chunks) throws Error { await delay_ticks(1); return chunks.count(); } int main(string[] args)', 'require synchronous native'),
	] if application == 'a79' else [
		('mutated-projection', 'store.clear();', 'store.clear(); number(workflow_count(store.view));', 'current non-null proof'),
		('null-contract', 'number(inspect_rows(store.view, action, code));', 'number(workflow_count(null));', 'current non-null proof'),
	] if application == 'a80' else [
		('descriptor-receiver', 'read_SensorReading_int(sensor, selected)', 'read_SensorPoint_int(sensor, selected)', 'type'),
		('private-inspection', 'number(value);', 'number(sensor.calibration);', 'private'),
	] if application == 'a81' else [
		('diagnostic-copy', 'archive.append(move stored)', 'archive.append(stored)', 'move'),
		('file-storage-escape', 'var text = bytes.decode();', 'var escaped = bytes.storage; var text = bytes.decode();', 'private'),
	] if application == 'a83' else [
		('arena-storage-escape', 'var samples = new Vector<StreamSample>(0);', 'number(len(arena.bytes)); var samples = new Vector<StreamSample>(0);', 'private'),
		('implicit-numeric-write', 'arena.write_u32_le(id, 0, state as u32)', 'arena.write_u32_le(id, 0, state)', "expects type 'u32'"),
	]
	for name, before, replacement, diagnostic in controls:
		assert source.read_text().count(before) >= 1, (application, name, 'negative control did not change source')
		invalid = out/(name+'.astra'); invalid.write_text(source.read_text().replace(before, replacement, 1))
		for stage in ['--check', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-llvm']:
			run([compiler, stage, '--vapi', api, *text_library, invalid], expected=1, diagnostic=diagnostic)
	if application == 'a84':
		arena = ROOT/'lib/astra/memory/byte-arena.astra'
		condition = 'if (index < 0 || index % width != 0 || this.starts[slot] % width != 0 || this.sizes[slot] < width || index > this.sizes[slot] - width)'
		assert arena.read_text().count(condition)==1
		mutant=out/'unguarded-arena.astra';mutant.write_text(arena.read_text().replace(condition,'if (false)'))
		mutant_executable=out/'unguarded-stream'
		run([compiler,'-O2','--vapi',api,*[mutant if item==arena else item for item in text_library],source,*links,'-o',mutant_executable])
		receipt['products'][str(mutant_executable)] = sha(mutant_executable)
		run([mutant_executable,'7','3','8','probe'],expected=2,stdout=b'+7\n-7\nmissing alignment refusal\nN0\n')
		expected,status=stream_oracle(7,'3',8,'probe')
		run([executable,'7','3','8','probe'],expected=status,stdout=expected)
	assert all(sha(Path(path)) == row['sha256'] for path,row in receipt.get('file_inputs',{}).items()), 'application modified an input file'
	assert sha(compiler) == receipt['compiler_sha256'], 'compiler changed during qualification'
	assert all(sha(ROOT/path) == identity for path,identity in receipt['sources'].items()), 'source changed during qualification'
	receipt['status'] = 'PASS_APPLICATION'
	(out/'checks.json').write_text(json.dumps(receipt, indent=2)+'\n')
	print(f'PASS {application}: {len(receipt["checks"])} public commands; receipt {out / "checks.json"}')


if __name__ == '__main__':
	main(*sys.argv[1:])
