// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
'use strict';
const vscode = require('vscode');
const {spawn} = require('child_process');

let client;

class Client {
	constructor(context) {
		this.output = vscode.window.createOutputChannel('Astra Language Server');
		this.diagnostics = vscode.languages.createDiagnosticCollection('astrac');
		context.subscriptions.push(this.output, this.diagnostics);
		this.pending = new Map();
		this.nextId = 1;
		this.buffer = Buffer.alloc(0);
		this.opened = new Set();
		const configuration = vscode.workspace.getConfiguration('astra');
		const server = configuration.get('serverPath', 'astra-lsp');
		const compiler = configuration.get('compilerPath', 'astrac');
		const args = [ '--compiler', compiler ];
		const scratch = configuration.get('scratchDirectory', '');
		if (scratch) args.push('--scratch-dir', scratch);
		this.process = server.endsWith('.py') ? spawn(configuration.get('pythonPath', 'python3'), [ server, ...args ]) : spawn(server, args);
		this.process.stdout.on('data', data => this.receive(data));
		this.process.stderr.on('data', data => this.output.append(data.toString()));
		this.process.on('error', error => this.fail(error));
		this.process.on('exit', code => this.fail(new Error(`Astra language server exited ${code}`)));
		this.ready = this.request('initialize', {
			                 processId : process.pid,
			                 rootUri : vscode.workspace.workspaceFolders?.[0]?.uri.toString() ?? null,
			                 capabilities : {general : {positionEncodings : [ 'utf-16' ]}}
		                 })
		                 .then(result => {
			                 if (result.capabilities.positionEncoding !== 'utf-16') throw new Error('Unsupported server position encoding');
			                 this.notify('initialized', {});
		                 });
		this.ready.catch(error => this.output.appendLine(error.message));
	}
	fail(error) {
		for (const [id, entry] of this.pending) {
			clearTimeout(entry.timer);
			entry.reject(error);
			this.pending.delete(id);
		}
		this.output.appendLine(error.message);
	}
	write(message) {
		const bytes = Buffer.from(JSON.stringify({jsonrpc : '2.0', ...message}), 'utf8');
		this.process.stdin.write(Buffer.concat([ Buffer.from(`Content-Length: ${bytes.length}\r\n\r\n`, 'ascii'), bytes ]));
	}
	notify(method, params) { this.write({method, params}); }
	request(method, params, token) {
		const id = this.nextId++;
		return new Promise((resolve, reject) => {
			const timer = setTimeout(() => { this.pending.delete(id); reject(new Error(`${method} timed out`)); }, 35000);
			this.pending.set(id, {resolve, reject, timer});
			const cancellation = token?.onCancellationRequested(() => this.notify('$/cancelRequest', {id}));
			const entry = this.pending.get(id);
			entry.resolve = value => { cancellation?.dispose(); resolve(value); };
			entry.reject = error => { cancellation?.dispose(); reject(error); };
			this.write({id, method, params});
		});
	}
	receive(data) {
		this.buffer = Buffer.concat([ this.buffer, data ]);
		while (true) {
			const end = this.buffer.indexOf('\r\n\r\n');
			if (end < 0) return;
			const match = /^Content-Length:\s*(\d+)\r?$/im.exec(this.buffer.subarray(0, end).toString('ascii'));
			if (!match || Number(match[1]) > 16 * 1024 * 1024) {
				this.fail(new Error('Invalid server frame'));
				this.process.kill();
				return;
			}
			const length = Number(match[1]);
			if (this.buffer.length < end + 4 + length) return;
			let message;
			try {
				message = JSON.parse(this.buffer.subarray(end + 4, end + 4 + length).toString('utf8'));
			} catch (error) {
				this.fail(error);
				this.process.kill();
				return;
			}
			this.buffer = this.buffer.subarray(end + 4 + length);
			if (message.id !== undefined) {
				const entry = this.pending.get(message.id);
				if (!entry) continue;
				this.pending.delete(message.id);
				clearTimeout(entry.timer);
				if (message.error)
					entry.reject(new Error(message.error.message));
				else
					entry.resolve(message.result);
			} else if (message.method === 'textDocument/publishDiagnostics') {
				const params = message.params;
				const document = vscode.workspace.textDocuments.find(d => d.uri.toString() === params.uri);
				if (document && params.version !== undefined && params.version !== document.version) continue;
				this.diagnostics.set(vscode.Uri.parse(params.uri), params.diagnostics.map(d => {
					const diagnostic = new vscode.Diagnostic(range(d.range), d.message, vscode.DiagnosticSeverity.Error);
					diagnostic.source = d.source;
					return diagnostic;
				}));
			} else if (message.method === 'window/logMessage')
				this.output.appendLine(message.params.message);
		}
	}
	async call(method, document, position, extra, token) {
		await this.ready;
		return this.request(method, {textDocument : {uri : document.uri.toString()}, ...(position ? {position} : {}), ...extra}, token);
	}
	async open(document) {
		if (document.languageId !== 'astra' || document.uri.scheme !== 'file') return;
		if (this.opened.has(document.uri.toString())) return;
		this.opened.add(document.uri.toString());
		await this.ready;
		this.notify('textDocument/didOpen', {textDocument : {uri : document.uri.toString(), languageId : 'astra', version : document.version, text : document.getText()}});
	}
	async stop() {
		try {
			await this.request('shutdown', {});
			this.notify('exit', {});
		} finally {
			const timer = setTimeout(() => this.process.kill(), 2000);
			timer.unref();
		}
	}
}

