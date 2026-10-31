#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
import ctypes,gc,sys,gi
from gi.repository import GLib
library=ctypes.CDLL(sys.argv[1]);library.query16_retired_count.argtypes=[ctypes.c_int32];library.query16_retired_count.restype=ctypes.c_uint32
gi.require_version('RecordQuery16','3.4')
from gi.repository import RecordQuery16
query_type=next(getattr(RecordQuery16,n) for n in dir(RecordQuery16) if n.startswith('Record') and hasattr(getattr(RecordQuery16,n),'astra_field_0_minimum'))
query=query_type.new();query.astra_field_0_minimum=0;query.astra_field_1_ceiling=10;query.astra_field_2_mask=7;query.astra_field_3_lowest=True
index=RecordQuery16.Index.new();assert index.props.requests==0 and index.props.enabled and index.props.bias==0 and index.props.description=='Record index λ' and index.props.last is None
seen=[];saved=[]
def completed(obj,requests,matched,score):
	assert obj is index
	seen.append((requests,matched,score))
def selected(obj,item,description):
	assert item.props.code==59 and item.props.score==1.75 and description.get_data()=='Record index λ'.encode()
	saved.extend([item,description]);obj.disconnect(connection)
index.connect('completed',completed);connection=index.connect('selected',selected)
ok,answer=index.try_search(query);assert ok and answer.astra_field_0_code==59 and answer.astra_field_1_score==1.75 and answer.astra_field_2_matches==3 and answer.astra_field_3_found
assert index.props.last is saved[0]
query.astra_field_0_minimum=20;query.astra_field_3_lowest=False
ok,found=index.try_find(query);assert ok and found.props.code==31 and found.props.score==5.5 and index.props.last is not found
index.props.enabled=False
try:index.try_find(query)
except GLib.Error as error:assert error.code==-1620
else:raise AssertionError('disabled query accepted')
index.props.enabled=True;index.props.bias=1.0;query.astra_field_0_minimum=0;query.astra_field_1_ceiling=3;query.astra_field_2_mask=3
ok,missing=index.try_find(query);assert ok and missing is None and index.props.last is None and seen==[(1,True,1.75),(2,True,5.5),(3,False,0.0)]
index=None;gc.collect();assert library.query16_retired_count(1)==1 and library.query16_retired_count(2)==1 and library.query16_retired_count(3)==2
assert found.props.code==31 and saved[0].props.code==59 and saved[1].get_data()=='Record index λ'.encode();found=None;saved.clear();gc.collect();assert library.query16_retired_count(3)==4
print('PASS frozen API B scanned GI records, properties, signals and independent result owners')
