// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;

namespace Astra.Core {
// Concrete application identities above materialization become exact StructTypes
// in this same statement. No aggregate computation or generic copy node exists.
public class CoreStructCopy : CoreStatement {
	public CorePlace destination { get; private set; }
	public CorePlace source { get; private set; }
	public SemanticType semantic_type { get; private set; }
	public bool initializes_destination { get; private set; }
	internal CoreStructCopy (SourceSpan span, CorePlace destination, CorePlace source, SemanticType semantic_type, bool initializes_destination = false) {
		base (span);
		this.destination = destination;
		this.source = source;
		this.semantic_type = semantic_type;
		this.initializes_destination = initializes_destination;
	}
}

// Each successful Resource initializer acquires one exact field obligation.
public class CoreStructAcquire : CoreStatement {
	public CoreOwnedLocal owner { get; private set; }
	public CoreFieldPlace field { get; private set; }
	public CoreOwnedLocal? source { get; private set; }
	public CoreValue? producer { get; private set; }
	internal CoreStructAcquire (SourceSpan span, CoreOwnedLocal owner, CoreFieldPlace field, CoreOwnedLocal? source, CoreValue? producer) {
		base (span);
		this.owner = owner;
		this.field = field;
		this.source = source;
		this.producer = producer;
	}
}
public class CoreStructMove : CoreStatement {
	public CoreOwnedLocal source { get; private set; }
	public CoreOwnedLocal destination { get; private set; }
	internal CoreStructMove (SourceSpan span, CoreOwnedLocal source, CoreOwnedLocal destination) {
		base (span);
		this.source = source;
		this.destination = destination;
	}
}
public class CoreRecordTake : CoreStatement {
	public CoreOwnedLocal source { get; private set; }
	public CoreFieldPlace field { get; private set; }
	public CoreOwnedLocal destination { get; private set; }
	internal CoreRecordTake (SourceSpan span, CoreOwnedLocal source, CoreFieldPlace field, CoreOwnedLocal destination) {
		base (span);
		this.source = source;
		this.field = field;
		this.destination = destination;
	}
}
public class CoreRecordReplace : CoreStatement {
	public CoreOwnedLocal owner { get; private set; }
	public CoreFieldPlace field { get; private set; }
	public CoreOwnedLocal? source { get; private set; }
	public CoreValue? producer { get; private set; }
	internal CoreRecordReplace (SourceSpan span, CoreOwnedLocal owner, CoreFieldPlace field, CoreOwnedLocal? source, CoreValue? producer) {
		base (span);
		this.owner = owner;
		this.field = field;
		this.source = source;
		this.producer = producer;
	}
}

public delegate CoreStruct? CoreStructResolver(SemanticType type);

public class CoreStructLeafPath : Object {
	public GenericArray<CoreStructField> fields { get; private set; }
	public SemanticType semantic_type { get { return fields[fields.length - 1].semantic_type; } }
	internal CoreStructLeafPath (GenericArray<CoreStructField> fields) {
		this.fields = new GenericArray<CoreStructField> ();
		foreach (var field in fields) {
			this.fields.add (field);
		}
	}
}

// The sole copy leaf walk: recursive declaration order, vectors stay one leaf.
public class CoreStructLeaves : Object {
	public static GenericArray<CoreStructLeafPath> enumerate(CoreStruct structure, CoreStructResolver resolve) throws CoreError {
		var result = new GenericArray<CoreStructLeafPath> ();
		try {
			CopyabilityFields copy_fields = (type) => {
				var owner = type == structure.semantic_type ? structure : resolve (type);
				if (owner == null) {
					return null;
				}
				var fields = new GenericArray<SemanticType> ();
				foreach (var field in owner.fields) {
					fields.add (field.semantic_type);
				}
				return fields;
			};
			var paths = StructLeafOrder.enumerate (structure.semantic_type, copy_fields);
			foreach (var path in paths) {
				var fields = new GenericArray<CoreStructField> ();
				var owner = structure;
				for (int d = 0; d < path.depth; d++) {
					int ordinal = path.field_ordinal (d);
					var field = owner.fields[ordinal];
					fields.add (field);
					if (field.semantic_type is StructType) {
						owner = resolve (field.semantic_type);
					}
				}
				result.add (new CoreStructLeafPath (fields));
			}
		} catch (StructLeafError error) {
			throw new CoreError.INVALID_IR ("invalid struct copy field graph: %s", error.message);
		}
		return result;
	}
}
}
