// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

namespace Astra.Semantic {
public enum ResultOwnershipContract {
	UNMANAGED,
	OWNED_TRANSFER,
	STATIC_TEXT,
	RECEIVER_TEXT,
	RECEIVER_BORROW;

	public bool is_valid() {
		return this == UNMANAGED || this == OWNED_TRANSFER || this == STATIC_TEXT || this == RECEIVER_TEXT || this == RECEIVER_BORROW;
	}

	public string dump_suffix() {
		return this == RECEIVER_BORROW ? " (contract receiver-borrow)" : this == STATIC_TEXT ? " (contract static-text)" : this == OWNED_TRANSFER ? " (contract owned-transfer)" : "";
	}

}

// Behavioral callable contract shared by native and foreign declarations.
// No type, ABI channel, syntax, or runtime representation is introduced.
public enum PointerParameterContract {
	UNMANAGED,
	BORROWED_NOESCAPE,
	OWNED_TRANSFER;

	public bool is_valid() {
		return this == UNMANAGED || this == BORROWED_NOESCAPE || this == OWNED_TRANSFER;
	}

	public string dump_suffix() {
		if (this == OWNED_TRANSFER) {
			return " (contract owned-transfer)";
		}
		return this == BORROWED_NOESCAPE ? " (contract borrowed-noescape)" : "";
	}

}

}
