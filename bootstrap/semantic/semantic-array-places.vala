// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;

namespace Astra.Semantic {
public class CheckedArrayRecordEntry : CheckedNode {
	public CheckedStructInitializer? initializer { get; private set; }
	public CheckedStructProducer? producer { get; private set; }
	internal CheckedArrayRecordEntry (SourceSpan span, CheckedStructInitializer? initializer, CheckedStructProducer? producer) {
		base (span);
		this.initializer = initializer;
		this.producer = producer;
	}
	internal CheckedArrayRecordEntry.named (CheckedStructInitializer initializer) {
		this(initializer.span, initializer, null);
	}
	internal CheckedArrayRecordEntry.produced (CheckedStructProducer producer) {
		this(producer.span, null, producer);
	}
}

public class CheckedArrayLocalDeclaration : CheckedStatement {
	public LocalSymbol local { get; private set; }
	public GenericArray<CheckedExpression> elements { get; private set; }
	public GenericArray<CheckedArrayRecordEntry> records { get; private set; default = new GenericArray<CheckedArrayRecordEntry> (); }
	internal CheckedArrayLocalDeclaration.record_entries (SourceSpan span, LocalSymbol local, GenericArray<CheckedArrayRecordEntry> records) {
		this(span, local, new GenericArray<CheckedExpression> ());
		this.records = records;
	}

	internal CheckedArrayLocalDeclaration (SourceSpan span, LocalSymbol local, GenericArray<CheckedExpression> elements) {
		base (span);
		this.local = local;
		this.elements = elements;
	}
}

public class CheckedArrayElementPlace : CheckedPlace {
	public LocalSymbol local { get; private set; }
	public ArrayType array_type { get; private set; }
	public CheckedExpression index { get; private set; }
	public DataPointerProvenance provenance { get; private set; }
	public bool traps_on_invalid { get { return true; } }

	internal CheckedArrayElementPlace (SourceSpan span, LocalSymbol local, CheckedExpression index) {
		base (span, ((ArrayType) local.semantic_type).element_type);
		this.local = local;
		this.array_type = (ArrayType) local.semantic_type;
		this.index = index;
		this.provenance = new DataPointerProvenance (DataPointerOrigin.LOCAL, local.ordinal, local.lexical_region.ordinal);
	}
}
}
