// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

namespace Astra.Semantic {
// Checked blocks own the tree's nodes. Locals/provenance may retain a node,
// but no region owns a block, symbol, child, or parent. Identity is the
// object; function-local preorder ordinals are only for inspection.
public class LexicalRegion : Object {
	private WeakRef parent_region;
	public LexicalRegion? parent { owned get { return (LexicalRegion?) parent_region.get (); } }
	public int ordinal { get; private set; }

	internal LexicalRegion (LexicalRegion? parent, int ordinal) {
		assert (parent == null ? ordinal == 0 : ordinal > parent.ordinal);
		this.parent_region = WeakRef (parent);
		this.ordinal = ordinal;
	}

	public bool outlives(LexicalRegion destination) {
		LexicalRegion? current = destination;
		while (current != null) {
			if (current == this) {
				return true;
			}
			current = current.parent;
		}
		return false;
	}

}

public enum BorrowProvenanceKind {
	NULL,
	REGION
}

// Semantic proof, queried for checked typed-pointer, slice and class-reference values.
// Origin retains the named source for diagnostics; local reads deliberately
// summarize at the local, without following its previous stored values.
public class BorrowProvenance : Object {
	public BorrowProvenanceKind kind { get; private set; }
	public LexicalRegion? region { get; private set; }
	public Symbol? origin { get; private set; }

	private BorrowProvenance.null_value () {
		this.kind = BorrowProvenanceKind.NULL;
	}

	private BorrowProvenance.for_region (LexicalRegion region, Symbol origin) {
		this.kind = BorrowProvenanceKind.REGION;
		this.region = region;
		this.origin = origin;
	}

	public static BorrowProvenance for_expression(CheckedExpression expression) {
		assert (expression.semantic_type.is_lexically_borrowed_value ());
		if (expression is CheckedNullPointerExpression) {
			return new BorrowProvenance.null_value ();
		}
		var buffer = expression as CheckedOwnedBufferBorrow;
		if (buffer != null) {
			return new BorrowProvenance.for_region (buffer.source.lexical_region, buffer.source);
		}
		var field = expression as CheckedOwnedFieldBorrow;
		if (field != null && field.field.owns_buffer) {
			return new BorrowProvenance.for_region (field.borrow_region, field.field);
		}
		var projection = expression as CheckedStructProjectionValue;
		if (projection != null && projection.source.contract.mode == StructValueMode.BORROW_VALUE) {
			CheckedStructProducer source = projection.source;
			while (source is CheckedStructProjectionProducer) {
				source = ((CheckedStructProjectionProducer) source).source;
			}
			var snapshot = source as CheckedStructBorrowSnapshot;
			var place = snapshot == null ? null : snapshot.source as CheckedLocalPlace;
			if (place != null && place.local.incoming_parameter != null && place.local.incoming_parameter.struct_value_contract != null && place.local.incoming_parameter.struct_value_contract.mode == StructValueMode.BORROW_VALUE) {
				return new BorrowProvenance.for_region (place.local.lexical_region, place.local);
			}
			var call = source as CheckedStructCallResult;
			var getter = call == null ? null : call.target as PropertyGetterSymbol;
			assert (getter != null && getter.result_contract == ResultOwnershipContract.RECEIVER_BORROW && projection.borrow_region != null);
			return new BorrowProvenance.for_region (projection.borrow_region, getter.property_symbol);
		}
		var reference = expression as CheckedObjectReferenceExpression;
		if (reference != null) {
			return new BorrowProvenance.for_region (reference.storage.lexical_region, reference.storage);
		}
		var slice = expression as CheckedSliceFromArrayExpression;
		if (slice != null) {
			return new BorrowProvenance.for_region (slice.local.lexical_region, slice.local);
		}
		var address = expression as CheckedAddressOfExpression;
		if (address != null) {
			assert (address.local.address_taken && ((TypedPointerType) address.semantic_type).pointee == address.local.semantic_type);
			return new BorrowProvenance.for_region (address.local.lexical_region, address.local);
		}
		var local = expression as CheckedLocalReferenceExpression;
		if (local != null) {
			return new BorrowProvenance.for_region (local.local.lexical_region, local.local);
		}
		var parameter = expression as CheckedParameterReferenceExpression;
		if (parameter != null) {
			assert (parameter.parameter.lexical_region != null && parameter.parameter.lexical_region.parent == null);
			return new BorrowProvenance.for_region (parameter.parameter.lexical_region, parameter.parameter);
		}
		// Adding another producer requires an explicit lifetime contract.
		assert_not_reached ();
	}

	public bool outlives(LexicalRegion destination) {
		return kind == BorrowProvenanceKind.NULL || region.outlives (destination);
	}

	public DataPointerProvenance snapshot(bool deep_text = false) {
		if (kind == BorrowProvenanceKind.NULL) {
			return new DataPointerProvenance (DataPointerOrigin.NULL, -1, -1);
		}
		if (origin is PropertySymbol) {
			return new DataPointerProvenance (DataPointerOrigin.RECEIVER_RECORD, ((PropertySymbol) origin).ordinal, region.ordinal, deep_text);
		}
		if (origin is StructFieldSymbol) {
			return new DataPointerProvenance (DataPointerOrigin.BUFFER_FIELD, ((StructFieldSymbol) origin).ordinal, region.ordinal);
		}
		var storage = origin as LexicalObjectStorageSymbol;
		if (storage != null) {
			return new DataPointerProvenance (DataPointerOrigin.OBJECT_STORAGE, storage.ordinal, region.ordinal);
		}
		var local = origin as LocalSymbol;
		return new DataPointerProvenance (local == null ? DataPointerOrigin.PARAMETER : DataPointerOrigin.LOCAL, local == null ? ((ParameterSymbol) origin).ordinal : local.ordinal, region.ordinal, deep_text);
	}

}
}
