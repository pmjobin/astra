// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Vapi;
using Astra.Core;
using Astra.Cfg;

namespace Astra.Tests.ObjectOwnCleanup {
private void ordering() {
	try {
		string text;
		FileUtils.get_contents ("tests/obj-own/fixtures/obj-own-order.astra", out text);
		string api;
		FileUtils.get_contents ("tests/obj-life/fixtures/lifecycle.vapi", out api);
		var parsed = Parser.parse (new SourceFile.from_text ("order", text));
		var vapi = VapiParser.parse (new SourceFile.from_text ("lifecycle.vapi", api));
		assert (parsed.diagnostic == null && vapi.diagnostic == null);
		var checked = SemanticAnalyzer.analyze (parsed.unit, VapiNormalizer.normalize (vapi.file), VapiNormalizer.normalize_handles (vapi.file));
		assert (checked.diagnostic == null);
		var core = CoreBuilder.build (checked.program);
		var cfg = CfgBuilder.build (core);
		assert (CfgFlowChecker.check (cfg).diagnostic == null);
		var consume = cfg.functions[0];
		var sequence = new StringBuilder ();
		bool return_expression_seen = false;
		foreach (var instruction in consume.entry.instructions) {
			var foreign = instruction as CfgCCallInstruction;
			if (foreign != null && foreign.target.name == "life_record") {
				return_expression_seen = true;
				sequence.append ("return ");
			}
			var cleanup = instruction as CfgCleanupInstruction;
			if (cleanup != null) {
				var owner = (CfgLocalPlace) ((CfgLoadValue) cleanup.value).source;
				sequence.append (owner.name + " ");
				assert (cleanup.cleanup == owner.cleanup);
				assert (owner.name == "nested" || return_expression_seen);
			}
			var fixed_cleanup = instruction as CfgLifecycleCallInstruction;
			if (fixed_cleanup != null && !fixed_cleanup.constructs) {
				assert (return_expression_seen && !fixed_cleanup.storage.transferable);
				sequence.append ("fixed ");
			}
		}
		assert (sequence.str == "nested return resource local fixed c b a ");
		assert (core.functions[0].owned_locals[0].place.incoming_parameter == core.functions[0].parameters[0]);
		assert (core.functions[0].owned_locals[1].place.incoming_parameter == core.functions[0].parameters[1]);
		assert (core.functions[0].owned_locals[2].place.incoming_parameter == core.functions[0].parameters[2]);
		assert (core.functions[0].object_storage[0].transferable == false && core.functions[0].object_storage[1].transferable && core.functions[0].object_storage[2].transferable);
	} catch (GLib.Error e) {
		GLib.error ("%s", e.message);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/obj-own/cleanup/shared-fixed-object-owner-resource-and-parameter-order", ordering);
	return Test.run ();
}

}
