# Generated API example

[minmax.json](minmax.json) is actual compiler output from the current
`lib/astra/base/order.astra`, including its source hash, semantic generic
constraints, checked links and named positive/negative examples. Its build
fingerprint identifies the recorded source/toolchain build; it is not an
executable hash or a promise that future builds have the same metadata.

Render it without native tools:

```sh
python3 -B tools/docs/render.py docs/api/examples/minmax.json --output /absolute/build/minmax.html
```

The JSON adapter uses the separately authored `tools/docs/api.css`, or an
explicit `--stylesheet` file. The full generated library/compiler previews and
their actual generation, schema, native example and memory receipts belong in
the external task build/runtime directories and delivered evidence. This small
snapshot is a reviewable integration example, not a separate source of API truth.
