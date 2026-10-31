# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Qualify actual declaration-driven generic programs at public O0/O1/O2."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import re
import subprocess
import tempfile
import time


ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
CASES = ['runtime-composition', 'owned-closure-async', 'namespaced-text', 'interface-branches', 'nested-generic-Class-record', 'generic-record-async', 'scoped-code-inspection', 'associative-map-inspection', 'direct-payload', 'two-parameters', 'independent-field', 'open-class-members', 'open-class-lazy', 'open-class-owning-members', 'open-class-generic-methods', 'open-class-method-owners', 'open-class-method-resource-results', 'method-result-origins', 'record-method-result-origins',
	'three-parameters', 'owned-substitution', 'copied-record', 'copied-property', 'closed-record-class-fields',
	'resource-payload', 'owning-record-payload', 'owning-buffer-record',
	'nested-record-producer', 'nested-buffer-producer', 'method-tuples',
	'method-ownership', 'substituted-constraints', 'ownable-constraint',
	'deferred-instantiation', 'deferred-lifetimes', 'nested-field-observation',
	'deferred-field-chains', 'constrained-declarations', 'multiple-slot-fields',
	'collection-helpers', 'ownable-slots', 'closed-closure-environment',
	'closed-generic-dispatch', 'owned-generic-async', 'copied-record-comparator',
	'generic-comparator-field', 'associative-map', 'associative-owned-map',
	'indexed-method-inspection', 'associative-copy-map', 'lexical-construction', 'lexical-bag',
	'record-projections', 'temporary-record-member', 'open-record-formals',
	'constructed-formal', 'nested-struct-formal', 'void-struct-formal',
	'historical-record-projection', 'historical-struct-property', 'closed-class-owner-transport',
	'closed-class-bag-transport', 'closed-empty-class', 'historical-empty-generic-class', 'historical-generic-bag-borrow', 'owning-record-view', 'owning-resource-view', 'owning-buffer-view', 'buffer-index-owner', 'readonly-buffer-view', 'borrowed-record-parameter', 'borrowed-buffer-parameter', 'borrowed-member-parameter', 'borrowed-record-leaves', 'borrowed-record-getter', 'readonly-record-parameter', 'borrowed-function-channel', 'borrowed-closure-channel', 'copied-record-closure', 'closed-record-callables', 'closed-record-type-only', 'owned-callable-resources', 'copied-callable-fields', 'owned-callable-classes', 'owning-record-callables', 'owned-callable-results', 'owned-callable-class-results', 'copied-callable-record-results', 'owning-callable-record-results', 'borrowed-callable-records', 'historical-owner-declaration', 'populated-owner-declaration', 'historical-consuming-closure', 'historical-owning-record-callable', 'symbolic-copied-callables', 'symbolic-borrowed-callables', 'symbolic-consuming-callables']


CASES += ['copied-record-slot-inspection', 'parenthesized-owner-results', 'generic-caller-result-roots', 'generic-inferred-locals', 'generic-owner-fresh-results', 'generic-owner-local-chains', 'dependent-fixed-Class-results', 'member-fixed-Class-factories', 'member-wrapper-result-origins', 'historical-concrete-result-chain', 'exercised-concrete-result-chain', 'class-signature-origins', 'generic-storage-requirements', 'symbolic-owned-callable-results', 'generic-class-result-origins',
	'historical-generic-owner-host', 'historical-unqualified-owner-field', 'open-class-owned-formals']
CASES += ['exchange-expansion-recovery']
CASES += ['nonnull-result-origins', 'historical-lazy-declaration', 'historical-lazy-unused']


