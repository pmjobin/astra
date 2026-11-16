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
	('DEFAULT-CHANNELS','ownership','compiler/semantic/elaborate.astra','TypeId checked_declared(', 'ownership-defaults','negative-stored-borrow'),
	('REARM-BOUNDARY','ownership','compiler/semantic/recover-loops.astra','bool recover_mutable(', 'owners','negative-rearm'),
	('BORROW-ANCHOR','shared','compiler/semantic/class-storage-flow.astra','bool class_storage_constructor_verified(', 'ownership-defaults','negative-stored-borrow'),
	('NUMERIC-EDGES','types','compiler/backend/llvm/recover-integer-check.astra','bool recover_integer_helper_verified(', 'numeric-contract','negative-numeric-mix'),
	('ORDER-TRACE','expressions','compiler/semantic/generic-methods.astra','checked_call_written_arguments(', 'evaluation-order','negative-label'),
	('CALL-ABORT','expressions','compiler/core/recover-owners.astra','bool recover_owner_uses(', 'call-abort','negative-owner'),
	('COLLECTION-COUNTS','collections','compiler/semantic/range-materialization.astra','int range_fixed_count(', 'range-edges','negative-fixed-count'),
	('FINITE-LAZY','collections','compiler/semantic/lambda-callables.astra','owned LambdaFacts lambda_facts(', 'numeric-pipeline','negative-dynamic-comprehension'),
	('VIEW-ROOTS','collections','compiler/semantic/range-slicing.astra','SymbolId range_slice_root(', 'collections','negative-view'),
	('CAPABILITY-SET','generics','compiler/semantic/generic-check.astra','bool generic_capability_verified(', 'generic-contract','negative-generic-capability'),
	('SPECIALIZATION','generics','compiler/semantic/generic-check.astra','bool generic_checked_instance_verified(', 'generic-contract','negative-generic-capability'),
	('FORMAT-DOMAIN','text','lib/astra/text/scalar-format.astra','bool astra_format_hex(', 'formatting','negative-type'),
	('HANDLER-SCOPE','errors','compiler/semantic/effect-source.astra','void checked_effect_source_visit(', 'call-abort','negative-type'),
	('COUNTED-SIGNATURE','abi','compiler/semantic/foreign-text.astra','bool checked_c_counted_signature(', 'application','negative-type'),
]


def sha(data):
	return hashlib.sha256(data).hexdigest()


