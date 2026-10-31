#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Real relocated typelibs, properties, UTF-8 transfer and native errors."""
import ctypes
import gc
import importlib
import sys
import weakref
import gi

namespace = sys.argv[1]
gi.require_version(namespace, '1.0')
from gi.repository import GLib

module = importlib.import_module('gi.repository.' + namespace)
library = ctypes.CDLL('lib' + namespace.lower() + '.so')
stats = getattr(library, 'a' + namespace[5:] + '_stats')
stats.argtypes = [ctypes.c_int32]
stats.restype = ctypes.c_int32
assert stats(0) == stats(1) == 0
kind = {'Astra126': 'Settings', 'Astra127': 'Diagnostic', 'Astra128': 'Publisher'}[namespace]
object = getattr(module, kind).new(0)
events = []
object.connect('changed', lambda self, value: events.append(value))
if namespace == 'Astra127':
	first = object.report(0)
	assert first == 'info[0]: ready 🖤' and stats(4) == 0
	object.props.value = 1
	second = object.report(0)
	assert second == 'warning[1]: retry café' and first == 'info[0]: ready 🖤'
	try:
		object.report(99)
		raise AssertionError('native checked exception was not mapped')
	except GLib.Error as error:
		assert error.code == 6 and error.domain == 'astra127_diagnostic-error'
	object.props.value = 2
	assert object.report(0) == 'error[2]: invalid packet'
	assert events == [1, 2] and stats(4) == 0 and stats(5) > 60
	object.run_dispose()
	try:
		object.report(0)
		raise AssertionError('disposed diagnostic was readable')
	except GLib.Error as error:
		assert error.code == 3
	expected = (2, 2)
elif namespace == 'Astra126':
	object.props.value = 3
	object.props.value = 7
	object.props.value = 9
	assert object.props.value == 7 and events == [3, 7]
	expected = (7, 3)
else:
	object.props.value = 7
	object.props.value = 9
	assert object.props.value == 240 and events == [7, 240]
	expected = (240, 2)
reference = weakref.ref(object)
del object
gc.collect()
assert reference() is None and stats(0) == stats(1) == 1
assert (stats(2), stats(3)) == expected
print('PASS ' + namespace + ' relocated GIR/typelib: real property signals ownership native-finalization' +
	(' Astra-owned UTF8 transfer-full copy native-error restored' if namespace == 'Astra127' else ''))
