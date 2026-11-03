// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

namespace Astra.NativeAbi {
// Declared storage fields, never flattened register channels. This graph owns
// copied nominal identities and immutable leaf types, with no upstream nodes.
public class NativeRecordField : Object {
	public int ordinal { get; private set; }
	private string identifier;
	public string name { get { return identifier; } }
	public NativeAbiType? leaf { get; private set; }
	public NativeRecordElement? record { get; private set; }
	internal NativeRecordField (int ordinal, string name, NativeAbiType? leaf, NativeRecordElement? record = null) {
		this.ordinal = ordinal;
		this.identifier = name;
		this.leaf = leaf;
		this.record = record;
	}

}

public class NativeRecordElement : Object {
	public int struct_ordinal { get; private set; }
	private string identifier;
	public string struct_name { get { return identifier; } }
	public GenericArray<NativeRecordField> fields { get; private set; }
	public bool natural_layout { get; private set; }
	public bool structural_zero { get; private set; }
	public bool trivial_destruction { get; private set; }
	internal NativeRecordElement (int ordinal, string name, GenericArray<NativeRecordField> fields, bool natural_layout = true, bool structural_zero = true, bool trivial_destruction = true) {
		this.struct_ordinal = ordinal;
		this.identifier = name;
		this.fields = fields;
		this.natural_layout = natural_layout;
		this.structural_zero = structural_zero;
		this.trivial_destruction = trivial_destruction;
	}

	public string spelling() {
		return "RECORD#%d(%s)".printf (struct_ordinal, struct_name);
	}

}

public class NativeRecordSliceType : NativeSliceType {
	public NativeRecordElement element { get; private set; }
	public NativeSliceAccess access { get; private set; }
	public bool borrowed_noescape { get; private set; }
	internal NativeRecordSliceType (NativeRecordElement element, NativeSliceAccess access = NativeSliceAccess.READ_WRITE, bool borrowed_noescape = true) {
		base ();
		this.element = element;
		this.access = access;
		this.borrowed_noescape = borrowed_noescape;
	}

	public override string spelling() {
		return "RECORD_SLICE(PTR,I32; %s) read-write borrowed-noescape".printf (element.spelling ());
	}

	public override bool same_type(NativeAbiType other) {
		var record = other as NativeRecordSliceType;
		return record != null && record.element == element && record.access == access && record.borrowed_noescape == borrowed_noescape && record.base_type == base_type && record.length_type == length_type;
	}

}

public class NativeRecordFieldLayout : Object {
	public NativeRecordField field { get; private set; }
	public uint64 offset { get; private set; }
	public uint64 size { get; private set; }
	public uint alignment { get; private set; }
	internal NativeRecordFieldLayout (NativeRecordField field, uint64 offset, uint64 size, uint alignment) {
		this.field = field;
		this.offset = offset;
		this.size = size;
		this.alignment = alignment;
	}

}

// An explicitly selected target witness. No host size enters semantic identity.
// LLVM independently supplies actual sizes, alignments and offsets for comparison.
public class NativeRecordLayout : Object {
	public NativeRecordElement element { get; private set; }
	public uint64 stride { get; private set; }
	public uint alignment { get; private set; }
	public GenericArray<NativeRecordFieldLayout> fields { get; private set; }
	public const uint64 MAX_EXTENT = 0x7fffffffffffffff;
	internal NativeRecordLayout (NativeRecordElement element, uint64 stride, uint alignment, GenericArray<NativeRecordFieldLayout> fields) {
		this.element = element;
		this.stride = stride;
		this.alignment = alignment;
		this.fields = fields;
	}

	public bool fits_count(uint64 count) {
		return stride != 0 && stride <= MAX_EXTENT && count <= MAX_EXTENT / stride;
	}

