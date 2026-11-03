// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;

namespace Astra.Ssa {
// Stage-owned semantic member. Accessors use the ordinary callable pipeline.
public class SsaProperty : SsaNode {
	public SsaMethod? factory { get; internal set; }
	public bool is_owned_lazy { get; internal set; }
	public bool is_borrowed { get; internal set; }
	public bool is_lazy { get; internal set; }
	private WeakRef owner;
	public SsaNativeInstance? declaring_type { owned get { return (SsaNativeInstance?) owner.get (); } }
	public SourceSpan name_span { get; private set; }
	private string identifier;
	public string name { get { return identifier; } }
	public SemanticType semantic_type { get; private set; }
	public int ordinal { get; private set; }
	public int member_ordinal { get; private set; }
	public SsaPropertyGetter? getter { get; internal set; }
	public SsaPropertySetter? setter { get; internal set; }

	internal SsaProperty (SourceSpan span, SourceSpan name_span, string name, SsaNativeInstance owner, SemanticType semantic_type, int ordinal, int member_ordinal) {
		base (span);
		this.name_span = name_span;
		this.identifier = name;
		this.owner = WeakRef (owner);
		this.semantic_type = semantic_type;
		this.ordinal = ordinal;
		this.member_ordinal = member_ordinal;
	}

}

public class SsaLazyObserve : SsaInstruction {
	private WeakRef property_identity;
	public SsaProperty? property_member { owned get { return (SsaProperty?) property_identity.get (); } }
	internal SsaLazyObserve (SourceSpan span, SsaProperty property_member, int ordinal) {
		base (span, property_member.semantic_type, ordinal);
		this.property_identity = WeakRef (property_member);
	}

}
public class SsaLazyDrop : SsaInstruction {
	private WeakRef property_identity;
	public SsaProperty? property_member { owned get { return (SsaProperty?) property_identity.get (); } }
	internal SsaLazyDrop (SourceSpan span, SsaProperty property_member) {
		base (span, null, -1);
		this.property_identity = WeakRef (property_member);
	}

}

public abstract class SsaPropertyAccessor : SsaFunction {
	private WeakRef parent;
	public SsaProperty? property_member { owned get { return (SsaProperty?) parent.get (); } }
	public SsaReceiver receiver { get; private set; }

	protected SsaPropertyAccessor (SourceSpan span, SourceSpan name_span, string name, SsaProperty property_member, SsaReceiver receiver, SemanticType return_type, int ordinal, GenericArray<SsaFunctionParameter> parameters, GenericArray<SsaBlock> blocks, SsaBlock entry, SsaCleanupContract? owned_cleanup = null) {
		base (span, name_span, name, return_type, ordinal, parameters, blocks, entry, owned_cleanup);
		this.parent = WeakRef (property_member);
		this.receiver = receiver;
	}

}

public class SsaPropertyGetter : SsaPropertyAccessor {
	internal SsaPropertyGetter (SourceSpan span, SourceSpan name_span, string name, SsaProperty property_member, SsaReceiver receiver, SemanticType return_type, int ordinal, GenericArray<SsaFunctionParameter> parameters, GenericArray<SsaBlock> blocks, SsaBlock entry, SsaCleanupContract? owned_cleanup = null) {
		base (span, name_span, name, property_member, receiver, return_type, ordinal, parameters, blocks, entry, owned_cleanup);
	}

}

public class SsaPropertySetter : SsaPropertyAccessor {
	internal SsaPropertySetter (SourceSpan span, SourceSpan name_span, string name, SsaProperty property_member, SsaReceiver receiver, SemanticType return_type, int ordinal, GenericArray<SsaFunctionParameter> parameters, GenericArray<SsaBlock> blocks, SsaBlock entry) {
		base (span, name_span, name, property_member, receiver, return_type, ordinal, parameters, blocks, entry);
	}

}
}
