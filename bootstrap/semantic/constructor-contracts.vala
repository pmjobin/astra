// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;

namespace Astra.Semantic {
// Both admitted constructor families use the same initialized-prefix unwind
// protocol. This decision is rechecked from each stage's copied authority.
public class ConstructorContracts : Object {
	public static bool admitted(ForeignClassPolicy? foreign, AllocationPolicy? allocation, int ordinal, ClassType? error) {
		return error != null && (allocation != null && allocation.checked_initialization () || ForeignApiTypes.checked_constructor (foreign, ordinal, error));
	}

}
}
