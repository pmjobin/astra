#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independent C0-syntax closure for nested, uniquely instantiated value records.

The established C++ layout generator remains independent of Astra's planner.
Ambiguous concrete instances and open value fields are refused, never guessed.
"""
import importlib.util
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('established_probe',ROOT/'tests/selfhost-classstorage/abi-probe.py')
base = importlib.util.module_from_spec(spec); spec.loader.exec_module(base)
syntax = base.syntax


def parse_type(text):
	text = text.removeprefix('nonnull ')
	tokens = re.findall(r'[A-Za-z_]\w*|[<>,]',text)
	if ''.join(tokens) != re.sub(r'\s+','',text): return None
	def parse(at,depth=0):
		assert depth <= 128
		assert at < len(tokens) and re.fullmatch(r'[A-Za-z_]\w*',tokens[at])
		name = tokens[at]; at += 1; arguments = []
		if at < len(tokens) and tokens[at] == '<':
			at += 1
			while True:
				argument,at = parse(at,depth+1); arguments.append(argument)
				if tokens[at] == '>': at += 1; break
				assert tokens[at] == ','; at += 1
		return (name,tuple(arguments)),at
	try:
		result,end = parse(0)
		return result if end == len(tokens) else None
	except (AssertionError,IndexError): return None


def render(type):
	name,arguments = type
	return name+('<'+','.join(map(render,arguments))+'>' if arguments else '')


def specialize_value_fields(declarations,tree):
	primitives = set('int i8 u8 i16 u16 i32 u32 i64 u64 f32 f64 bool string'.split())
	def closed(type,depth=0):
		if type is None or depth > 128: return False
		name,arguments = type
		if name in primitives: return not arguments
		return name in declarations and len(arguments) == len(declarations[name].get('parameters',[])) and all(closed(argument,depth+1) for argument in arguments)
	queue = []
	def request(type):
		if not closed(type): return
		name,arguments = type
		if arguments: queue.append(type)
		for argument in arguments: request(argument)
	def visit(node):
		if isinstance(node,str): request(parse_type(node))
		elif isinstance(node,list):
			for child in node: visit(child)
	visit(tree); instances = {name:set() for name in declarations}
	def substitute(type,mapping):
		name,arguments = type
		if not arguments and name in mapping: return mapping[name]
		return name,tuple(substitute(argument,mapping) for argument in arguments)
	while queue:
		name,arguments = queue.pop(0)
		if arguments in instances[name]: continue
		instances[name].add(arguments)
		assert sum(map(len,instances.values())) <= 256,'independent layout closure bound'
		mapping = dict(zip(declarations[name].get('parameters',[]),arguments))
		for field in declarations[name]['fields']:
			type = parse_type(field['type'])
			if type: request(substitute(type,mapping))
	resolved = {}
	for name,declaration in declarations.items():
		parameters = declaration.get('parameters',[])
		inline = [field for field in declaration['fields'] if not field['type'].endswith(('[]','[slots]'))]
		dependent = any(any(re.search(r'\b'+re.escape(parameter)+r'\b',field['type']) for parameter in parameters) for field in inline)
		if parameters and dependent:
			assert len(instances[name]) == 1,('inline generic probe requires one exact closed instance',name,instances[name])
			arguments = next(iter(instances[name])); mapping = dict(zip(parameters,arguments))
			resolved[name] = {parameter:render(type) for parameter,type in mapping.items()}
		else: mapping = {}
		for field in inline:
			type = parse_type(field['type']); assert type is not None,('unsupported independent value-field syntax',field)
			type = substitute(type,mapping); assert closed(type),('open independent value field',name,field)
			base_name,arguments = type
			if arguments:
				assert len(instances[base_name]) == 1 and arguments in instances[base_name],('ambiguous nested probe',type)
			field['type'] = base_name
	return resolved


def main():
	base.specialize_value_fields = specialize_value_fields
	base.main()
	runtime = Path(sys.argv[sys.argv.index('--runtime')+1]); result = runtime/'result.json'
	data = json.loads(result.read_text()); data['nested_value_probe_wrapper_sha256'] = base.sha(__file__); data['established_probe_sha256'] = base.sha(ROOT/'tests/selfhost-classstorage/abi-probe.py')
	data['nested_value_probe_scope'] = 'C0 syntax only; exact declaration-local substitution closure; one concrete inline layout per declaration; no candidate type/layout/cache facts consumed'
	result.write_text(json.dumps(data,indent=2)+'\n')


if __name__ == '__main__':
	main()
