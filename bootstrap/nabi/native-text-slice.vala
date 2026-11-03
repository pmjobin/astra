// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

namespace Astra.NativeAbi {
public enum NativeSliceAccess {
	READ, READ_WRITE
}

// A memory descriptor shape, distinct from text result register transport.
// Offsets, stride and alignment are supplied by the selected target layout.
public class NativeTextDescriptor : Object {
	public NativeTextType text { get; private set; }
	public int data_ordinal { get; private set; }
	public int byte_length_ordinal { get; private set; }
	public bool natural_layout { get; private set; }
	internal NativeTextDescriptor (NativeTextType? text = null, int data_ordinal = 0, int byte_length_ordinal = 1, bool natural_layout = true) {
		this.text = text ?? new NativeTextType (NativeTextContract.BORROWED_NOESCAPE);
		this.data_ordinal = data_ordinal;
		this.byte_length_ordinal = byte_length_ordinal;
		this.natural_layout = natural_layout;
	}

	public bool valid() {
		return text.base_type == NativeScalarType.PTR && text.length_type == NativeScalarType.I32 && text.contract == NativeTextContract.BORROWED_NOESCAPE && data_ordinal == 0 && byte_length_ordinal == 1 && natural_layout;
	}

}
public class NativeTextSliceType : NativeSliceType {
	public NativeTextDescriptor descriptor { get; private set; }
	public NativeSliceAccess access { get; private set; }
	public bool deep_borrow { get; private set; }
	internal NativeTextSliceType (NativeTextDescriptor? descriptor = null, NativeSliceAccess access = NativeSliceAccess.READ, bool deep_borrow = true, NativeScalarType base_type = NativeScalarType.PTR, NativeScalarType length_type = NativeScalarType.I32) {
		base (base_type, length_type);
		this.descriptor = descriptor ?? new NativeTextDescriptor ();
		this.access = access;
		this.deep_borrow = deep_borrow;
	}

	public bool valid() {
		return base_type == NativeScalarType.PTR && length_type == NativeScalarType.I32 && descriptor.valid () && access == NativeSliceAccess.READ && deep_borrow;
	}

	public override string spelling() {
		return "TEXT_SLICE(table PTR,count I32; element {data PTR,byte_length I32} natural) read deep-borrowed-noescape";
	}

	public override bool same_type(NativeAbiType other) {
		return valid () && other is NativeTextSliceType && ((NativeTextSliceType) other).valid ();
	}

}
// An independently owned target witness; never infer this from result registers.
public class NativeTextSliceLayout : Object {
	public uint64 data_offset { get; private set; }
	public uint64 length_offset { get; private set; }
	public uint64 stride { get; private set; }
	public uint alignment { get; private set; }
	public uint pointer_bytes { get; private set; }
	internal NativeTextSliceLayout (uint64 data_offset, uint64 length_offset, uint64 stride, uint alignment, uint pointer_bytes) {
		this.data_offset = data_offset;
		this.length_offset = length_offset;
		this.stride = stride;
		this.alignment = alignment;
		this.pointer_bytes = pointer_bytes;
	}

	public bool qualified() {
		return data_offset == 0 && length_offset == 8 && stride == 16 && alignment == 8 && pointer_bytes == 8;
	}

}
}
