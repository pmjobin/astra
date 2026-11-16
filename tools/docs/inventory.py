#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Editorial source witnesses and explicit coverage debt; never an Astra parser."""
import argparse
import hashlib
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
MAP = [
	('EDITION','README','compiler/driver/main.astra','int astrac_compile(', 'hello','negative-profile'),
	('PROFILE','profiles','compiler/syntax/parser.astra','SyntaxNodeId parse_unit(', 'hello','negative-profile'),
	('LEGACY','profiles','compiler/syntax/program.astra','syntax_source_language_profile', 'shared','negative-profile'),
	('LEXICAL','lexical','compiler/syntax/lexer.astra','class Lexer', 'values','negative-literal'),
	('LITERALS','lexical','compiler/syntax/text-decoder.astra','class TextLiteralDecoder', 'values','negative-literal'),
	('SPANS','lexical','compiler/source/source.astra','class SourceSpan', 'hello','negative-literal'),
	('TYPES','types','compiler/semantic/types.astra','class TypeTable', 'records','negative-type'),
	('NUMERIC','types','compiler/semantic/recover-numeric.astra','void recover_prefix_types_build(', 'values','negative-literal'),
	('TYPE-BOUNDARY','types','compiler/semantic/recover-storage.astra','bool recover_storage_channel(', 'values','negative-vector'),
	('NAMES','declarations','compiler/semantic/index.astra','binding_index', 'application','negative-label'),
	('LOCALS','declarations','compiler/semantic/statements.astra','checked_statement', 'records','negative-type'),
	('CONSTANT-BOUNDARY','declarations','compiler/semantic/recover-build.astra','recover', 'values','negative-constant'),
	('EVALUATION','expressions','compiler/semantic/recover-call-check.astra','recover', 'records','negative-label'),
	('SHORT-CIRCUIT','expressions','compiler/semantic/expressions.astra','checked_expression', 'values','negative-type'),
	('PLACE','expressions','compiler/semantic/recover-record-mutation.astra','recover', 'values','negative-owner'),
	('CHAIN-BOUNDARY','expressions','compiler/semantic/recover-build.astra','recover', 'values','negative-chain'),
	('CONTROL','control','compiler/semantic/recover-loops.astra','recover', 'values','negative-for'),
	('FOR-BOUNDARY','control','compiler/semantic/recover-loops.astra','recover', 'values','negative-for'),
	('FOREACH','control','compiler/semantic/range-iteration.astra','void checked_range_foreach(', 'collections','negative-for'),
	('MATCH','control','compiler/semantic/enum-values-check.astra','enum', 'matching','negative-match'),
	('RECORDS','values','compiler/semantic/recover-record.astra','bool recover_record_source(', 'records','negative-type'),
	('CLASSES','values','compiler/semantic/class-storage.astra','class_storage', 'owners','negative-owner'),
	('ENUMS','values','compiler/semantic/enum-values.astra','enum', 'matching','negative-match'),
	('OWNERS','ownership','compiler/semantic/recover-owner-check.astra','recover', 'owners','negative-owner'),
	('ABORT-CLEANUP','ownership','compiler/semantic/recover-call-check.astra','recover', 'owners','negative-owner'),
	('MOVED-REFUSAL','ownership','compiler/ssa/recover-owners.astra','recover', 'owners','negative-owner'),
	('SHARED','shared','compiler/semantic/recover-shared.astra','bool recover_shared_source(', 'shared','negative-owner'),
	('WEAK','shared','compiler/semantic/recover-shared.astra','bool recover_shared_source_with_bindings(', 'shared','negative-owner'),
	('STORED-BORROW','shared','compiler/semantic/recover-owner-check.astra','recover', 'shared','negative-view'),
	('ARRAYS','collections','compiler/semantic/recover-arrays.astra','recover', 'collections','negative-view'),
	('RANGES','collections','compiler/semantic/integer-ranges.astra','TypeId checked_range_binary(', 'collections','negative-stride'),
	('MATERIALIZATION','collections','compiler/semantic/range-materialization.astra','TypeId checked_range_fixed(', 'fixed','negative-stride'),
	('VIEWS','collections','compiler/semantic/range-slicing.astra','bool range_slice_verified(', 'collections','negative-view'),
	('LAZY','collections','compiler/semantic/lazy-collections.astra','int lazy_call_action(', 'lazy','negative-view'),
	('GENERICS','generics','compiler/semantic/generic.astra','SymbolId generic_instantiate(', 'records','negative-type'),
	('CONSTRAINTS','generics','compiler/semantic/generic-syntax-check.astra','generic', 'records','negative-type'),
	('GENERIC-LIMIT','generics','compiler/semantic/generic.astra','SymbolId generic_instantiate(', 'records','negative-type'),
	('TEXT','text','compiler/semantic/text-storage.astra','text', 'formatting','negative-type'),
	('FORMAT','text','compiler/semantic/formatting.astra','TypeId checked_formatting_call(', 'formatting','negative-type'),
	('UTF8-BOUNDARY','text','compiler/semantic/recover-utf8.astra','recover', 'formatting','negative-type'),
	('ERRORS','errors','compiler/semantic/effect-check.astra','checked', 'errors','negative-type'),
	('ERROR-CLEANUP','errors','compiler/semantic/recover-error-storage.astra','recover', 'errors','negative-owner'),
	('FATAL','errors','compiler/semantic/recover-arrays.astra','recover', 'errors','negative-literal'),
	('ABI','abi','compiler/backend/llvm/effect-abi.astra','class NativeCheckedAbi', 'application','negative-type'),
	('COUNTED-C','abi','compiler/semantic/foreign-text.astra','bool checked_c_counted_signature(', 'application','negative-type'),
	('PROFILES','abi','compiler/driver/main.astra','int astrac_compile(', 'fixed','negative-pointer'),
	('GRAMMAR','grammar','compiler/syntax/parser.astra','class SyntaxParser', 'hello','negative-profile'),
	('PRECEDENCE','grammar','compiler/syntax/parser.astra','int infix_binding_power(', 'values','negative-chain'),
	('LIMITS','limits','compiler/driver/main.astra','int astrac_compile(', 'hello','negative-type'),
	('MATRIX','limits','compiler/semantic/recover-storage.astra','bool recover_storage_channel(', 'hello','negative-vector'),
	('QUALIFICATION','limits','compiler/driver/main.astra','int astrac_compile(', 'hello','negative-owner'),
	('HISTORY','limits','docs/decisions/0170-rebuilt-c0-release-provenance.md','ACCEPTED', 'hello','negative-owner'),
]


