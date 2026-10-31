#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Import an explicitly selected, fail-closed GObject GIR profile into typed VAPI/C."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
from xml.parsers import expat

GI = 'http://www.gtk.org/introspection/core/1.0}'
C = 'http://www.gtk.org/introspection/c/1.0}'
GLIB = 'http://www.gtk.org/introspection/glib/1.0}'
IDENT = re.compile(r'[A-Za-z_][A-Za-z0-9_]*\Z')
MEMBER = re.compile(r'[A-Za-z_][A-Za-z0-9_-]*\Z')


class Rejected(ValueError):
	pass


class Node:
	def __init__(self, tag, attributes, path, line, column):
		self.tag, self.attributes, self.path = tag, attributes, path
		self.line, self.column, self.children = line, column, []

	def fail(self, message):
		raise Rejected(f'{self.path}:{self.line}:{self.column}: error: {message}')

	def attrs(self, allowed):
		unknown = set(self.attributes) - set(allowed)
		if unknown:
			self.fail('unsupported GIR annotation '+sorted(unknown)[0])

	def one(self, tag):
		found = [child for child in self.children if child.tag == tag]
		if len(found) != 1:
			self.fail('expected exactly one '+tag.split('}')[-1])
		return found[0]

	def content(self, allowed):
		for child in self.children:
			if child.tag not in {GI+'doc', GI+'doc-deprecated', GI+'source-position', *allowed}:
				child.fail('unsupported GIR construct '+child.tag.split('}')[-1])


def parse(path):
	data = path.read_bytes()
	if len(data) > 16*1024*1024:
		raise Rejected(f'{path}:1:1: error: GIR exceeds finite input limit')
	parser = expat.ParserCreate(namespace_separator='}')
	stack, roots = [], []
	count = 0

	def start(tag, attributes):
		nonlocal count
		count += 1
		if count > 250000 or len(stack) > 64:
			raise Rejected(f'{path}:{parser.CurrentLineNumber}:1: error: GIR nesting/node limit')
		node = Node(tag, attributes, str(path), parser.CurrentLineNumber, parser.CurrentColumnNumber+1)
		if stack: stack[-1].children.append(node)
		else: roots.append(node)
		stack.append(node)

	def forbidden(*args):
		raise Rejected(f'{path}:{parser.CurrentLineNumber}:1: error: DTD/entities are unsupported')

	parser.StartElementHandler = start
	parser.EndElementHandler = lambda tag: stack.pop()
	parser.StartDoctypeDeclHandler = forbidden
	parser.EntityDeclHandler = forbidden
	parser.ExternalEntityRefHandler = forbidden
	try:
		parser.Parse(data, True)
	except expat.ExpatError as error:
		raise Rejected(f'{path}:{error.lineno}:{error.offset+1}: error: malformed GIR XML: {error}') from error
	if len(roots) != 1 or roots[0].tag != GI+'repository' or roots[0].attributes.get('version') != '1.2':
		raise Rejected(f'{path}:1:1: error: expected GIR repository version 1.2')
	return roots[0], hashlib.sha256(data).hexdigest()


def unique_json(pairs):
	result = {}
	for key, value in pairs:
		if key in result: raise Rejected('duplicate profile key '+key)
		result[key] = value
	return result


def identifier(value, node=None):
	if not isinstance(value, str) or not IDENT.fullmatch(value):
		if node: node.fail('invalid C/source identifier')
		raise Rejected('invalid profile identifier '+str(value))
	return value


