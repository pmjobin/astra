// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;

namespace Astra.Semantic {
public class ResultObjectStorageSymbol : Object {
	private WeakRef class_identity;
	public ClassSymbol? object_class { owned get { return (ClassSymbol?) class_identity.get (); } }
	public ClassType semantic_type { get { return (ClassType) object_class.semantic_type; } }
	internal ResultObjectStorageSymbol (ClassSymbol object_class) {
		this.class_identity = WeakRef (object_class);
	}

}

public class CheckedOwnedObjectResultConstruction : CheckedExpression {
	public ResultObjectStorageSymbol storage { get; private set; }
	public ConstructorSymbol constructor { get; private set; }
	public GenericArray<CheckedExpression> arguments { get; private set; }
	public ObjectResultProvenance provenance { get { return ObjectResultProvenance.RESULT_STORAGE; } }
	internal CheckedOwnedObjectResultConstruction (SourceSpan span, ResultObjectStorageSymbol storage, ConstructorSymbol constructor, GenericArray<CheckedExpression> arguments) {
		base (span, storage.semantic_type);
		this.storage = storage;
		this.constructor = constructor;
		this.arguments = arguments;
	}

}
}
