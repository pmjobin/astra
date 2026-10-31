// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;

namespace Astra.Cfg {
// Stage-owned semantic member. Accessors use the ordinary callable pipeline.
public class CfgProperty : CfgNode {
	public CfgMethod? factory { get; internal set; }
	public bool is_owned_lazy { get; internal set; }
	public bool is_borrowed { get; internal set; }
	public bool is_lazy { get; internal set; }
	private WeakRef owner;
	public CfgNativeInstance? declaring_type { owned get { return (CfgNativeInstance?) owner.get (); } }
	public SourceSpan name_span { get; private set; }
	private string identifier;
	public string name { get { return identifier; } }
	public SemanticType semantic_type { get; private set; }
	public int ordinal { get; private set; }
	public int member_ordinal { get; private set; }
	public CfgPropertyGetter? getter { get; internal set; }
	public CfgPropertySetter? setter { get; internal set; }

	internal CfgProperty (SourceSpan span, SourceSpan name_span, string name, CfgNativeInstance owner, SemanticType semantic_type, int ordinal, int member_ordinal) {
		base (span);
		this.name_span = name_span;
		this.identifier = name;
		this.owner = WeakRef (owner);
		this.semantic_type = semantic_type;
		this.ordinal = ordinal;
		this.member_ordinal = member_ordinal;
	}
}

public class CfgLazyObserve : CfgValue {
	private WeakRef property_identity;
	public CfgProperty? property_member { owned get { return (CfgProperty?) property_identity.get (); } }
	internal CfgLazyObserve (SourceSpan span, CfgProperty property_member) {
		base (span, property_member.semantic_type);
		this.property_identity = WeakRef (property_member);
	}
}
public class CfgLazyDrop : CfgInstruction {
	private WeakRef property_identity;
	public CfgProperty? property_member { owned get { return (CfgProperty?) property_identity.get (); } }
	internal CfgLazyDrop (SourceSpan span, CfgProperty property_member) {
		base (span);
		this.property_identity = WeakRef (property_member);
	}
}

public abstract class CfgPropertyAccessor : CfgFunction {
	private WeakRef parent;
	public CfgProperty? property_member { owned get { return (CfgProperty?) parent.get (); } }
	public CfgReceiver receiver { get; private set; }

	protected CfgPropertyAccessor (SourceSpan span, SourceSpan name_span, string name, CfgProperty property_member, CfgReceiver receiver, SemanticType return_type, int ordinal, GenericArray<CfgParameter> parameters, GenericArray<CfgLocalPlace> locals, GenericArray<CfgBlock> blocks, CfgBlock entry, CfgCleanupContract? owned_cleanup = null) {
		base (span, name_span, name, return_type, ordinal, parameters, locals, blocks, entry, owned_cleanup);
		this.parent = WeakRef (property_member);
		this.receiver = receiver;
	}
}

public class CfgPropertyGetter : CfgPropertyAccessor {
	internal CfgPropertyGetter (SourceSpan span, SourceSpan name_span, string name, CfgProperty property_member, CfgReceiver receiver, SemanticType return_type, int ordinal, GenericArray<CfgParameter> parameters, GenericArray<CfgLocalPlace> locals, GenericArray<CfgBlock> blocks, CfgBlock entry, CfgCleanupContract? owned_cleanup = null) {
		base (span, name_span, name, property_member, receiver, return_type, ordinal, parameters, locals, blocks, entry, owned_cleanup);
	}
}

public class CfgPropertySetter : CfgPropertyAccessor {
	internal CfgPropertySetter (SourceSpan span, SourceSpan name_span, string name, CfgProperty property_member, CfgReceiver receiver, SemanticType return_type, int ordinal, GenericArray<CfgParameter> parameters, GenericArray<CfgLocalPlace> locals, GenericArray<CfgBlock> blocks, CfgBlock entry) {
		base (span, name_span, name, property_member, receiver, return_type, ordinal, parameters, locals, blocks, entry);
	}
}
}