def normalize(profile, documents):
	if set(profile) != {'format', 'target', 'namespaces', 'packages', 'objects'} or profile['format'] != 'astra-gir-profile/1' or profile['target'] != 'gnu-x86_64-sysv-lp64':
		raise Rejected('unsupported GIR profile/schema/target')
	spaces, inputs = {}, {}
	for root, digest in documents:
		space = root.one(GI+'namespace')
		name = identifier(space.attributes.get('name'), space)
		if name in spaces: space.fail('duplicate namespace input '+name)
		if name not in profile['namespaces'] or space.attributes.get('version') != profile['namespaces'][name]: space.fail('namespace/version does not match selected profile')
		spaces[name] = space
		inputs[name] = digest
	if set(spaces) != set(profile['namespaces']): raise Rejected('missing selected GIR namespace input')
	objects = {}
	for selected in profile['objects']:
		if set(selected) != {'namespace', 'name', 'ctype', 'get_type', 'parent', 'header', 'constructors', 'methods', 'properties', 'signals'}: raise Rejected('unknown/missing object profile member')
		namespace, name = identifier(selected['namespace']), identifier(selected['name'])
		key = namespace+'.'+name
		if key in objects: raise Rejected('duplicate selected object '+key)
		space = spaces[namespace]
		found = [node for node in space.children if node.tag == GI+'class' and node.attributes.get('name') == name]
		if len(found) != 1: space.fail('selected object missing/duplicated: '+name)
		node = found[0]
		node.attrs({'name', C+'type', C+'symbol-prefix', GLIB+'type-name', GLIB+'get-type', GLIB+'type-struct', 'parent', 'abstract', 'final', 'version', 'introspectable'})
		ctype, get_type = identifier(selected['ctype']), identifier(selected['get_type'])
		parent = node.attributes.get('parent')
		if parent and '.' not in parent: parent = namespace+'.'+parent
		if node.attributes.get(C+'type') != ctype or node.attributes.get(GLIB+'get-type') != get_type or parent != selected['parent']:
			node.fail('object C type/GType/parent identity differs from profile')
		if node.attributes.get('introspectable', '1') != '1' or node.attributes.get('abstract', '0') != '0': node.fail('abstract/non-introspectable object unsupported')
		if not re.fullmatch(r'[A-Za-z0-9_./-]+\.h', selected['header']) or '..' in selected['header'].split('/'): node.fail('unsafe header name')
		for category in ('constructors', 'methods', 'properties', 'signals'):
			values = selected[category]
			if not isinstance(values, list) or len(values) != len(set(values)) or any(not MEMBER.fullmatch(v) for v in values): node.fail('invalid/duplicate selected member list')
		gtype_name = identifier(node.attributes.get(GLIB+'type-name'), node)
		objects[key] = dict(selected, node=node, handle=namespace+name, gtype_name=gtype_name)

	def value(node, namespace, property_value=False):
		node.content({GI+'type'})
		type_node = node.one(GI+'type')
		type_node.attrs({'name', C+'type'})
		type_node.content(set())
		name = type_node.attributes.get('name')
		ctype = type_node.attributes.get(C+'type')
		transfer = node.attributes.get('transfer-ownership')
		if transfer not in ('none', 'full'): node.fail('explicit transfer-ownership none/full required')
		nullable = node.attributes.get('nullable', node.attributes.get('allow-none', '0'))
		if nullable not in ('0', '1') or ('allow-none' in node.attributes and node.attributes['allow-none'] != nullable): node.fail('conflicting nullable contract')
		if name in ('gint', 'none', 'utf8'):
			allowed = {'gint': {'gint'}, 'none': {'void'}, 'utf8': {'const gchar*'}}[name]
			if (ctype not in allowed and not (property_value and ctype is None)) or transfer != 'none' or (name != 'utf8' and nullable != '0'):
				node.fail('unsupported scalar/string C type, transfer or nullable contract')
			return dict(kind=name, ctype=ctype, transfer=transfer, nullable=nullable == '1')
		key = name if name and '.' in name else namespace+'.'+str(name)
		if key not in objects: node.fail('unsupported GIR type '+str(name))
		obj = objects[key]
		if ctype != obj['ctype']+'*' and not (key == 'GObject.Object' and ctype == 'gpointer'): node.fail('object pointer C type does not match nominal GType')
		return dict(kind='object', object=key, ctype=ctype, transfer=transfer, nullable=nullable == '1')

	api, seen_symbols = [], set()
	for key, obj in sorted(objects.items()):
		node, namespace = obj['node'], obj['namespace']
		known_members = {GI+tag for tag in ('method', 'constructor', 'function', 'virtual-method', 'field', 'property', 'implements', 'constant', 'record')} | {GLIB+'signal'}
		node.content(known_members)
		for category, tag in (('constructors', GI+'constructor'), ('methods', GI+'method'), ('properties', GI+'property'), ('signals', GLIB+'signal')):
			for name in sorted(obj[category]):
				matches = [child for child in node.children if child.tag == tag and child.attributes.get('name') == name]
				if len(matches) != 1: node.fail('selected member missing/duplicated: '+name)
				member = matches[0]
				base = obj['handle']+'_'+name.replace('-', '_')
				if category == 'properties':
					member.attrs({'name', 'readable', 'writable', 'construct', 'construct-only', 'transfer-ownership', 'version'})
					if member.attributes.get('construct-only', '0') != '0' or member.attributes.get('construct', '0') != '0': member.fail('construction property unsupported')
					for flag in ('readable', 'writable'):
						if member.attributes.get(flag, '1' if flag == 'readable' else '0') not in ('0', '1'): member.fail('invalid property access flag')
					typed = value(member, namespace, True)
					if typed['kind'] not in ('gint', 'utf8'): member.fail('unsupported property type')
					api.append(dict(kind='property', owner=key, name=name, source=base, type=typed, readable=member.attributes.get('readable', '1') == '1', writable=member.attributes.get('writable', '0') == '1'))
					continue
				member.attrs({'name', C+'identifier', 'version', 'introspectable', 'when', 'deprecated', 'deprecated-version'})
				member.content({GI+'return-value', GI+'parameters'})
				if member.attributes.get('introspectable', '1') != '1': member.fail('non-introspectable callable unsupported')
				returned = member.one(GI+'return-value')
				returned.attrs({'transfer-ownership', 'nullable', 'allow-none'})
				result = value(returned, namespace)
				parameters = member.one(GI+'parameters')
				parameters.attrs(set())
				parameters.content({GI+'parameter', GI+'instance-parameter'})
				args = []
				for parameter in parameters.children:
					if parameter.tag not in (GI+'parameter', GI+'instance-parameter'): continue
					parameter.attrs({'name', 'transfer-ownership', 'nullable', 'allow-none'})
					identifier(parameter.attributes.get('name'), parameter)
					args.append(dict(value(parameter, namespace), receiver=parameter.tag == GI+'instance-parameter'))
				if len(args) > 4: member.fail('finite callable parameter limit exceeded')
				if category == 'signals':
					if result['kind'] != 'gint' or len(args) != 1 or args[0]['kind'] != 'gint' or args[0]['receiver'] or member.attributes.get('when') != 'last': member.fail('only last int(int) signals supported')
					api.append(dict(kind='signal', owner=key, name=name, source=base, result=result, parameters=args))
					continue
				symbol = identifier(member.attributes.get(C+'identifier'), member)
				if symbol in seen_symbols: member.fail('duplicate selected C symbol '+symbol)
				seen_symbols.add(symbol)
				if category == 'constructors':
					if result.get('object') != key or result['transfer'] != 'full' or any(a['kind'] != 'gint' or a['receiver'] for a in args): member.fail('constructor requires full exact object and copied int parameters')
				else:
					if not args or not args[0]['receiver'] or args[0].get('object') != key or args[0]['nullable'] or any(a['receiver'] or a['kind'] != 'gint' for a in args[1:]): member.fail('method requires exact nonnullable object receiver and copied int parameters')
					if args[0]['transfer'] == 'full' and not (symbol == 'g_object_unref' and result['kind'] == 'none' and len(args) == 1): member.fail('consuming method is not the selected GObject unref contract')
					if result['kind'] == 'object' and result['transfer'] != 'full': member.fail('borrowed object returns are unsupported; no implicit ownership upgrade')
				api.append(dict(kind='constructor' if category == 'constructors' else 'method', owner=key, name=name, source=base, symbol=symbol, result=result, parameters=args))
	return objects, api, inputs


