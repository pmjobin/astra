// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;

namespace Astra.Tests.Ownbound {
private void stages() throws GLib.Error {
	CheckedProgram? checked = check (BASIC);
	var checked_parameter = WeakRef (checked.functions[0].symbol.parameters[0]);
	var checked_return = WeakRef (checked.functions[0].body.statements[0]);
	var checked_cleanup = WeakRef (checked.functions[0].symbol.owned_cleanup);
	CoreProgram? core = CoreBuilder.build (checked);
	checked = null;
	assert (checked_parameter.get () == null && checked_return.get () == null && checked_cleanup.get () == null);
	CoreVerifier.verify (core);
	var core_owner = WeakRef (core.functions[0].owned_locals[0]);
	var core_parameter = WeakRef (core.functions[0].parameters[0]);
	CfgProgram? control = CfgBuilder.build (core);
	core = null;
	assert (core_owner.get () == null && core_parameter.get () == null);
	CfgVerifier.verify (control);
	var cfg_owner = WeakRef (control.functions[0].locals[0]);
	var cfg_return = WeakRef (control.functions[0].entry.instructions[1]);
	var cfg_commit = WeakRef (control.functions[1].entry.instructions[3]);
	SsaProgram? ssa = SsaBuilder.build (control);
	control = null;
	assert (cfg_owner.get () == null && cfg_return.get () == null && cfg_commit.get () == null);
	SsaVerifier.verify (ssa);
	var parameter = WeakRef (ssa.functions[0].parameters[0]);
	var type = WeakRef (ssa.handles[0].semantic_type);
	var cleanup = WeakRef (ssa.functions[0].owned_cleanup);
	var nabi = NativeAbiBuilder.build (ssa);
	var cabi = CAbiBuilder.build (ssa, nabi);
	ssa = null;
	assert (parameter.get () == null && type.get () == null && cleanup.get () == null);
	NativeAbiVerifier.verify (nabi);
	CAbiVerifier.verify (cabi);
}

private void register_lifetime() {
	add ("/ownbound/lifetime/stage-boundaries", stages);
}

}
