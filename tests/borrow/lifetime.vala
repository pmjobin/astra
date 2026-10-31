// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;

namespace Astra.Tests.Borrows {
private void parent_expiry() throws GLib.Error {
	LexicalRegion? root = new LexicalRegion (null, 0);
	LexicalRegion? child = new LexicalRegion (root, 1);
	var root_ref = WeakRef (root);
	var child_ref = WeakRef (child);
	assert (root.outlives (child) && !child.outlives (root));
	root = null;
	assert (root_ref.get () == null && child.parent == null && child.outlives (child));
	assert (!new LexicalRegion (null, 0).outlives (child));
	child = null;
	assert (child_ref.get () == null);
}

private void local_expiry() throws GLib.Error {
	CheckedProgram? program = check (REGION_SOURCE);
	LocalSymbol? local = program.functions[0].locals[2];
	var local_ref = WeakRef (local);
	var region_ref = WeakRef (local.lexical_region);
	var root_ref = WeakRef (program.functions[0].body.region);
	var parameter_ref = WeakRef (program.functions[0].symbol.parameters[0]);
	var block_ref = WeakRef (program.functions[0].body);
	program = null;
	assert (root_ref.get () == null && block_ref.get () == null && parameter_ref.get () == null);
	assert (local.lexical_region.parent == null && region_ref.get () != null);
	local = null;
	assert (local_ref.get () == null && region_ref.get () == null);
}

private void provenance_expiry() throws GLib.Error {
	CheckedProgram? program = check (REGION_SOURCE);
	CheckedAddressOfExpression? address = (CheckedAddressOfExpression) ((CheckedLocalDeclaration) ((CheckedIf) program.functions[0].body.statements[2]).else_body.statements[1]).initializer;
	BorrowProvenance? provenance = BorrowProvenance.for_expression (address);
	var provenance_ref = WeakRef (provenance);
	var address_ref = WeakRef (address);
	var local_ref = WeakRef (address.local);
	var child_ref = WeakRef (provenance.region);
	var root_ref = WeakRef (program.functions[0].body.region);
	program = null;
	assert (root_ref.get () == null && provenance.region.parent == null);
	address = null;
	assert (address_ref.get () == null && local_ref.get () != null);
	assert (provenance.origin.name == "inner" && provenance.region.ordinal == 3);
	provenance = null;
	assert (provenance_ref.get () == null && local_ref.get () == null && child_ref.get () == null);
}

private void stage_lifetime() throws GLib.Error {
	CheckedProgram? checked = check (fixture ("borrow-scopes"));
	var checked_ref = WeakRef (checked);
	var root_ref = WeakRef (checked.functions[0].body.region);
	var child_ref = WeakRef (((CheckedWhile) checked.functions[0].body.statements[2]).body.region);
	var local_ref = WeakRef (checked.functions[0].locals[0]);
	CoreProgram? core = CoreBuilder.build (checked);
	checked = null;
	assert (checked_ref.get () == null && root_ref.get () == null && child_ref.get () == null && local_ref.get () == null);
	CoreVerifier.verify (core);
	var core_ref = WeakRef (core);
	var core_place_ref = WeakRef (core.functions[0].locals[0]);
	CfgProgram? cfg = CfgBuilder.build (core);
	core = null;
	assert (core_ref.get () == null && core_place_ref.get () == null);
	CfgVerifier.verify (cfg);
	var cfg_ref = WeakRef (cfg);
	var cfg_place_ref = WeakRef (cfg.functions[0].locals[0]);
	SsaProgram? ssa = SsaBuilder.build (cfg);
	cfg = null;
	assert (cfg_ref.get () == null && cfg_place_ref.get () == null);
	SsaVerifier.verify (ssa);
	assert (!SsaDump.format (ssa).contains ("region"));
	var ssa_ref = WeakRef (ssa);
	var storage_ref = WeakRef (ssa.functions[0].storage[0]);
	var source_ref = WeakRef (ssa.span.file);
	NativeAbiProgram? nabi = NativeAbiBuilder.build (ssa);
	CAbiProgram? cabi = CAbiBuilder.build (ssa, nabi);
	ssa = null;
	assert (ssa_ref.get () == null && storage_ref.get () == null);
	NativeAbiVerifier.verify (nabi);
	CAbiVerifier.verify (cabi);
	nabi = null;
	cabi = null;
	assert (source_ref.get () == null);
}

private void register_lifetime() {
	add ("/borrow/lifetime/parent-expiry", parent_expiry);
	add ("/borrow/lifetime/local-expiry", local_expiry);
	add ("/borrow/lifetime/provenance-expiry", provenance_expiry);
	add ("/borrow/lifetime/stages", stage_lifetime);
}
}