def generate(profile_path, gir_paths, policy_attributes=False):
	profile_bytes = profile_path.read_bytes()
	profile = json.loads(profile_bytes, object_pairs_hook=unique_json)
	if profile.get('format') == 'astra-gir-declarations-profile/1':
		from declarations import generate as generate_declarations
		return generate_declarations(profile, profile_bytes, [parse(path) for path in gir_paths], Path(__file__).read_bytes(), Rejected)
	objects, api, inputs = normalize(profile, [parse(path) for path in gir_paths])
	packages = {}
	for package in profile['packages']:
		if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]*', package): raise Rejected('unsafe package name')
		p = subprocess.run(['pkg-config', '--modversion', package], capture_output=True, text=True, timeout=20)
		if p.returncode: raise Rejected('selected pkg-config dependency unavailable: '+package)
		packages[package] = p.stdout.strip()
	version = packages.get('gobject-2.0', '')
	if not re.fullmatch(r'2\.[0-9]+\.[0-9]+', version): raise Rejected('selected profile requires an exact GObject 2.x.y package version')
	major, minor, micro = map(int, version.split('.'))
	generator_sha256 = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
	identity = hashlib.sha256(json.dumps(dict(format='astra-gir-contract/1', target=profile['target'], packages=packages,
		profile_sha256=hashlib.sha256(profile_bytes).hexdigest(), gir_sha256=inputs, generator_sha256=generator_sha256, policy_attributes=policy_attributes), sort_keys=True).encode()).hexdigest()
	prefix = 'astra_gir_'+identity+'_'
	validation_symbol = prefix+'contract_valid'
	vapi = ['// Generated by astra-gir/1; explicit foreign Resource boundaries.']
	bridge_header = ['/* Generated typed C bridge declarations; astra-gir/1. */', '#ifndef ASTRA_GIR_'+identity.upper(), '#define ASTRA_GIR_'+identity.upper(), '#include <stdint.h>', '#ifdef __cplusplus', 'extern "C" {', '#endif']
	native = ['// Generated by astra-gir/1; consuming calls use native cleanup authority.']
	code = ['/* Generated by astra-gir/1. */', '#include "gobject.h"', '#include "gobject-signals.h"', '#include <limits.h>', '#include <string.h>']
	for header in sorted({obj['header'] for obj in objects.values()}): code.append(f'#include "{header}"')
	code += ['_Static_assert(sizeof(gint) == 4 && sizeof(void *) == 8 && sizeof(GType) == 8, "GIR LP64 scalar profile");', '#if !defined(__linux__) || !defined(__x86_64__)', '#error "GIR profile requires qualified GNU x86-64 Linux"', '#endif']
	code.append(f'_Static_assert(GLIB_MAJOR_VERSION == {major} && GLIB_MINOR_VERSION == {minor} && GLIB_MICRO_VERSION == {micro}, "GIR selected header version");')
	for obj in objects.values():
		vapi += ['[CCode(destroy_function = "astra_gobject_unref")]', f'handle {obj["handle"]};']
		code.append(f'_Static_assert(_Generic(&{obj["get_type"]}, GType (*)(void): 1, default: 0), "GType function ABI");')
	vapi += ['[CCode(destroy_function = "astra_gobject_text_free")] handle GirUtf8;', '[CCode(destroy_function = "astra_gobject_signal_source_free")] handle GirSignal;']
	validation = [f'if (glib_major_version != {major} || glib_minor_version != {minor} || glib_micro_version != {micro}) return 0;']
	for key, obj in sorted(objects.items()):
		validation += ['{', f'GType type = {obj["get_type"]}();', f'if (!g_type_is_a(type, G_TYPE_OBJECT) || strcmp(g_type_name(type), "{obj["gtype_name"]}")) return 0;']
		if obj['parent']:
			if obj['parent'] not in objects: obj['node'].fail('selected parent type is missing from profile')
			validation.append(f'if (g_type_parent(type) != {objects[obj["parent"]]["get_type"]}()) return 0;')
		validation.append('GObjectClass *klass = g_type_class_ref(type);')
		for item in api:
			if item['owner'] != key: continue
			if item['kind'] == 'property':
				expected = 'G_TYPE_INT' if item['type']['kind'] == 'gint' else 'G_TYPE_STRING'
				flags = (1 if item['readable'] else 0) | (2 if item['writable'] else 0)
				validation += ['{', f'GParamSpec *spec = g_object_class_find_property(klass, "{item["name"]}");', f'if (!spec || G_PARAM_SPEC_VALUE_TYPE(spec) != {expected} || (spec->flags & (G_PARAM_READABLE | G_PARAM_WRITABLE | G_PARAM_CONSTRUCT_ONLY)) != {flags}) {{ g_type_class_unref(klass); return 0; }}', '}']
			elif item['kind'] == 'signal':
				validation += ['{', 'GSignalQuery query;', f'g_signal_query(g_signal_lookup("{item["name"]}", type), &query);', 'if (!query.signal_id || query.itype != type || query.return_type != G_TYPE_INT || query.n_params != 1 || query.param_types[0] != G_TYPE_INT || (query.signal_flags & (G_SIGNAL_RUN_FIRST | G_SIGNAL_RUN_LAST | G_SIGNAL_RUN_CLEANUP)) != G_SIGNAL_RUN_LAST) { g_type_class_unref(klass); return 0; }', '}']
		validation += ['g_type_class_unref(klass);', '}']
	code.append('int32_t '+validation_symbol+'(void) {\n'+''.join('\t'+line+'\n' for line in validation)+'\treturn 1;\n}')
	vapi.append(('[GObjectImport(name = "'+validation_symbol+'", header = "bindings.h")]' if policy_attributes else '[CCode(cname = "'+validation_symbol+'")]')+' int gir_contract_valid();')
	bridge_header.append('int32_t '+validation_symbol+'(void);')
	emitted = {'gir_contract_valid'}

	def declaration(name, result, parameters, body, text=False):
		if name in emitted: raise Rejected('generated source/symbol collision: '+name)
		emitted.add(name)
		symbol = prefix+name
		metadata = (f'[GObjectImport(name = "{symbol}", header = "bindings.h"' if policy_attributes else f'[CCode(cname = "{symbol}"')+(', text_abi = "utf8-i32"' if text else '')+')]'
		vapi.append(metadata+' '+result+' '+name+'('+', '.join(p[0] for p in parameters)+');')
		c_result = 'void' if result == 'void' else 'void *' if result.startswith('owned ') else 'int32_t'
		c_parameters = [p[1] for p in parameters]
		bridge_header.append(c_result+' '+symbol+'('+(', '.join(c_parameters) or 'void')+');')
		if not any(p[0].startswith('owned ') for p in parameters):
			failure = 'return;' if result == 'void' else 'return NULL;' if result.startswith('owned ') else 'return INT32_MIN;'
			body = ['if (!'+validation_symbol+'()) '+failure, *body]
		code.append(c_result+' '+symbol+'('+(', '.join(c_parameters) or 'void')+') {\n'+''.join('\t'+line+'\n' for line in body)+'}')

	for item in api:
		obj = objects[item['owner']]
		name, handle = item['source'], obj['handle']
		receiver = ('borrowed '+handle+' object', 'void *object')
		check = f'if (!astra_gobject_peek(object, {obj["get_type"]}()))'
		if item['kind'] == 'property':
			name = obj['handle']+'_property_'+item['name'].replace('-', '_')
			prop = item['name']
			if item['type']['kind'] == 'gint':
				if item['readable']: declaration(name+'_get', 'int', [receiver], [check+' return INT32_MIN;', 'int32_t result;', f'return astra_gobject_get_int(object, "{prop}", &result) == 1 ? result : INT32_MIN;'])
				if item['writable']: declaration(name+'_set', 'int', [receiver, ('int value', 'int32_t value')], [check+' return -1;', f'return astra_gobject_set_int(object, "{prop}", value);'])
			else:
				if item['readable']: declaration(name+'_copy', 'owned GirUtf8', [receiver], [check+' return NULL;', f'return astra_gobject_copy_utf8(object, "{prop}");'])
				if item['writable']: declaration(name+'_set', 'int', [receiver, ('borrowed string text', 'const uint8_t *text, int32_t length')], [check+' return -1;', f'return astra_gobject_set_utf8(object, "{prop}", text, length);'], True)
			continue
		if item['kind'] == 'signal':
			declaration(name+'_source', 'owned GirSignal', [receiver], [check+' return NULL;', f'return astra_gobject_signal_source(object, (const uint8_t *)"{item["name"]}", {len(item["name"])});'])
			continue
		result, args, symbol = item['result'], item['parameters'], item['symbol']
		code.append(f'_Static_assert(_Generic(&{symbol}, {result["ctype"]} (*)('+(', '.join(a['ctype'] for a in args) or 'void')+'): 1, default: 0), "GIR function ABI: '+symbol+'");')
		parameters, body, passed = [], [], []
		for index, arg in enumerate(args):
			if arg['receiver']:
				parameters.append((('owned ' if arg['transfer'] == 'full' else 'borrowed ')+handle+' object', 'void *object'))
				if arg['transfer'] != 'full':
					body.append(f'{arg["ctype"]} receiver = ({arg["ctype"]})astra_gobject_peek(object, {obj["get_type"]}());')
					failure = 'return;' if result['kind'] == 'none' else 'return INT32_MIN;' if result['kind'] == 'gint' else 'return NULL;'
					body.append('if (!receiver) '+failure)
					passed.append('receiver')
			else:
				parameters.append((f'int value{index}', f'int32_t value{index}'))
				passed.append(f'value{index}')
		call = symbol+'('+', '.join(passed)+')'
		if args and args[0]['transfer'] == 'full':
			if name in emitted: raise Rejected('generated source/symbol collision: '+name)
			emitted.add(name)
			native.append(f'void {name}(owned {handle} object) {{}}')
		elif result['kind'] == 'object':
			result_obj = objects[result['object']]
			body += [f'{result["ctype"]} result = {call};', f'return astra_gobject_take((GObject *)result, {result_obj["get_type"]}());']
			declaration(name, 'owned '+result_obj['handle'], parameters, body)
		elif result['kind'] == 'utf8':
			body.append(f'return astra_gobject_copy_text({call});')
			declaration(name+'_copy', 'owned GirUtf8', parameters, body)
		elif result['kind'] == 'none':
			declaration(name, 'void', parameters, body+[call+';'])
		else:
			declaration(name, 'int', parameters, body+['return '+call+';'])
	declaration('gir_text_length', 'int', [('borrowed GirUtf8 text', 'void *text')], ['return astra_gobject_text_length(text);'])
	declaration('gir_text_byte', 'int', [('borrowed GirUtf8 text', 'void *text'), ('int index', 'int32_t index')], ['return astra_gobject_text_byte(text, index);'])
	declaration('gir_signal_mode', 'int', [('borrowed GirSignal source', 'void *source')], ['return astra_gobject_signal_mode(source);'])
	if policy_attributes: code.insert(1, '#include "bindings.h"')
	files = {'bindings.vapi': ('\n'.join(vapi)+'\n').encode(), 'bindings.c': ('\n'.join(code)+'\n').encode(), 'bindings.astra': ('\n'.join(native)+'\n').encode()}
	if policy_attributes:
		bridge_header += ['#ifdef __cplusplus', '}', '#endif', '#endif']
		files['bindings.h'] = ('\n'.join(bridge_header)+'\n').encode()
	contract = dict(format='astra-gir-contract/1', policy_attributes=policy_attributes, target=profile['target'], namespaces=profile['namespaces'], packages=packages,
		profile_sha256=hashlib.sha256(profile_bytes).hexdigest(), gir_sha256=inputs, api=api,
		generator_sha256=generator_sha256, abi_identity=identity,
		objects=[{k: v for k, v in obj.items() if k != 'node'} for obj in objects.values()],
		products={name: hashlib.sha256(data).hexdigest() for name, data in files.items()})
	contract['fingerprint'] = hashlib.sha256(json.dumps(contract, sort_keys=True, separators=(',', ':')).encode()).hexdigest()
	files['contract.json'] = (json.dumps(contract, sort_keys=True, indent=2)+'\n').encode()
	return files