def sha(path):
	return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument('compiler', type=Path)
	parser.add_argument('output', type=Path)
	parser.add_argument('--case', choices=CASES, action='append')
	args = parser.parse_args()
	compiler = args.compiler.resolve(strict=True)
	output = args.output.resolve()
	if output.is_relative_to(ROOT):
		parser.error('compiled products must remain outside the source repository')
	output.mkdir(parents=True, exist_ok=True)
	run_dir = Path(tempfile.mkdtemp(prefix='declared-', dir=output))
	cases = args.case or CASES
	receipt = {
		'format': 'astra-m15-declared-execution/1',
		'compiler': str(compiler), 'compiler_sha256': sha(compiler),
		'recipe_sha256': sha(Path(__file__).resolve()),
		'sources': {case: sha(HERE / (case + '.astra')) for case in cases},
		'checks': [], 'products': {},
	}

	def run(argv, memory=False, dump=False, stdout=b'', expected_exit=0):
		argv = list(map(str, argv))
		started = time.perf_counter()
		result = subprocess.run(argv, cwd=ROOT, capture_output=True,
			timeout=90, env=dict(os.environ, CCACHE_DISABLE='1',
			PYTHONDONTWRITEBYTECODE='1'))
		passed = result.returncode == expected_exit
		if memory:
			passed &= all(text in result.stderr for text in [b'ERROR SUMMARY: 0 errors',
				b'in use at exit: 0 bytes in 0 blocks', b'(suppressed: 0 from 0)'])
		else:
			passed &= not result.stderr
		if not dump:
			passed &= result.stdout == stdout
		receipt['checks'].append({
			'argv': argv, 'cwd': str(ROOT), 'exit': result.returncode, 'expected_exit': expected_exit,
			'elapsed_seconds': time.perf_counter() - started,
			'stdout_sha256': hashlib.sha256(result.stdout).hexdigest(),
			'stdout_bytes': len(result.stdout),
			'stderr': result.stderr.decode(errors='replace'), 'passed': bool(passed),
		})
		if memory:
			usage = re.search(rb'total heap usage: ([\d,]+) allocs, ([\d,]+) frees, ([\d,]+) bytes allocated', result.stderr)
			if usage:
				receipt['checks'][-1]['target_heap_usage'] = dict(zip(
					['allocations', 'frees', 'bytes_allocated'],
					[int(value.replace(b',', b'')) for value in usage.groups()]))
		(run_dir / 'checks.json').write_text(json.dumps(receipt, indent='\t') + '\n')
		if not passed:
			raise RuntimeError(json.dumps(receipt['checks'][-1], indent=2))

	observer = run_dir / 'resource-observer.o'
	observed_cases = ['resource-payload', 'owning-record-payload', 'owning-buffer-record', 'open-class-lazy', 'open-class-owning-members', 'open-class-method-owners', 'open-class-method-resource-results', 'method-result-origins', 'record-method-result-origins',
		'nested-buffer-producer', 'method-ownership', 'ownable-constraint',
		'deferred-lifetimes', 'nested-field-observation', 'multiple-slot-fields',
		'collection-helpers', 'ownable-slots', 'closed-closure-environment',
		'closed-generic-dispatch', 'owned-generic-async', 'owned-closure-async', 'associative-owned-map', 'lexical-construction', 'lexical-bag', 'closed-class-owner-transport', 'closed-class-bag-transport', 'owning-record-view', 'owning-resource-view', 'owning-buffer-view', 'readonly-buffer-view', 'borrowed-record-parameter', 'borrowed-buffer-parameter', 'borrowed-member-parameter', 'borrowed-record-leaves', 'borrowed-record-getter', 'readonly-record-parameter', 'borrowed-function-channel', 'borrowed-closure-channel', 'copied-record-closure', 'closed-record-callables', 'closed-record-type-only', 'owned-callable-resources', 'copied-callable-fields', 'owned-callable-classes', 'owning-record-callables', 'owned-callable-results', 'owned-callable-class-results', 'copied-callable-record-results', 'owning-callable-record-results', 'borrowed-callable-records', 'populated-owner-declaration', 'symbolic-borrowed-callables', 'symbolic-consuming-callables']
	observed_cases.append('symbolic-owned-callable-results')
	observed_cases.append('generic-class-result-origins')
	observed_cases.append('open-class-owned-formals')
	observed_cases.append('generic-storage-requirements')
	observed_cases.append('class-signature-origins')
	observed_cases.append('member-wrapper-result-origins')
	observed_cases.append('member-fixed-Class-factories')
	observed_cases.append('dependent-fixed-Class-results')
	observed_cases.append('generic-owner-local-chains')
	observed_cases.append('generic-owner-fresh-results')
	observed_cases.append('generic-inferred-locals')
	observed_cases.append('parenthesized-owner-results')
	observed_cases.append('associative-map-inspection')
	if any(case in observed_cases for case in cases):
		companion = ROOT / 'tests/own-field/companion.c'
		vapi = ROOT / 'tests/own-field/fixtures/resources.vapi'
		receipt['sources'].update({str(path.relative_to(ROOT)): sha(path)
			for path in [companion, vapi]})
		run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-O2',
			'-c', companion, '-o', observer])
		receipt['products'][str(observer)] = sha(observer)
	for case in cases:
		source = HERE / (case + '.astra')
		native_exit = {'historical-concrete-result-chain': 42, 'exercised-concrete-result-chain': 42, 'temporary-record-member': 1, 'nested-struct-formal': 1, 'historical-empty-generic-class': 42, 'historical-owner-declaration': 42,
			'historical-generic-owner-host': 42, 'historical-unqualified-owner-field': 42}.get(case, 0)
		observed = case in observed_cases
		imports = ['--vapi', vapi] if observed else []
		libraries = [ROOT / 'lib/astra/base/errors.astra'] if case in ['runtime-composition', 'owned-closure-async', 'generic-record-async', 'generic-storage-requirements', 'open-class-method-owners', 'open-class-method-resource-results', 'nested-buffer-producer', 'ownable-slots', 'closed-closure-environment', 'owned-generic-async', 'borrowed-closure-channel', 'copied-record-closure', 'closed-record-callables', 'owned-callable-resources', 'copied-callable-fields', 'owned-callable-classes', 'owning-record-callables', 'owned-callable-results', 'owned-callable-class-results', 'copied-callable-record-results', 'owning-callable-record-results', 'borrowed-callable-records', 'symbolic-consuming-callables'] else []
		if case == 'runtime-composition':
			libraries.append(HERE / 'runtime-composition-provider.astra')
		if case == 'namespaced-text':
			libraries.append(HERE / 'namespaced-text-provider.astra')
		if case in ['collection-helpers', 'lexical-bag', 'closed-class-bag-transport', 'historical-generic-bag-borrow']:
			libraries.append(ROOT / 'lib/astra/collections/bag.astra')
		if case in ['associative-map', 'associative-owned-map', 'associative-copy-map', 'associative-map-inspection']:
			libraries.append(ROOT / 'lib/astra/collections/map.astra')
		if case in ['associative-owned-map', 'associative-copy-map', 'associative-map-inspection']:
			libraries += [ROOT / 'lib/astra/collections/box.astra', ROOT / 'lib/astra/collections/cache.astra']
		if case in ['owning-resource-view', 'readonly-buffer-view', 'borrowed-buffer-parameter', 'borrowed-record-getter', 'readonly-record-parameter', 'borrowed-function-channel', 'borrowed-closure-channel']:
			libraries.append(ROOT / 'lib/astra/collections/box.astra')
		if case == 'borrowed-callable-records':
			libraries.append(ROOT / 'lib/astra/collections/box.astra')
		if case in ['symbolic-owned-callable-results', 'generic-class-result-origins']:
			libraries.append(ROOT / 'lib/astra/base/errors.astra')
		if case in ['runtime-composition', 'owned-generic-async', 'generic-record-async', 'owned-closure-async']:
			libraries.append(ROOT / 'lib/astra/async/virtual.astra')
			for support in ['lib/runtime/async/virtual.c', 'lib/runtime/async/virtual.h', 'lib/runtime/async/provider.h']:
				receipt['sources'][support] = sha(ROOT / support)
		for library in libraries:
			receipt['sources'][str(library.relative_to(ROOT))] = sha(library)
		link = ['--link-object', observer] if observed else []
		if case in ['runtime-composition', 'owned-generic-async', 'generic-record-async', 'owned-closure-async']:
			provider = compiler.parent / 'lib/astra/async-virtual.o'
			assert provider.is_file(), 'build the nominated virtual executor support object'
			link += ['--link-object', provider]
			receipt['products'][str(provider)] = sha(provider)
		trace = {'owned-closure-async': b'+241\nD2300\n-241\n+242\nD2301\nD2300\n-242\n'
			b'+243\nD2301\nD2302\nD2310\nD2310\nD2311\nD2303\nD2310\nD2300\n-243\n'
			b'+244\nD2301\nD2302\nD2310\nD2310\nD2311\nD2303\nD2310\nD2300\n-244\nD2304\n', 'associative-map-inspection': b'+31\n+32\n-32\n-31\n', 'generic-class-result-origins':
			b'+101\n+102\n+103\n+104\n+105\n+106\n+107\n-106\n+108\n+109\n'
			b'D1400\n-109\nD1400\n-108\nD1400\n-107\nD1400\n-105\nD1400\n-104\nD1400\n-103\nD1400\n-102\nD1400\n-101\n'
			b'+111\n+112\n+113\n+114\nD1402\nD1400\n-114\nD1403\n'
			b'+115\n+116\nD1402\nD1400\n-116\nD1404\n+117\nD1400\n-115\n'
			b'D1405\nD1400\n-117\nD1401\n-113\nD1400\n-112\nD1401\n-111\n',
			'symbolic-owned-callable-results': b'+201\n+202\n+203\n+204\n+205\n+206\n+207\n+208\nD1101\nD1102\n+209\n-209\n-208\n-207\n-206\n-205\n-204\n-203\n-202\n-201\n'
			b'+210\n+211\n+214\n+212\nD1103\n-212\nD1104\n+213\n-213\n-214\n-211\n-210\n',
			'closed-class-owner-transport': b'D771\nD701\nD772\nD702\n+151\n+152\nD773\nD704\nD703\n-152\n-151\nD774\nD705\nD775\n',
			'open-class-lazy': b'+241\n+242\nD241\nD242\n+243\nD243\n+244\nD244\n-244\n-243\n-242\n-241\n',
			'open-class-owning-members': b'+221\n+222\n-221\n+223\n+224\n-223\n+225\n-225\n+226\n-226\n-224\n-222\n',
			'record-method-result-origins': b'+241\n+242\n-242\n-241\n',
			'method-result-origins': b'+230\n+231\n-230\n+232\n+233\n-232\n-233\n-231\n',
			'open-class-method-resource-results': b'+211\n+212\n+213\n+214\n-213\n+215\n+216\nD903\nD904\n+217\n-217\nD905\n+218\n-218\n-216\n-215\n-214\n-212\n-211\n',
			'open-class-method-owners': b'+201\n-201\n+202\n-202\n+203\n-203\n+204\n-204\n+205\n-205\n+206\nD901\nD902\n-206\n',
			'closed-class-bag-transport': b'D776\nD712\nD711\n',
			'lexical-bag': b'D501\nD502\nD401\nD402\nD503\nD403\n',
			'lexical-construction': b'+141\n+142\n+143\n+144\nD202\nD207\nD206\nD205\nD300\n-144\n-143\nD204\n-142\n-141\nD203\nD201\n',
			'resource-payload': b'+41\n+42\n-42\n-41\n',
			'owning-record-payload': b'D23\nD19\nD102\nD47\nD37\n',
			'owning-record-view': b'D9\nD23\nD19\nD802\nD47\nD37\n',
			'owning-resource-view': b'+161\n+162\n-162\n-161\n',
			'owning-buffer-view': b'+171\n+172\n-171\nD902\n-172\n',
			'readonly-buffer-view': b'+181\n-181\n',
			'borrowed-record-parameter': b'D192\nD191\n',
			'borrowed-buffer-parameter': b'+191\n-191\n',
			'borrowed-member-parameter': b'+192\n+193\n-193\nD194\n-192\nD193\n',
			'borrowed-record-leaves': b'+201\n+202\n-202\n-201\nD19\n',
			'borrowed-record-getter': b'+201\n+202\nD5\n-202\n-201\nD19\n',
			'readonly-record-parameter': b'+181\n-181\n',
			'borrowed-callable-records': b'+201\n+202\n+211\n+212\n+203\n+204\n+205\nD931\nD932\nD930\n-205\nD930\n-204\n-202\n-201\nD201\n-203\n-212\n-211\nD211\n',
			'owning-callable-record-results': b'+171\n+172\n+173\n+174\n+175\n+176\n-172\n-171\nD171\n-174\n-173\nD173\n-176\n-175\nD175\n+179\n+180\n+181\n+182\n+183\n+184\nD891\n-184\n-183\nD183\nD892\n+185\n+186\n-181\n-180\nD180\nD890\n-182\n-186\n-185\nD185\nD890\n-179\n',
			'copied-callable-record-results': b'+161\n+162\nD881\nD882\nD880\n-162\nD880\n-161\n',
			'owned-callable-class-results': b'+231\n+232\n+239\nD840\n-231\nD840\n-239\nD840\n-232\n+233\n+234\n+235\n+236\nD851\nD840\n-236\nD852\n+237\nD840\n-237\n+238\nD840\n-238\nD850\n-235\nD840\n-234\nD850\n-233\n',
			'owned-callable-results': b'+211\n+212\n+213\n-213\n-212\n-211\n+219\n+220\n-219\n+221\n-220\n+222\n-221\n+223\n-223\n+224\n-222\n-224\n+214\n+215\n+218\n+216\nD811\n-216\nD812\n+216\nD811\n-216\nD813\n+217\n-217\nD810\n-218\n-215\nD810\n-214\n',
			'owning-record-callables': b'+231\n+232\n-232\n-231\nD231\n+233\n+234\nD761\nD763\n-234\n-233\nD233\n+235\n+236\n-236\n-235\nD235\n+237\n+238\nD762\n-238\n-237\nD237\nD764\n+239\n+240\n-240\n-239\nD239\n+244\n+241\n+242\n+243\n-243\n-242\n-241\nD241\n-244\nD760\nD760\n',
			'symbolic-consuming-callables': b'+171\n-171\n+172\n-172\nD1001\n+173\nD1002\n-173\nD1003\n+174\nD990\nD991\n-174\n+175\n-175\nD1004\nD1005\n',
			'symbolic-borrowed-callables': b'+241\n+242\n-242\nD962\n-241\nD961\n',
			'populated-owner-declaration': b'+250\n-250\nD751\n',
			'open-class-owned-formals': b'D1501\nD1502\nD1503\n+201\nD1504\n-201\nD1506\nD1505\n',
			'member-fixed-Class-factories': b'+221\nD1901\n-221\n+222\nD1902\n-222\n+223\nD1910\n-223\n+224\nD1910\n-224\n',
			'generic-owner-local-chains': b'+241\n-241\n+242\n+243\n-243\n-242\n+244\nD2101\n-244\n+245\nD2102\n-245\n+246\n-246\n+247\n-247\n',
			'parenthesized-owner-results': b'+235\n-235\n+236\nD2301\n-236\n+237\nD2302\n-237\n',
			'generic-inferred-locals': b'+231\n-231\n+232\n-232\n',
			'generic-owner-fresh-results': b'+251\n-251\n+252\n-252\n+253\nD2201\n-253\n+254\nD2202\n-254\n+255\nD2203\n-255\n+240\nD2204\n-240\n',
			'dependent-fixed-Class-results': b'+231\nD2003\n-231\n+232\nD2004\n-232\n+233\nD2005\n-233\n+234\nD2006\n-234\n+235\nD2008\n-235\n+236\nD2008\n-236\n+237\nD2010\n-237\n+238\nD2010\n-238\n',
			'member-wrapper-result-origins': b'+211\nD1803\n-211\n+212\n+213\nD1804\n-212\nD1801\n-213\n+214\n+215\nD1805\n-214\nD1802\n-215\n',
			'class-signature-origins': b'+201\n+202\nD1702\n-202\nD1701\n-201\n+203\nD1703\n-203\n+204\nD1704\n-204\nD1711\nD1710\n+205\n+206\nD1713\n-206\nD1712\n-205\n+207\nD1721\nD1720\n-207\n',
			'generic-storage-requirements': b''.join(b'D%d\n' % serial for serial in range(1601, 1617)) + b'D1618\nD1619\nD1617\n',
			'owned-callable-classes': b'+251\nD710\n-251\n+252\nD711\nD712\nD710\n-252\n+253\nD710\n-253\n+254\nD713\nD710\n-254\nD714\n+255\nD710\n-255\nD720\nD720\n',
			'copied-callable-fields': b'+240\n-240\n',
			'owned-callable-resources': b'+241\n+242\n-242\n+243\nD650\nD651\n-243\n+249\n-249\n-241\n+244\n+245\n-245\n+246\n+247\nD641\n-247\nD642\n+248\n-248\nD640\n-246\nD640\n-244\n',
			'borrowed-function-channel': b'+211\n+212\n+213\n-213\nD31\nD19\n-212\n-211\nD29\nD23\n',
			'copied-record-closure': b'+232\n+231\n+233\nD610\nD611\nD600\n-233\nD600\n-231\n-232\n',
			'closed-record-callables': b'+232\n+231\n+233\nD610\nD611\nD600\n-233\nD600\n-231\n-232\n',
			'borrowed-closure-channel': b'+221\nD530\nD531\n+222\n+223\n+224\nD521\nD522\nD500\n-224\n-223\nD31\nD500\n-222\n-221\nD29\nD19\n',
			'owning-buffer-record': b'+51\n+52\n-51\nD102\n-52\n',
			'nested-buffer-producer': b'+61\n-61\nD61\n+62\nD100\n-62\n',
			'method-ownership': b'+71\n-71\nD47\nD31\n',
			'ownable-constraint': b'+81\nD37\n-81\n',
			'deferred-lifetimes': b'+11\n+12\n+13\n+14\nD51\n-14\n+15\nD115\n-15\nD42\nD41\nD113\n-13\nD32\nD31\n-12\nD21\n-11\n',
			'nested-field-observation': b'+91\nD30\nD20\nD10\nD191\n-91\n',
			'multiple-slot-fields': b'+95\n+96\nD40\nD13\nD196\n-96\nD12\nD195\n-95\n',
			'collection-helpers': b'D10\nD20\nD301\nD30\n',
			'ownable-slots': b'+97\nD42\n-97\nD53\n',
			'closed-closure-environment': b'+98\n+99\nD42\nD240\n-99\n-98\nD220\n',
			'closed-generic-dispatch': b'D70\nD40\nD70\nD40\n',
			'owned-generic-async': b'+101\n+102\nD142\n-102\n-101\n+103\n+104\nD10\nD142\n-104\n-103\n+105\n+106\nD10\nD20\nD142\n-106\n-105\n+107\n+108\nD10\nD142\n-108\n-107\n',
			'associative-owned-map': b'+121\n+122\n+123\n+124\n+125\n+126\n+127\n+128\n+129\n+130\n+131\n+132\nD220\n-126\n-125\nD200\n-122\n-121\nD240\n-130\n-129\nD230\n-128\n-127\nD299\n-132\n-131\nD210\n-124\n-123\n'}.get(case, b'')
		for stage in ['--format', '--dump-semantics', '--dump-core',
			'--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-llvm', '--check']:
			# These historical inputs retain their exact original bytes, including formatting.
			preserved_format = stage == '--format' and case in [
				'historical-consuming-closure', 'historical-owning-record-callable', 'historical-concrete-result-chain']
			run([compiler, stage, *([] if preserved_format else ['--check'] if stage == '--format' else imports), source,
				*([] if stage == '--format' else libraries)],
				dump=preserved_format or stage not in ['--format', '--check'])
		for level in ['-O0', '-O1', '-O2']:
			binary = run_dir / (case + level)
			run([compiler, level, *imports, source, *libraries, *link, '-o', binary])
			receipt['products'][str(binary)] = sha(binary)
			receipt.setdefault('product_bytes', {})[str(binary)] = binary.stat().st_size
			run([binary], stdout=trace, expected_exit=native_exit)
			run(['valgrind', '--default-suppressions=no', '--leak-check=full',
				'--show-leak-kinds=all', '--errors-for-leak-kinds=all',
				'--error-exitcode=99', binary], memory=True, stdout=trace, expected_exit=native_exit)
	assert sha(compiler) == receipt['compiler_sha256'], 'compiler changed during qualification'
	assert sha(Path(__file__).resolve()) == receipt['recipe_sha256'], 'recipe changed during qualification'
	for case in cases:
		assert sha(HERE / (case + '.astra')) == receipt['sources'][case], 'source changed during qualification'
	for source, digest in receipt['sources'].items():
		if '/' in source:
			assert sha(ROOT / source) == digest, 'support source changed during qualification'
	receipt['all_passed'] = True
	(run_dir / 'checks.json').write_text(json.dumps(receipt, indent='\t') + '\n')
	print(run_dir / 'checks.json')


if __name__ == '__main__':
	main()
