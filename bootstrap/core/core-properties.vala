// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;

namespace Astra.Core {
// Stage-owned semantic member. Accessors use the ordinary callable pipeline.
public class CoreProperty : CoreNode {
	public CoreMethod? factory { get; internal set; }
	public bool is_owned_lazy { get; internal set; }
	public bool is_borrowed { get; internal set; }
	public bool is_lazy { get; internal set; }
	private WeakRef owner;
	public CoreNativeInstance? declaring_type { owned get { return (CoreNativeInstance?) owner.get (); } }
	public SourceSpan name_span { get; private set; }
	private string identifier;
	public string name { get { return identifier; } }
	public SemanticType semantic_type { get; internal set; }
	public int ordinal { get; private set; }
	public int member_ordinal { get; private set; }
	public CorePropertyGetter? getter { get; internal set; }
	public CorePropertySetter? setter { get; internal set; }

	internal CoreProperty (SourceSpan span, SourceSpan name_span, string name, CoreNativeInstance owner, SemanticType semantic_type, int ordinal, int member_ordinal) {
		base (span);
		this.name_span = name_span;
		this.identifier = name;
		this.owner = WeakRef (owner);
		this.semantic_type = semantic_type;
		this.ordinal = ordinal;
		this.member_ordinal = member_ordinal;
	}

}

public class CoreLazyObserve : CoreValue {
	private WeakRef property_identity;
	public CoreProperty? property_member { owned get { return (CoreProperty?) property_identity.get (); } }
	internal CoreLazyObserve (SourceSpan span, CoreProperty property_member) {
		base (span, property_member.semantic_type);
		this.property_identity = WeakRef (property_member);
	}

}

public abstract class CorePropertyAccessor : CoreFunction {
	private WeakRef parent;
	public CoreProperty? property_member { owned get { return (CoreProperty?) parent.get (); } }
	public CoreReceiver receiver { get; private set; }

	protected CorePropertyAccessor (SourceSpan span, SourceSpan name_span, string name, CoreProperty property_member, CoreReceiver receiver, SemanticType return_type, GenericArray<CoreParameter> parameters, GenericArray<CoreLocalPlace> locals, CoreBlock body, CoreCleanupContract? owned_cleanup = null) {
		base (span, name_span, name, return_type, parameters, locals, body, owned_cleanup);
		this.parent = WeakRef (property_member);
		this.receiver = receiver;
	}

}

public class CorePropertyGetter : CorePropertyAccessor {
	internal CorePropertyGetter (SourceSpan span, SourceSpan name_span, string name, CoreProperty property_member, CoreReceiver receiver, SemanticType return_type, GenericArray<CoreParameter> parameters, GenericArray<CoreLocalPlace> locals, CoreBlock body, CoreCleanupContract? owned_cleanup = null) {
		base (span, name_span, name, property_member, receiver, return_type, parameters, locals, body, owned_cleanup);
	}

}

public class CorePropertySetter : CorePropertyAccessor {
	internal CorePropertySetter (SourceSpan span, SourceSpan name_span, string name, CoreProperty property_member, CoreReceiver receiver, SemanticType return_type, GenericArray<CoreParameter> parameters, GenericArray<CoreLocalPlace> locals, CoreBlock body) {
		base (span, name_span, name, property_member, receiver, return_type, parameters, locals, body);
	}

}
}