function range(value) {
	return new vscode.Range(value.start.line, value.start.character, value.end.line, value.end.character);
}
function locations(values) {
	return (values ?? []).map(value => new vscode.Location(vscode.Uri.parse(value.uri), range(value.range)));
}

async function activate(context) {
	client = new Client(context);
	const selector = {language : 'astra', scheme : 'file'};
	const report = error => client.output.appendLine(error.message);
	context.subscriptions.push(
	    vscode.workspace.onDidOpenTextDocument(document => client.open(document).catch(report)),
	    vscode.workspace.onDidChangeTextDocument(event => {
		    if (event.document.languageId === 'astra' && event.contentChanges.length) client.ready.then(() => client.notify('textDocument/didChange', {
				                                                                                      textDocument : {uri : event.document.uri.toString(), version : event.document.version},
				                                                                                      contentChanges : [ {text : event.document.getText()} ]
			                                                                                      }))
			                                                                              .catch(report);
	    }),
	    vscode.workspace.onDidCloseTextDocument(document => {
		    client.opened.delete(document.uri.toString());
		    if (document.languageId === 'astra') client.ready.then(() => client.notify('textDocument/didClose', {textDocument : {uri : document.uri.toString()}})).catch(report);
	    }),
	    vscode.languages.registerHoverProvider(selector, {async provideHover(document, position, token) {
		                                           const result = await client.call('textDocument/hover', document, position, {}, token);
		                                           return result ? new vscode.Hover(result.contents.value) : null;
		                                       }}),
	    vscode.languages.registerDefinitionProvider(selector, {async provideDefinition(document, position, token) {
		                                                return locations(await client.call('textDocument/definition', document, position, {}, token));
		                                            }}),
	    vscode.languages.registerReferenceProvider(selector, {async provideReferences(document, position, referenceContext, token) {
		                                               return locations(await client.call('textDocument/references', document, position, {context : referenceContext}, token));
		                                           }}),
	    vscode.languages.registerCompletionItemProvider(selector, {async provideCompletionItems(document, position, token) {
		                                                    const result = await client.call('textDocument/completion', document, position, {}, token);
		                                                    return result.items.map(i => { const item = new vscode.CompletionItem(i.label, vscode.CompletionItemKind.Variable); item.detail = i.detail; return item; });
		                                                }}),
	    vscode.languages.registerDocumentFormattingEditProvider(selector, {async provideDocumentFormattingEdits(document, options, token) {
		                                                            return (await client.call('textDocument/formatting', document, null, {options}, token)).map(e => new vscode.TextEdit(range(e.range), e.newText));
		                                                        }}));
	await client.ready;
	for (const document of vscode.workspace.textDocuments)
		await client.open(document);
}

async function deactivate() {
	if (client) await client.stop();
}
module.exports = {
	activate,
	deactivate
};
