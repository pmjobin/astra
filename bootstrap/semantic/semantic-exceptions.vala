// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
namespace Astra.Semantic {
internal class ExceptionHandlerScope : Object {
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
public class CheckedCatch : Object {
	public LocalSymbol binding { get; private set; }
	public CheckedBlockStatement body { get; private set; }
	internal CheckedCatch (LocalSymbol binding, CheckedBlockStatement body) {
		this.binding = binding;
		this.body = body;
	}

}
public class CheckedTry : CheckedStatement {
	public CheckedBlockStatement body { get; private set; }
	public GenericArray<CheckedCatch> catches { get; private set; }
	public ClassType root_type { get; private set; }
	internal CheckedTry (SourceSpan span, CheckedBlockStatement body, GenericArray<CheckedCatch> catches, ClassType root_type) {
		base (span);
		this.body = body;
		this.catches = catches;
		this.root_type = root_type;
	}

}
public class CheckedThrow : CheckedStatement {
	public LocalSymbol owner { get; private set; }
	public CheckedConstructorObjectInitialization? construction { get; private set; }
	public ClassType root_type { get; private set; }
	public bool rethrows { get; private set; }
	internal CheckedThrow (SourceSpan span, LocalSymbol owner, ClassType root_type, bool rethrows, CheckedConstructorObjectInitialization? construction = null) {
		base (span);
		this.owner = owner;
		this.root_type = root_type;
		this.rethrows = rethrows;
		this.construction = construction;
	}

}
}
