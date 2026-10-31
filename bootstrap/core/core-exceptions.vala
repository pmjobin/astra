// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Semantic;
namespace Astra.Core {
internal class CoreExceptionHandlerScope : Object {
	internal GenericArray<ClassType> bounds = new GenericArray<ClassType> ();
	internal GenericArray<ClassType> effects = new GenericArray<ClassType> ();
	internal GenericArray<ClassType> incoming(int index) {
		var result = new GenericArray<ClassType> ();
		foreach (var effect in effects) {
			bool consumed = false;
			for (int p = 0; p < index; p++) {
				if (effect.derives_from (bounds[p])) {
					consumed = true;
				}
			}
			if (!consumed && (effect.derives_from (bounds[index]) || bounds[index].derives_from (effect))) {
				result.add (effect.derives_from (bounds[index]) ? effect : bounds[index]);
			}
		}
		if (result.length == 0) {
			result.add (bounds[index]);
		}
		return result;
	}
}
public class CoreDiscardOwnedSuccess : CoreCallStatement {
	public CoreCleanupContract cleanup { get; private set; }
	internal CoreDiscardOwnedSuccess (SourceSpan span, CoreFunction target, GenericArray<CoreValue> arguments, CoreValue? receiver, CoreCleanupContract cleanup) {
		base (span, target, arguments, receiver);
		this.cleanup = cleanup;
	}
}
public class CoreCatch : Object {
	public CoreLocalPlace binding { get; private set; }
	public CoreBlock body { get; private set; }
	internal CoreCatch (CoreLocalPlace binding, CoreBlock body) {
		this.binding = binding;
		this.body = body;
	}
}
public class CoreTry : CoreStatement {
	private GenericArray<CoreCatch> ordered_catches = new GenericArray<CoreCatch> ();
	public CoreBlock body { get; private set; }
	public GenericArray<CoreCatch> catches { get; private set; }
	public CoreCleanupContract cleanup { get; private set; }
	internal CoreTry (SourceSpan span, CoreBlock body, GenericArray<CoreCatch> catches, CoreCleanupContract cleanup) {
		base (span);
		this.body = body;
		this.catches = catches;
		this.cleanup = cleanup;
		foreach (var caught in catches) {
			ordered_catches.add (caught);
		}
	}
	internal bool matches_catches() {
		if (catches.length != ordered_catches.length) {
			return false;
		}
		for (int c = 0; c < catches.length; c++) {
			if (catches[c] != ordered_catches[c]) {
				return false;
			}
		}
		return true;
	}
}
public class CoreThrow : CoreStatement {
	public CoreLocalPlace source { get; private set; }
	public CoreOwnedLocal? owner { get; private set; }
	public CoreCleanupContract cleanup { get; private set; }
	public bool rethrows { get { return owner == null; } }
	internal CoreThrow (SourceSpan span, CoreLocalPlace source, CoreOwnedLocal? owner, CoreCleanupContract cleanup) {
		base (span);
		this.source = source;
		this.owner = owner;
		this.cleanup = cleanup;
	}
}
public class CoreForeignReturn : CoreReturn {
	public ForeignImportBinding binding { get; internal set; }
	public CoreFunction factory { get; internal set; }
	public GenericArray<CoreOwnedLocal> consumed { get; private set; default = new GenericArray<CoreOwnedLocal> (); }
	internal CoreForeignReturn (SourceSpan span, ForeignImportBinding binding, CoreFunction factory, GenericArray<CoreOwnedLocal>? consumed = null) {
		base (span, null);
		this.binding = binding;
		this.factory = factory;
		if (consumed != null) {
			foreach (var owner in consumed) {
				this.consumed.add (owner);
			}
		}
	}
}
public class CoreForeignSignalReturn : CoreReturn {
	public ForeignSignalBinding binding { get; internal set; }
	internal CoreForeignSignalReturn (SourceSpan span, ForeignSignalBinding binding) {
		base (span, null);
		this.binding = binding;
	}
}

}
