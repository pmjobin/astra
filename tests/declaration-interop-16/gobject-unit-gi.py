# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
import ctypes,gc,sys
import gi
gi.require_version('Opaque16','1.0')
from gi.repository import Opaque16,GLib
library=ctypes.CDLL(sys.argv[1]);library.gobjectunit16_retired_count.restype=ctypes.c_uint
session=Opaque16.Session.new(7,1.5);assert session.props.count==7;session.props.count=19;assert session.try_evaluate(4)==(True,25.0)
try:session.try_evaluate(-1);raise AssertionError('missing checked error')
except GLib.Error as error:assert error.code==-1600
ok,copy=session.try_snapshot(GLib.Bytes.new(bytes([3,0,254])));assert ok and copy.get_data()==bytes([86,85,171]);assert session.try_visit(False,lambda value: not value)==(True,True)
assert library.gobjectunit16_retired_count()==0;del session;gc.collect();assert library.gobjectunit16_retired_count()==1
print('PASS opaque scanned GI bytes, callbacks, properties and native retirement')
