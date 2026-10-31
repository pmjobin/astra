// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;
using Astra.Core;

namespace Astra.Tests.CoreStandalone {
private CoreProgram control_model() {
	var span = SourceSpan (new SourceFile.from_text ("control.astra", ""), 0, 0);
	var types = new BuiltinTypes ();
	var condition = new CoreBooleanValue (span, types.bool_type, BooleanLiteral.TRUE);
	var outer = new CoreLoopTarget (span, 0);
	var inner = new CoreLoopTarget (span, 1);
	var inner_body = new CoreBlock (span, new GenericArray<CoreStatement> ());
	inner_body.statements.add (new CoreContinue (span, inner));
	inner_body.statements.add (new CoreBreak (span, inner));
	var outer_body = new CoreBlock (span, new GenericArray<CoreStatement> ());
	outer_body.statements.add (new CoreWhile (span, inner, condition, inner_body));
	outer_body.statements.add (new CoreBreak (span, outer));
	outer_body.statements.add (new CoreContinue (span, outer));
	var body = new CoreBlock (span, new GenericArray<CoreStatement> ());
	body.statements.add (new CoreWhile (span, outer, condition, outer_body));
	var functions = new GenericArray<CoreFunction> ();
	functions.add (new CoreFunction (span, span, "f", types.void_type, new GenericArray<CoreParameter> (), new GenericArray<CoreLocalPlace> (), body));
	return new CoreProgram (span, functions);
}

private void control_lifetime() {
	try {
		CoreProgram? program = control_model ();
		var targets = new GenericArray<CoreStatement> ();
		var outer_ref = WeakRef (((CoreWhile) program.functions[0].body.statements[0]).target);
		WeakRef inner_ref;
		{
			var outer = (CoreWhile) program.functions[0].body.statements[0];
			var inner = (CoreWhile) outer.body.statements[0];
			inner_ref = WeakRef (inner.target);
			targets.add (outer.body.statements[1]);
			targets.add (outer.body.statements[2]);
			targets.add (inner.body.statements[0]);
			targets.add (inner.body.statements[1]);
			assert (((CoreContinue) inner.body.statements[0]).target == inner.target && inner.target != outer.target);
		}
		CoreVerifier.verify (program);
		assert (CoreDump.format (program).contains ("(break #1)"));
		program = null;
		assert (outer_ref.get () == null && inner_ref.get () == null);
		for (int i = 0; i < targets.length; i++) {
			var target = (targets[i] is CoreBreak) ? ((CoreBreak) targets[i]).target : ((CoreContinue) targets[i]).target;
			assert (target == null);
		}
	} catch (CoreError error) {
		GLib.error ("Standalone control lifetime: %s", error.message);
	}
}

private void invalid_control_targets() {
	for (int kind = 0; kind < 7; kind++) {
		foreach (bool is_break in new bool[] {true, false}) {
			var program = control_model ();
			var function = program.functions[0];
			var outer = (CoreWhile) function.body.statements[0];
			var inner = (CoreWhile) outer.body.statements[0];
			CoreLoopTarget? foreign = new CoreLoopTarget (outer.span, 0);
			string expected;
			if (kind <= 2) {
				inner.body.statements[0] = is_break ? (CoreStatement) new CoreBreak (inner.span, foreign) : new CoreContinue (inner.span, foreign);
				if (kind == 0) {
					foreign = null;
				} else if (kind == 2) {
					var body = new CoreBlock (outer.span, new GenericArray<CoreStatement> ());
					body.statements.add (new CoreWhile (outer.span, foreign, outer.condition, new CoreBlock (outer.span, new GenericArray<CoreStatement> ())));
					program.functions.add (new CoreFunction (function.span, function.name_span, "g", function.return_type, new GenericArray<CoreParameter> (), new GenericArray<CoreLocalPlace> (), body));
				}
				expected = kind == 0 ? "loop-control target is expired" : "not owned by the containing function";
			} else if (kind == 3) {
				outer.body.statements[0] = new CoreWhile (inner.span, outer.target, inner.condition, inner.body);
				expected = "repeated loop-target identity";
			} else if (kind == 4) {
				outer.body.statements[0] = new CoreWhile (inner.span, foreign, inner.condition, inner.body);
				expected = "loop-target ordinal";
			} else if (kind == 5) {
				function.body.statements.add (is_break ? (CoreStatement) new CoreBreak (outer.span, outer.target) : new CoreContinue (outer.span, outer.target));
				expected = "does not enclose the transfer";
			} else {
				var body = new CoreBlock (outer.span, new GenericArray<CoreStatement> ());
				body.statements.add (new CoreWhile (outer.span, outer.target, outer.condition, new CoreBlock (outer.span, new GenericArray<CoreStatement> ())));
				program.functions.add (new CoreFunction (function.span, function.name_span, "g", function.return_type, new GenericArray<CoreParameter> (), new GenericArray<CoreLocalPlace> (), body));
				expected = "repeated loop-target identity";
			}
			for (int repeat = 0; repeat < 2; repeat++) {
				try {
					CoreDump.format (program);
					GLib.error ("Invalid Core target case %d accepted", kind);
				} catch (CoreError error) {
					assert (error.code == CoreError.INVALID_IR && error.message.contains (expected));
				}
			}
		}
	}
}

private void register_loop_control_tests() {
	Test.add_func ("/core-standalone/loopctrl/identities-lifetime-expiry", control_lifetime);
	Test.add_func ("/core-standalone/loopctrl/invalid-targets", invalid_control_targets);
}
}
