// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
[CCode(destroy_function = "astra_gobject_signal_source_free")]
handle SignalSource;
[CCode(cname = "astra_gobject_signal_source", text_abi = "utf8-i32")]
owned SignalSource signal_source(borrowed Counter object, borrowed string name);
[CCode(cname = "astra_gobject_signal_mode")] int signal_mode(borrowed SignalSource source);
[CCode(cname = "astra_gobject_signal_connections")] int signal_connections();
