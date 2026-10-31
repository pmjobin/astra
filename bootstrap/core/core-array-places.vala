// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;

namespace Astra.Core {
// One complete entry. Named fields stay in written order, while a producer
// retains the existing bounded snapshot/call-result contract until CFG.
public class CoreArrayRecordEntry : CoreNode {
	public CoreArrayElementPlace target { get; private set; }
	public GenericArray<CoreStatement> initializers { get; private set; }
	public CoreStructProducer? producer { get; private set; }
	internal CoreArrayRecordEntry (SourceSpan span, CoreArrayElementPlace target, GenericArray<CoreStatement> initializers, CoreStructProducer? producer = null) {
		base (span);
		this.target = target;
		this.initializers = initializers;
		this.producer = producer;
	}
}

public class CoreArrayInitialize : CoreStatement {
	public CoreLocalPlace storage { get; private set; }
	public GenericArray<CoreValue> elements { get; private set; }
	public GenericArray<CoreArrayRecordEntry> records { get; private set; default = new GenericArray<CoreArrayRecordEntry> (); }
	internal CoreArrayInitialize.record_entries (SourceSpan span, CoreLocalPlace storage, GenericArray<CoreArrayRecordEntry> records) {
		this(span, storage, new GenericArray<CoreValue> ());
		this.records = records;
	}

	internal CoreArrayInitialize (SourceSpan span, CoreLocalPlace storage, GenericArray<CoreValue> elements) {
		base (span);
		this.storage = storage;
		this.elements = elements;
	}
}

public class CoreArrayElementPlace : CorePlace {
	public CoreLocalPlace storage { get; private set; }
	public ArrayType array_type { get; private set; }
	public CoreValue index { get; private set; }
	public DataPointerProvenance provenance { get; private set; }
	public bool traps_on_invalid { get { return true; } }

	internal CoreArrayElementPlace (SourceSpan span, CoreLocalPlace storage, ArrayType array_type, CoreValue index, DataPointerProvenance provenance) {
		base (span, array_type.element_type);
		this.storage = storage;
		this.array_type = array_type;
		this.index = index;
		this.provenance = provenance;
	}
}
}