def main():
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument('--profile', type=Path, required=True)
	parser.add_argument('--gir', type=Path, action='append', required=True)
	parser.add_argument('--policy-attributes', action='store_true', help='emit typed GObjectImport and an exact C bridge header')
	group = parser.add_mutually_exclusive_group(required=True)
	group.add_argument('--output', type=Path)
	group.add_argument('--verify', type=Path)
	args = parser.parse_args()
	try:
		files = generate(args.profile, args.gir, args.policy_attributes)
		if args.verify:
			for name, data in files.items():
				if (args.verify/name).is_symlink() or (args.verify/name).read_bytes() != data:
					raise Rejected(f'{args.verify/name}:1:1: error: generated GIR contract/product drift')
			print('verified '+('astra-gir-declarations/1' if 'bindings.vapi' not in files else 'astra-gir/1')+' typed products')
		else:
			if args.output.exists(): raise Rejected('output directory already exists; select a fresh generation directory')
			args.output.mkdir(parents=True)
			for name, data in files.items():
				with (args.output/name).open('xb') as stream: stream.write(data)
			print('generated '+('astra-gir-declarations/1' if 'bindings.vapi' not in files else 'astra-gir/1')+' typed products')
		return 0
	except (Rejected, OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError) as error:
		print('astra-gir: '+str(error), file=sys.stderr)
		return 1


if __name__ == '__main__':
	sys.exit(main())