def products(api_spans=None):
	prior = json.loads((ROOT/'docs/books/inventory.json').read_text())
	prior_rules = json.loads((ROOT/'docs/books/rules.json').read_text())
	retained_spans = {r['id']:r['sources'][0] for r in prior_rules['rules']}
	document = json.loads(api_spans.read_text()) if api_spans else None
	if document:
		assert document['format']=='astra-api-docs/1'
		assert all(sha((ROOT/row['path']).read_bytes())==row['sha256'] for row in document['inputs'])
	reviews = {row['path']:row.get('role_review') for row in prior['source_files']}
	family_reviews = {row['name']:row.get('grammar_review') for row in prior['syntax_families']}
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
		source = dict(path=path,symbol=symbol,sha256=sha(data),git_blob=hashlib.sha1(b'blob '+str(len(data)).encode()+b'\0'+data).hexdigest(),span=[start,end],span_sha256=sha(data[start:end]))
		source['span_kind'] = 'DECLARATION_LINE_ONLY; body conformance remains independent'
		old = retained_spans.get('R-'+identifier,{})
		if old.get('span_kind')=='ACTUAL_COMPILER_API_DECLARATION':
			assert old['sha256']==source['sha256'] and old['path']==path and old['symbol']==symbol,'stale API source citation'
			assert sha(data[slice(*old['span'])])==old['span_sha256']
			source = old
		if document:
			matches = [s for s in document['symbols'] if s['source_location']['path']==path and s['source_location']['start']<=at<s['source_location']['end']]
			if matches:
				entry = min(matches,key=lambda s:s['source_location']['end']-s['source_location']['start'])
				span = entry['source_location']
				source.update(span=[span['start'],span['end']],span_sha256=sha(data[span['start']:span['end']]),span_kind='ACTUAL_COMPILER_API_DECLARATION',api_symbol_id=entry['id'],api_document_sha256=sha(api_spans.read_bytes()))
		rules.append(dict(id='R-'+identifier,chapter='docs/reference/'+chapter+'.md',sources=[source],positive=[dict(path='tests/books/examples.json',id=positive)],negative=[dict(path='tests/books/examples.json',id=negative)],coverage='DIRECT_DECLARATION_AND_DOMAIN_CONTROLS; full rule-specific cross-products require independent qualification'))
		# Prefer the actual rule-specific controls over unrelated representative
		# negatives. These existing recipes retain their source strings and native
		# O0/O2 observations independently; a textual link is not execution credit.
	for rule in rules:
		if rule['id']=='R-FORMAT-DOMAIN': rule['negative'] = [dict(path='tests/selfhost-expressive-language-27c/named.py',id='format-escaping-plan')]
		if rule['id']=='R-HANDLER-SCOPE': rule['negative'] = [dict(path='tests/selfhost-expressive-language-27c/named.py',id='format-unhandled-owned')]
		if rule['id']=='R-COUNTED-SIGNATURE':
			rule['negative'] = [dict(path='tests/selfhost-convergence-27d/c-client.py',id='null-empty')]
			rule['coverage'] = 'VALID_COUNTED_IMPORT_AND_EMPTY_DESCRIPTOR_CONTROL; malformed import-signature cross-products remain OPEN'
	inputs = sorted([*ROOT.glob('compiler/**/*.astra'),*ROOT.glob('lib/astra/**/*.astra')])
	mapped = {r['sources'][0]['path'] for r in rules}
	rows = []
	for path in inputs:
		name = str(path.relative_to(ROOT)); data = path.read_bytes()
		row = dict(path=name,bytes=len(data),sha256=sha(data),git_blob=hashlib.sha1(b'blob '+str(len(data)).encode()+b'\0'+data).hexdigest(),rule_ids=[r['id'] for r in rules if r['sources'][0]['path']==name],review='DIRECT_RULE_WITNESS' if name in mapped else 'INVENTORIED_NOT_EXHAUSTIVELY_REVIEWED')
		review = reviews.get(name)
		if review:
			assert review['reviewed_sha256']==row['sha256'],('source role review is stale; review changed source explicitly',name)
			row['role_review'] = review
		rows.append(row)
	model = json.loads((ROOT/'compiler/syntax/model.json').read_text())
	modern = (ROOT/'compiler/syntax/model.astra').read_bytes()
	enum = modern.split(b'enum SyntaxKind {',1)[1].split(b'\n}',1)[0]
	names = re.findall(rb'(?m)^\t([A-Za-z0-9_]+),?$',enum)
	families = [dict(name=name.decode(),abstract=model['nodes'].get(name.decode(),{}).get('abstract'),status='PARSER_REPRESENTATION_ONLY; NOT_EXHAUSTIVE_NATIVE_RULE_COVERAGE',legacy_source=model['nodes'].get(name.decode(),{}).get('path')) for name in names]
	for family in families:
		review = family_reviews.get(family['name'])
		if review:
			assert review['syntax_model_sha256']==sha(modern),'syntax family review is stale'
			family['grammar_review'] = review
	return {'rules.json':dict(format='astra-book-rules/1',edition='28-A2-R1',status='PARTIAL_EXHAUSTIVE_CONFORMANCE_REMAINS',rules=rules), 'inventory.json':dict(format='astra-book-source-inventory/1',edition='28-A2-R1',status='COMPLETE_FILE_AND_ROLE_INVENTORY_PARTIAL_SEMANTIC_CONFORMANCE',source_files=rows,syntax_model_sha256=sha(modern),syntax_families=families,method='Exact Git/content identities, authored role classifications pinned to reviewed bytes, direct declaration witnesses and actual SyntaxKind enum names. Role classification, constructor occurrence and parser acceptance do not establish exhaustive language-rule or native conformance.',role_classified_units=sum(bool(r.get('role_review')) for r in rows),baseline_28A2=dict(source_units=269,units_without_direct_rule_witness=231,syntax_families=100,engineering='PARTIAL'),unreviewed_source_units=sum(r['review']=='INVENTORIED_NOT_EXHAUSTIVELY_REVIEWED' for r in rows))}


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--check',action='store_true')
	p.add_argument('--api-spans',type=Path,help='Actual astrac doc JSON; upgrade only declarations it really exposes')
	a = p.parse_args()
	for name,value in products(a.api_spans).items():
		path = ROOT/'docs/books'/name
		data = (json.dumps(value,sort_keys=True,indent=2)+'\n').encode()
		if a.check: assert path.read_bytes() == data,path
		else:
			path.parent.mkdir(parents=True,exist_ok=True)
			path.write_bytes(data)
	print('Book source witnesses match; exhaustive semantic coverage remains PARTIAL')


if __name__ == '__main__':
	main()
