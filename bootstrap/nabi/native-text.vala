// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

namespace Astra.NativeAbi {
public enum NativeTextContract {
	BORROWED_NOESCAPE, STATIC_TEXT, RECEIVER_TEXT
}

// Independent physical text identity and contract. No semantic type,
// source universe, SSA value, ownership bit or C ABI descriptor is retained.
public class NativeTextType : NativeAbiType {
	public NativeScalarType base_type { get; private set; }
	public NativeScalarType length_type { get; private set; }
	public NativeTextContract contract { get; private set; }
	internal NativeTextType (NativeTextContract contract, NativeScalarType base_type = NativeScalarType.PTR, NativeScalarType length_type = NativeScalarType.I32) {
		this.contract = contract;
		this.base_type = base_type;
		this.length_type = length_type;
	}

	public override string spelling() {
		return "TEXT(%s,%s) %s".printf (base_type.spelling (), length_type.spelling (), contract == NativeTextContract.BORROWED_NOESCAPE ? "borrowed-noescape" : contract == NativeTextContract.RECEIVER_TEXT ? "receiver-text" : "static-text");
	}

	public override bool same_type(NativeAbiType other) {
		var text = other as NativeTextType;
		return text != null && text.contract == contract && text.base_type == base_type && text.length_type == length_type;
	}

}
}