def sha(data):
	return hashlib.sha256(data).hexdigest()


def products():
	rules = []
	for identifier,chapter,path,symbol,positive,negative in MAP:
		data = (ROOT/path).read_bytes()
		assert symbol.encode() in data,(path,symbol)
		if symbol in ('recover','checked','enum','generic','effect','text','class_storage','binding_index','checked_statement','checked_expression','syntax_source_language_profile'):
			candidates = re.findall(rb'(?m)^\w[^\n]*\([^\n]*\)[^\n]*\{',data)
			declaration = next((line for line in candidates if symbol.encode() in line),None)
			assert declaration,(path,symbol)
			symbol = declaration.decode().split('(')[0].split()[-1]
		at = data.index(symbol.encode()); start = data.rfind(b'\n',0,at)+1
		end = data.find(b'\n',at+len(symbol))
		if end < 0: end = len(data)
		rules.append(dict(id='R-'+identifier,chapter='docs/reference/'+chapter+'.md',sources=[dict(path=path,symbol=symbol,sha256=sha(data),span=[start,end],span_sha256=sha(data[start:end]))],positive=[dict(path='tests/books/examples.json',id=positive)],negative=[dict(path='tests/books/examples.json',id=negative)],coverage='REPRESENTATIVE_CONTROLS_ONLY; exhaustive rule-specific conformance remains to be established'))
	inputs = sorted([*ROOT.glob('compiler/**/*.astra'),*ROOT.glob('lib/astra/**/*.astra')])
	mapped = {r['sources'][0]['path'] for r in rules}
	rows = [dict(path=str(path.relative_to(ROOT)),bytes=path.stat().st_size,sha256=sha(path.read_bytes()),rule_ids=[r['id'] for r in rules if r['sources'][0]['path']==str(path.relative_to(ROOT))],review='DIRECT_RULE_WITNESS' if str(path.relative_to(ROOT)) in mapped else 'INVENTORIED_NOT_EXHAUSTIVELY_REVIEWED') for path in inputs]
	model = json.loads((ROOT/'compiler/syntax/model.json').read_text())
	modern = (ROOT/'compiler/syntax/model.astra').read_bytes()
	enum = modern.split(b'enum SyntaxKind {',1)[1].split(b'\n}',1)[0]
	names = re.findall(rb'(?m)^\t([A-Za-z0-9_]+),?$',enum)
	families = [dict(name=name.decode(),abstract=model['nodes'].get(name.decode(),{}).get('abstract'),status='PARSER_REPRESENTATION_ONLY; NOT_EXHAUSTIVE_NATIVE_RULE_COVERAGE',legacy_source=model['nodes'].get(name.decode(),{}).get('path')) for name in names]
	return {'rules.json':dict(format='astra-book-rules/1',edition='28-A2',status='PARTIAL_EXHAUSTIVE_CONFORMANCE_REMAINS',rules=rules), 'inventory.json':dict(format='astra-book-source-inventory/1',edition='28-A2',status='COMPLETE_FILE_INVENTORY_PARTIAL_SEMANTIC_REVIEW',source_files=rows,syntax_model_sha256=sha(modern),syntax_families=families,method='Exact file inventory, literal declaration witnesses and actual SyntaxKind enum names. No language parsing, native execution or inferred semantic coverage.',unreviewed_source_units=sum(r['review']=='INVENTORIED_NOT_EXHAUSTIVELY_REVIEWED' for r in rows))}


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--check',action='store_true')
	a = p.parse_args()
	for name,value in products().items():
		path = ROOT/'docs/books'/name
		data = (json.dumps(value,sort_keys=True,indent=2)+'\n').encode()
		if a.check: assert path.read_bytes() == data,path
		else:
			path.parent.mkdir(parents=True,exist_ok=True)
			path.write_bytes(data)
	print('Book source witnesses match; exhaustive semantic coverage remains PARTIAL')


if __name__ == '__main__':
	main()
