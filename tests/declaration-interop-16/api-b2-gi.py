#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
import ctypes,gc,sys,gi
from gi.repository import GLib
library=ctypes.CDLL(sys.argv[1]);library.lens16_retired_count.argtypes=[ctypes.c_int32];library.lens16_retired_count.restype=ctypes.c_uint32
gi.require_version('LensCatalog16','4.9')
from gi.repository import LensCatalog16
query_type=next(getattr(LensCatalog16,n) for n in dir(LensCatalog16) if n.startswith('Record') and hasattr(getattr(LensCatalog16,n),'astra_field_1_minimum'))
query=query_type.new();query.astra_field_2_cap=0;query.astra_field_1_minimum=0;query.astra_field_0_ceiling=10;query.astra_field_3_mask=7;query.astra_field_4_lowest=True
index=LensCatalog16.Catalog.new();assert index.props.requests==0 and index.props.enabled and index.props.bias==0 and index.props.description=='Record index λ' and index.props.last is None
seen=[];saved=[]
def completed(obj,requests,matched,score):
	assert obj is index
	seen.append((requests,matched,score))
def selected(obj,item,description):
	assert item.props.code==59 and item.props.score==1.75 and description.get_data()=='Record index λ'.encode()
	saved.extend([item,description]);obj.disconnect(connection)
index.connect('completed',completed);connection=index.connect('selected',selected)
ok,answer=index.try_lookup(query);assert ok and answer.astra_field_1_code==59 and answer.astra_field_0_score==1.75 and answer.astra_field_2_matches==3 and answer.astra_field_3_found
assert index.props.last is saved[0]
query.astra_field_1_minimum=20;query.astra_field_4_lowest=False
ok,found=index.try_resolve(query);assert ok and found.props.code==31 and found.props.score==5.5 and index.props.last is not found
index.props.enabled=False
try:index.try_resolve(query)
except GLib.Error as error:assert error.code==-1620
else:raise AssertionError('disabled query accepted')
index.props.enabled=True;index.props.bias=1.0;query.astra_field_1_minimum=0;query.astra_field_0_ceiling=3;query.astra_field_3_mask=3
ok,missing=index.try_resolve(query);assert ok and missing is None and index.props.last is None and seen==[(1,True,1.75),(2,True,5.5),(3,False,0.0)]
index=None;gc.collect();assert library.lens16_retired_count(1)==1 and library.lens16_retired_count(2)==1 and library.lens16_retired_count(3)==2
assert found.props.code==31 and saved[0].props.code==59 and saved[1].get_data()=='Record index λ'.encode();found=None;saved.clear();gc.collect();assert library.lens16_retired_count(3)==4
print('PASS frozen API B2 scanned GI records, properties, signals and independent result owners')
