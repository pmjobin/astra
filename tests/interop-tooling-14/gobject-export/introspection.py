#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independent installed typelib consumer; never reads Astra native layouts."""
import ctypes
import gc
import weakref
import gi

gi.require_version('Astra14', '1.0')
from gi.repository import Astra14, GObject, GLib

library = ctypes.CDLL('libastra14.so')
library.astra14_stats.argtypes = [ctypes.c_int32]
library.astra14_stats.restype = ctypes.c_int32
stats = library.astra14_stats
assert stats(0) == stats(1) == 0
assert not hasattr(Astra14.Counter, 'as_gobject')
obj = Astra14.Counter.new(40)
assert isinstance(obj, GObject.Object) and not obj.is_floating() and obj.props.value == 40
events = []
notifications = []
obj.connect('changed', lambda self, value: events.append(value))
obj.connect('notify::value', lambda self, spec: notifications.append(spec.name))
obj.props.value = 42
assert obj.try_set_value(27)
assert obj.try_get_value() == (True, 27)
obj.props.value = 27
assert obj.props.value == 27 and events == [42, 27] and notifications == ['value', 'value']
assert stats(0) == 1 and stats(1) == 0
obj.run_dispose()
try:
	obj.try_get_value()
	raise AssertionError('disposed object was readable')
except GLib.Error as error:
	assert error.code == 3 and error.domain == 'astra14_counter-error'
reference = weakref.ref(obj)
del obj
gc.collect()
assert reference() is None and stats(1) == 1 and stats(3) == 27
direct = GObject.new(Astra14.Counter, value=31)
assert direct.props.value == 31 and stats(0) == 2 and stats(2) == 0
del direct
gc.collect()
assert stats(1) == 2 and stats(3) == 31
print('PASS installed GIR/typelib Python client: real GType property signal error direct construction and exact native finalization')
