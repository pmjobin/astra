// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
'use strict';
const vscode = require('vscode');
const assert = require('assert');
const fs = require('fs');
const path = require('path');

async function run() {
	const root = vscode.workspace.workspaceFolders[0].uri.fsPath;
	const receipt = {client : `Visual Studio Code ${vscode.version}`, checks : []};
	const save = () => fs.writeFileSync(path.join(root, '..', 'editor-receipt.json'), JSON.stringify(receipt, null, 2));
	const check = (condition, label) => { assert(condition, label); receipt.checks.push(label); save(); };
	const delay = ms => new Promise(resolve => setTimeout(resolve, ms));

	async function until(predicate) {
		const deadline = Date.now() + 30000;
		while (Date.now() < deadline) {
			if (await predicate()) return;
			await delay(150);
		}
		throw new Error('Editor integration timed out');
	}

	const extension = vscode.extensions.getExtension('astra-lang.astra-language-tools');
	check(extension, 'actual Astra editor extension discovered');
	await extension.activate();
	const uri = vscode.Uri.file(path.join(root, 'main.astra'));
	const library = vscode.Uri.file(path.join(root, 'library.astra'));
	const original = fs.readFileSync(uri.fsPath, 'utf8');
	const document = await vscode.workspace.openTextDocument(uri);
	await vscode.window.showTextDocument(document);
	const position = document.positionAt(original.indexOf('answer(cell') + 1);
	let hovers = [];
	await until(async () => {
		hovers = await vscode.commands.executeCommand('vscode.executeHoverProvider', uri, position);
		return hovers?.some(h => h.contents.some(c => (c.value ?? c).includes('Editor14.answer')));
	});
	check(true, 'compiler-backed cross-file hover through actual editor provider');
	const definitions = await vscode.commands.executeCommand('vscode.executeDefinitionProvider', uri, position);
	check(definitions.length === 1 && definitions[0].uri.toString() === library.toString(), 'definition preserves exact namespace identity');
	const references = await vscode.commands.executeCommand('vscode.executeReferenceProvider', uri, position);
	check(references.some(r => r.uri.toString() === uri.toString() && r.range.start.character === position.character - 1), 'UTF-16 reference after astral comment');
	const completion = await vscode.commands.executeCommand('vscode.executeCompletionItemProvider', uri, position);
	check(completion.items.some(i => i.label === 'Editor14.answer'), 'real editor completion');
	const libraryDocument = await vscode.workspace.openTextDocument(library);
	const classPosition = libraryDocument.positionAt(libraryDocument.getText().indexOf('Cell {') + 1);
	const policies = await vscode.commands.executeCommand('vscode.executeHoverProvider', library, classPosition);
	check(policies.some(h => h.contents.some(c => (c.value ?? c).includes('assignment moves'))), 'Shared ownership policy visible in editor');

	async function replace(text) {
		const edit = new vscode.WorkspaceEdit();
		edit.replace(uri, new vscode.Range(document.positionAt(0), document.positionAt(document.getText().length)), text);
		assert(await vscode.workspace.applyEdit(edit));
	}

	await replace(original.replace('answer(cell', 'missing(cell'));
	await until(() => vscode.languages.getDiagnostics(uri).some(d => d.message.includes('missing')));
	check(true, 'unsaved editor change produces compiler diagnostic');
	check(fs.readFileSync(uri.fsPath, 'utf8') === original, 'diagnostics do not write user source');
	await replace(original);
	await until(() => vscode.languages.getDiagnostics(uri).length === 0);
	check(true, 'repaired unsaved document clears diagnostic');
	await replace(original.replace(/\t/g, '    '));
	const edits = await vscode.commands.executeCommand('vscode.executeFormatDocumentProvider', uri, {tabSize : 4, insertSpaces : false});
	receipt.formatEdits = edits;
	save();
	check(edits.length > 0, 'real editor formatter supplies compiler formatting edits');
	const formatting = new vscode.WorkspaceEdit();
	formatting.set(uri, edits);
	assert(await vscode.workspace.applyEdit(formatting));
	check(document.getText() === original, 'formatted document matches original semantic source');
	const idempotent = await vscode.commands.executeCommand('vscode.executeFormatDocumentProvider', uri, {tabSize : 4, insertSpaces : false});
	check(idempotent === undefined || idempotent.length === 0, 'formatter is idempotent in actual editor');
	check(fs.readFileSync(uri.fsPath, 'utf8') === original, 'editor test left source files unchanged');
	receipt.status = 'PASS';
	save();
}

module.exports = {run};
