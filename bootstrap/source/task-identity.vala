// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
namespace Astra.Source {
// Shared value identity; detached native plans do not depend on semantic graphs.
public enum AsyncProviderKind {
	VIRTUAL, LINUX_IO_URING, POSIX_THREADED
}
public class SuspensionLoanIdentity : Object {
	internal SuspensionLoanIdentity () {
	}
}
// Opaque logical contract token. It has no body, frame or stage backlink.
public class TaskContractIdentity : Object {
	internal TaskContractIdentity () {
	}
}
}
