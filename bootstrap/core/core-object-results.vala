// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;

namespace Astra.Core {
// Compiler-owned input, separate from lexical allocations and source parameters.
public class CoreResultObjectStorage : CoreNode {
	private WeakRef class_identity;
	public CoreClass? object_class { owned get { return (CoreClass?) class_identity.get (); } }
	public ClassType semantic_type { get; private set; }
	internal CoreResultObjectStorage (SourceSpan span, CoreClass object_class) {
		base (span);
		this.class_identity = WeakRef (object_class);
		this.semantic_type = (ClassType) object_class.semantic_type;
	}
}

public class CoreResultStorageReceiverValue : CoreValue {
	public CoreResultObjectStorage storage { get; private set; }
	internal CoreResultStorageReceiverValue (SourceSpan span, CoreResultObjectStorage storage, ReceiverType contract) {
		base (span, contract);
		this.storage = storage;
	}
}

public class CoreOwnedObjectResultConstruction : CoreValue {
	public CoreResultObjectStorage storage { get; private set; }
	private WeakRef callee;
	public CoreConstructor? constructor { owned get { return (CoreConstructor?) callee.get (); } }
	public GenericArray<CoreValue> arguments { get; private set; }
	internal CoreOwnedObjectResultConstruction (SourceSpan span, CoreResultObjectStorage storage, CoreConstructor constructor, GenericArray<CoreValue> arguments) {
		base (span, storage.semantic_type);
		this.storage = storage;
		this.callee = WeakRef (constructor);
		this.arguments = arguments;
	}
}
}
