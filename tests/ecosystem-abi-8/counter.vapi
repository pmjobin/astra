// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
[CCode(destroy_function = "astra_gobject_unref")]
handle Counter;
[CCode(destroy_function = "astra_gobject_weak_free")]
handle CounterWeak;
[CCode(destroy_function = "astra_gobject_text_free")]
handle ForeignUtf8;
[CCode(cname = "counter_new")] owned Counter counter_new(int value);
[CCode(cname = "counter_get")] int counter_get(borrowed Counter value);
[CCode(cname = "counter_set")] int counter_set(borrowed Counter value, int number);
[CCode(cname = "counter_label", text_abi = "utf8-i32")] int counter_label(borrowed Counter value, borrowed string text);
[CCode(cname = "counter_snapshot")] owned ForeignUtf8 counter_snapshot(borrowed Counter value);
[CCode(cname = "astra_gobject_ref")] owned Counter counter_ref(borrowed Counter value);
[CCode(cname = "astra_gobject_identity")] int counter_identity(borrowed Counter value);
[CCode(cname = "astra_gobject_same")] int counter_same(borrowed Counter left, borrowed Counter right);
[CCode(cname = "astra_gobject_weak")] owned CounterWeak counter_weak(borrowed Counter value);
[CCode(cname = "astra_gobject_upgrade")] owned Counter counter_upgrade(borrowed CounterWeak value);
[CCode(cname = "astra_gobject_text_length")] int foreign_text_length(borrowed ForeignUtf8 value);
[CCode(cname = "astra_gobject_text_byte")] int foreign_text_byte(borrowed ForeignUtf8 value, int offset);
[CCode(cname = "astra_gobject_live_handles")] int foreign_live();
[CCode(cname = "counter_finalized")] int counter_finalized();
[CCode(cname = "counter_disposed")] int counter_disposed();
[CCode(cname = "counter_emit")] int counter_emit(borrowed Counter value, int number);
