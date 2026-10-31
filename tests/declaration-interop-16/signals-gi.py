# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
import ctypes,gc,sys
import gi
gi.require_version('Events16','1.0')
from gi.repository import Events16,GLib,GObject
library=ctypes.CDLL(sys.argv[1]);library.signals16_retired_count.restype=ctypes.c_uint
library.signals16_item_retired_count.restype=ctypes.c_uint
session=Events16.Session.new(7);events=[];copies=[]
def described(obj,text,payload,record):
	assert obj is session and text.get_data()==b'a\0b' and payload.get_data()==bytes([3,0,254])
	fields=record.__class__.__info__.get_fields();values=[field.get_value(record) for field in fields]
	assert values==[True,3.5,29];copies.extend([text,payload,record.copy()]);events.append('described')
def updated(obj,count,committed,weight):
	assert obj is session and obj.props.count==count==19 and committed is True and weight==2.5
	obj.disconnect(connection);events.append('updated')
session.connect('described',described);connection=session.connect('updated',updated)
def selected(obj,item):
	assert obj is session and isinstance(item,Events16.Item) and item.props.code==37
	copies.append(item);events.append('selected')
session.connect('selected',selected);assert session.try_choose_item(37);assert library.signals16_item_retired_count()==0
assert session.try_describe(GLib.Bytes.new(b'a\0b'),GLib.Bytes.new(bytes([3,0,254])))
assert session.try_update(19);assert session.try_update(23);assert events==['selected','described','updated']
assert copies[1].get_data()==b'a\0b';assert library.signals16_retired_count()==0
del session;gc.collect();assert library.signals16_retired_count()==1
copies.clear();gc.collect()
assert library.signals16_item_retired_count()==1
print('PASS scanned GI typed signals, disconnection, retained byte/boxed copies and native retirement')
