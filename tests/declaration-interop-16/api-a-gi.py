#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
import ctypes,gc,sys,gi
from gi.repository import GLib
library=ctypes.CDLL(sys.argv[1]);library.byte16_retired_count.argtypes=[ctypes.c_int32];library.byte16_retired_count.restype=ctypes.c_uint32
gi.require_version('ByteService16','2.1')
from gi.repository import ByteService16
configuration_type=next(getattr(ByteService16,n) for n in dir(ByteService16) if n.startswith('Record') and hasattr(getattr(ByteService16,n),'astra_field_0_mask'))
configuration=configuration_type.new();configuration.astra_field_0_mask=85;configuration.astra_field_1_rotate=True;configuration.astra_field_2_weight=2.5
session=ByteService16.Session.new(configuration)
assert session.props.revision==0 and session.props.enabled and session.props.weight==2.5 and session.props.label=='Byte transform é' and session.props.current is None
seen=[];retained=[]
def processed(obj,revision,committed,weight):
	assert obj is session and revision==1 and committed and weight==2.5
	seen.append('processed')
def snapshot_ready(obj,token,label):
	assert obj is session and token.props.revision==1 and label.get_data()=='Byte transform é'.encode()
	retained.extend([token,label]);seen.append('snapshot');obj.disconnect(connection)
session.connect('processed',processed);connection=session.connect('snapshot-ready',snapshot_ready)
assert tuple(session.try_process(GLib.Bytes.new(bytes([3,0,254])),[77,77,77,77]))==(True,bytes([172,170,87,77]),3)
assert seen==['processed','snapshot'] and session.props.revision==1 and session.props.current is retained[0]
ok,statistics=session.try_statistics();assert ok and statistics.astra_field_0_score==1072.5 and statistics.astra_field_1_revision==1 and statistics.astra_field_2_processed==3
session.props.enabled=False
try:session.try_process(GLib.Bytes.new(b'\0'),[77])
except GLib.Error as error:assert error.code==-1610
else:raise AssertionError('disabled service accepted input')
session.props.enabled=True
try:session.try_process(GLib.Bytes.new(bytes([3,0,254])),[77])
except GLib.Error as error:assert error.code==-1610
else:raise AssertionError('insufficient capacity accepted')
ok,snapshot=session.try_snapshot();assert ok and snapshot.get_data()==bytes([172,170,87])
session=None;gc.collect();assert library.byte16_retired_count(1)==1 and library.byte16_retired_count(3)==1 and library.byte16_retired_count(4)==0
assert retained[0].props.revision==1 and retained[1].get_data()=='Byte transform é'.encode();retained.clear();gc.collect();assert library.byte16_retired_count(4)==1
print('PASS API A scanned GI properties, algorithms, signals and surviving object/text values')
