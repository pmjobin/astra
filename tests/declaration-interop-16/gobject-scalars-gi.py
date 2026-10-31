#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independent PyGObject client of the scanned declaration-driven typelib."""
import ctypes
import gc
import sys
import gi
gi.require_version('Astra16','2.3')
from gi.repository import Astra16,GLib,GObject
library=ctypes.CDLL(sys.argv[1]);library.go16_destroyed_count.restype=ctypes.c_int32
assert library.go16_destroyed_count()==0
obj=Astra16.Session.new(7,True,1.5)
assert not obj.is_floating()
assert GObject.type_test_flags(Astra16.Session.__gtype__,GObject.TypeFlags.FINAL) and GObject.type_test_flags(Astra16.Item.__gtype__,GObject.TypeFlags.FINAL)
assert {p.name:p.value_type for p in obj.list_properties()}=={'count':GObject.TYPE_INT,'enabled':GObject.TYPE_BOOLEAN,'scale':GObject.TYPE_DOUBLE,'title':GLib.Bytes.__gtype__,'current':Astra16.Item.__gtype__}
assert obj.props.title.get_data()=='hé\0llo'.encode()
assert tuple(obj.props.current.try_code())==(True,41)
assert tuple(obj.try_read_current())==(True,41)
assert obj.props.count==7 and obj.props.enabled and obj.props.scale==1.5
notifications=[]
obj.connect('notify',lambda _object,spec:notifications.append(spec.name))
obj.props.count=19;obj.props.enabled=False;obj.props.scale=2.5
assert sorted(notifications)==['count','enabled','scale']
obj.props.count=19;obj.props.enabled=False;obj.props.scale=2.5
assert len(notifications)==3
assert tuple(obj.try_get_count())==(True,19)
assert tuple(obj.try_fold(-5000000000,4000000000,1.25,9))==(True,-999999990)
assert tuple(obj.try_choose(True))==(True,False)
assert tuple(obj.try_evaluate(4.0))==(True,10.0)
try:obj.try_evaluate(-1.0)
except GLib.Error as error:assert error.domain=='astra-foreign-domain-16' and error.code==-1600
else:raise AssertionError('native checked failure was lost')
assert not hasattr(obj,'try_native_only')
assert tuple(obj.try_glib_only(5))==(True,9)
callback_values=[]
def invert(value):callback_values.append(value);return not value
assert tuple(obj.try_visit(True,invert))==(True,False) and callback_values==[True]
assert tuple(obj.try_maybe_visit(True,None))==(True,True)
assert obj.try_deliver(1.25,lambda value:callback_values.append(value))
assert callback_values==[True,1.25]
assert tuple(obj.try_eval_refs(-5000000000,2.5,False))==(True,4.0,4000000000,-4999999995)
try:obj.try_eval_refs(-5000000000,2.5,True)
except GLib.Error as error:assert error.domain=='astra-foreign-domain-16' and error.code==-1600
else:raise AssertionError('reference failure was lost')
data=GLib.Bytes.new(bytes([1,0,254]))
assert tuple(obj.try_digest(data))==(True,255)
ok,owned=obj.try_snapshot(data)
assert ok and owned.get_data()==bytes([84,85,171])
assert tuple(obj.try_transform(data,[9,9,9,9]))==(True,bytes([2,1,255,9]),3)
assert tuple(obj.try_mutate([1,0,253]))==(True,bytes([3,2,255]),3)
assert tuple(obj.try_digest(None))==(True,0)
try:obj.try_transform(data,[9])
except GLib.Error:pass
else:raise AssertionError('invalid output bound published')
text=GLib.Bytes.new('hé\0llo'.encode())
assert tuple(obj.try_measure(text))==(True,7)
try:obj.try_measure(GLib.Bytes.new(bytes([0xff])))
except GLib.Error:pass
else:raise AssertionError('invalid UTF-8 accepted')
ok,owned=obj.try_counted_text()
assert ok and owned.get_data()=='hé\0llo'.encode()
assert tuple(obj.try_terminated())==(True,'café')
assert tuple(obj.try_terminated_length('café'))==(True,5)
try:obj.try_forbidden_nul()
except GLib.Error:pass
else:raise AssertionError('NUL text conversion truncated')
sample_type=next(getattr(Astra16,n) for n in dir(Astra16) if n.startswith('Record') and hasattr(getattr(Astra16,n),'astra_field_2_enabled'))
sample=sample_type.new()
sample.astra_field_0_count=2;sample.astra_field_1_scale=3.5;sample.astra_field_2_enabled=True;sample.astra_field_3_mask=4000000000;sample.astra_field_4_stamp=9000000001;sample.astra_field_5_weight=1.25
ok,record=obj.try_adjust(sample)
assert ok and (record.astra_field_0_count,record.astra_field_1_scale,record.astra_field_2_enabled,record.astra_field_3_mask,record.astra_field_4_stamp,record.astra_field_5_weight)==(21,8.75,False,4000000000,9000000002,1.75)
copy=record.copy();record.astra_field_0_count=99;assert copy.astra_field_0_count==21
pair_type=next(getattr(Astra16,n) for n in dir(Astra16) if n.startswith('Record') and hasattr(getattr(Astra16,n),'astra_field_0_first'))
pair=pair_type.new();pair.astra_field_0_first=1.25;pair.astra_field_1_second=-2
ok,result=obj.try_pair(pair);assert ok and result.astra_field_0_first==3.75 and result.astra_field_1_second==17
del sample,record,copy,pair,result
ok,item=obj.try_spawn(5);assert ok
assert tuple(obj.try_inspect(item))==(True,24)
ok,copy=obj.try_duplicate(item);assert ok and copy is item
ok,missing=obj.try_lookup(False,item);assert ok and missing is None
assert tuple(obj.try_optional(None))==(True,-7)
ok,copy=obj.try_relay(item);assert ok and copy is item
library.go16_item_destroyed_count.restype=ctypes.c_int32
assert library.go16_item_destroyed_count()==0
del item,copy;gc.collect();assert library.go16_item_destroyed_count()==1
del owned,data,text
survivor=obj.props.current
del obj;gc.collect();assert library.go16_destroyed_count()==1 and library.go16_item_destroyed_count()==1
assert tuple(survivor.try_code())==(True,41)
del survivor;gc.collect();assert library.go16_item_destroyed_count()==2
print('PASS declared GObject GI properties, checked errors and exact native retirement')
