// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
[CCode(destroy_function = "surge_close")]
handle Lease;
[CCode(destroy_function = "surge_close_other")]
handle OtherLease;
[CCode(cname = "surge_open")] owned Lease open_lease(int id);
[CCode(cname = "surge_open_other")] owned OtherLease open_other(int id);
[CCode(cname = "surge_id")] int lease_id(borrowed Lease value);
[CCode(cname = "surge_other_id")] int other_lease_id(borrowed OtherLease value);
[CCode(cname = "surge_live")] int live_leases();
[CCode(cname = "surge_event")] int event(int value);
[CCode(cname = "surge_number")] int number(int value);