	public void verify_x86_64() throws NativeAbiError {
		var expected = x86_64 (element);
		if (stride != expected.stride || alignment != expected.alignment || fields.length != expected.fields.length) {
			throw new NativeAbiError.INVALID_ABI ("record physical layout has an incorrect stride, alignment or field count");
		}
		for (int i = 0; i < fields.length; i++) {
			var actual = fields[i];
			var member = expected.fields[i];
			if (actual.field != member.field || actual.offset != member.offset || actual.size != member.size || actual.alignment != member.alignment) {
				throw new NativeAbiError.INVALID_ABI ("record physical layout has an incorrect field identity, offset, size or alignment");
			}
		}
	}

	private static uint scalar_bits(NativeScalarType type) throws NativeAbiError {
		switch (type) {
		case NativeScalarType.B1:
			return 1;
		case NativeScalarType.I8:
		case NativeScalarType.U8:
			return 8;
		case NativeScalarType.I16:
		case NativeScalarType.U16:
			return 16;
		case NativeScalarType.I32:
		case NativeScalarType.U32:
		case NativeScalarType.F32:
			return 32;
		case NativeScalarType.I64:
		case NativeScalarType.U64:
		case NativeScalarType.F64:
		case NativeScalarType.PTR:
			return 64;
		default:
			throw new NativeAbiError.INVALID_ABI ("unsupported record storage leaf");
		}
	}

	private static uint64 align_up(uint64 offset, uint alignment) throws NativeAbiError {
		if (alignment == 0 || offset > MAX_EXTENT - (alignment - 1)) {
			throw new NativeAbiError.INVALID_ABI ("record layout exceeds the qualified address range");
		}
		return (offset + alignment - 1) & ~((uint64) alignment - 1);
	}

	public static NativeRecordLayout x86_64(NativeRecordElement element, HashTable<NativeRecordElement, NativeRecordLayout>? completed = null, HashTable<NativeRecordElement, bool>? active = null) throws NativeAbiError {
		var cache = completed ?? new HashTable<NativeRecordElement, NativeRecordLayout> (direct_hash, direct_equal);
		var visiting = active ?? new HashTable<NativeRecordElement, bool> (direct_hash, direct_equal);
		var prior = cache.lookup (element);
		if (prior != null) {
			return prior;
		}
		if (visiting.contains (element) || element.fields.length == 0 || !element.natural_layout || !element.structural_zero || !element.trivial_destruction) {
			throw new NativeAbiError.INVALID_ABI ("incomplete or cyclic record element layout");
		}
		visiting.insert (element, true);
		uint64 end = 0;
		uint alignment = 1;
		var fields = new GenericArray<NativeRecordFieldLayout> ();
		foreach (var field in element.fields) {
			uint64 size;
			uint member_alignment;
			if (field.ordinal != fields.length || (field.record == null) == (field.leaf == null)) {
				throw new NativeAbiError.INVALID_ABI ("record layout requires exact ordered field shapes");
			}
			if (field.record != null) {
				var child = x86_64 (field.record, cache, visiting);
				size = child.stride;
				member_alignment = child.alignment;
			} else {
				var vector = field.leaf as NativeVectorType;
				if (vector == null && !(field.leaf is NativeScalarAbiType)) {
					throw new NativeAbiError.INVALID_ABI ("record field is not a storage leaf");
				}
				uint bits = scalar_bits (vector == null ? ((NativeScalarAbiType) field.leaf).scalar_type : vector.element);
				if (vector != null) {
					if (vector.lanes < 1 || vector.lanes > 16) {
						throw new NativeAbiError.INVALID_ABI ("unqualified record vector extent");
					}
					bits *= vector.lanes;
				}
				uint bytes = (bits + 7) / 8;
				member_alignment = 1;
				while (member_alignment < bytes) {
					member_alignment *= 2;
				}
				size = member_alignment;
			}
			uint64 offset = align_up (end, member_alignment);
			if (size > MAX_EXTENT - offset) {
				throw new NativeAbiError.INVALID_ABI ("record layout exceeds the qualified address range");
			}
			fields.add (new NativeRecordFieldLayout (field, offset, size, member_alignment));
			end = offset + size;
			alignment = uint.max (alignment, member_alignment);
		}
		var result = new NativeRecordLayout (element, align_up (end, alignment), alignment, fields);
		visiting.remove (element);
		cache.insert (element, result);
		return result;
	}

}
}
