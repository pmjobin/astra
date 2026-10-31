#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
import ctypes,gc,sys,gi
from gi.repository import GLib
library=ctypes.CDLL(sys.argv[1]);library.orbit16_retired_count.argtypes=[ctypes.c_int32];library.orbit16_retired_count.restype=ctypes.c_uint32
gi.require_version('OrbitTable16','5.3')
from gi.repository import OrbitTable16
query_type=next(getattr(OrbitTable16,n) for n in dir(OrbitTable16) if n.startswith('Record') and hasattr(getattr(OrbitTable16,n),'astra_field_2_minimum'))
query=query_type.new();query.astra_field_0_boost=0;query.astra_field_3_cap=0;query.astra_field_2_minimum=0;query.astra_field_1_ceiling=10;query.astra_field_4_mask=7;query.astra_field_5_lowest=True
index=OrbitTable16.Directory.new();assert index.props.requests==0 and index.props.enabled and index.props.bias==0 and index.props.description=='Stream query λ' and index.props.last is None
seen=[];saved=[]
def completed(obj,requests,matched,score):
	assert obj is index
	seen.append((requests,matched,score))
def selected(obj,item,description):
	assert item.props.code==83 and item.props.score==0.5 and description.get_data()=='Stream query λ'.encode()
	saved.extend([item,description]);obj.disconnect(connection)
index.connect('completed',completed);connection=index.connect('selected',selected)
ok,answer=index.try_scan(query);assert ok and answer.astra_field_1_code==83 and answer.astra_field_0_score==0.5 and answer.astra_field_2_matches==3 and answer.astra_field_3_found
assert index.props.last is saved[0]
query.astra_field_2_minimum=30;query.astra_field_5_lowest=False
ok,found=index.try_entry_for(query);assert ok and found.props.code==47 and found.props.score==6.25 and index.props.last is not found
index.props.enabled=False
try:index.try_entry_for(query)
except GLib.Error as error:assert error.code==-1620
else:raise AssertionError('disabled query accepted')
index.props.enabled=True;index.props.bias=1.0;query.astra_field_2_minimum=0;query.astra_field_1_ceiling=3;query.astra_field_4_mask=3
ok,missing=index.try_entry_for(query);assert ok and missing is None and index.props.last is None and seen==[(1,True,0.5),(2,True,6.25),(3,False,0.0)]
index=None;gc.collect();assert library.orbit16_retired_count(1)==1 and library.orbit16_retired_count(2)==1 and library.orbit16_retired_count(3)==2
assert found.props.code==47 and saved[0].props.code==83 and saved[1].get_data()=='Stream query λ'.encode();found=None;saved.clear();gc.collect();assert library.orbit16_retired_count(3)==4
print('PASS frozen API B3 scanned GI records, properties, signals and independent result owners')
