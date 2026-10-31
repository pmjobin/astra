// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
[CCode(cname = "error_observe")] void observe(int stage);
[CCode(cname = "error_record_drop")] void record_drop(int value);
[CCode(cname = "error_observer_result")] int observer_result();
