// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Core;

namespace Astra.Tests.ObjectAllocationLoans {
private const string LABEL = "class Label{readonly string text;init(string text){this.text=text;}}";
private void moved_into_loan_scope(string source, int function_ordinal, bool returned) {
	try {
		var parsed = Parser.parse (new SourceFile.from_text ("loan-control", LABEL + source));
		assert (parsed.diagnostic == null);
		var checked = SemanticAnalyzer.analyze (parsed.unit);
		assert (checked.diagnostic == null);
		var program = CoreBuilder.build (checked.program);
		CoreVerifier.verify (program);
		var root = program.functions[function_ordinal].body;
		CoreBlock? scope = null;
		int position = -1;
		for (int i = 0; i < root.statements.length; i++) {
			var statement = root.statements[i];
			if (statement is CoreScope) {
				scope = ((CoreScope) statement).body;
			}
			var init = statement as CoreInitialize;
			if ((returned && statement is CoreOwnershipReturn) || (!returned && init != null && (init.value is CoreNumericConversionValue || init.value is CoreIntegerConversionValue || init.value is CoreFloatConversionValue))) {
				position = i;
			}
		}
		assert (scope != null && position >= 0);
		// Change only the evaluation position of an otherwise valid consuming
		// expression: its original position follows the loan's lexical end.
		var moved = root.statements[position];
		root.statements.remove_index (position);
		scope.statements.add (moved);
		bool rejected = false;
		try {
			CoreVerifier.verify (program);
		} catch (CoreError error) {
			rejected = error.message.contains ("receiver invalidation overlaps a surviving stored text loan");
		}
		assert (rejected);
		scope.statements.remove_index (scope.statements.length - 1);
		root.statements.insert (position, moved);
		CoreVerifier.verify (program);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void conversion(string result_type, string result, string conversion_type) {
	moved_into_loan_scope (result_type + " consume(owned Label label){return " + result + ";}int main(){var first=new Label(\"x\");{var view=first.text;}var number=consume(move first) as " + conversion_type + ";return 42;}", 1, false);
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/obj-alloc-1/loan/numeric-conversion", () => { conversion ("int", "0", "f64");
	});
	Test.add_func ("/obj-alloc-1/loan/integer-conversion", () => { conversion ("int", "0", "i8");
	});
	Test.add_func ("/obj-alloc-1/loan/float-conversion", () => { conversion ("f64", "0.0d", "f32");
	});
	Test.add_func ("/obj-alloc-1/loan/owner-return", () => { moved_into_loan_scope ("owned Label pass(owned Label label){{var view=label.text;}return move label;}int main(){return 42;}", 0, true);
	});
	Test.add_func ("/obj-alloc-1/loan/owner-result-return", () => { moved_into_loan_scope ("owned Label transfer(owned Label label){return move label;}owned Label pass(owned Label label){{var view=label.text;}return transfer(move label);}int main(){return 42;}", 1, true);
	});
	return Test.run ();
}

}
