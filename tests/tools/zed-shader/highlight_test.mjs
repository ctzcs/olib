import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { Parser, Language, Query } from '../../../library/tmp/zed-shader-toolchain/node_modules/web-tree-sitter/tree-sitter.js';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');
await Parser.init();
const wasmPath = path.join(root, 'build/zed-shader/grammars/olib_shader.wasm');
const imports = WebAssembly.Module.imports(new WebAssembly.Module(fs.readFileSync(wasmPath)));
assert.ok(imports.every(item => item.module === 'env' && item.kind !== 'function'),
  `Grammar must not import WASI program startup functions: ${JSON.stringify(imports)}`);
const language = await Language.load(wasmPath);
const parser = new Parser();
parser.setLanguage(language);
const source = `Shader "Test" {
Properties {
  [Id("speed")] [Step(0.1)] _Speed ("速度", Range(0,5)) = 1
  _Tint ("Tint", Color) = (1,1,1,1)
  _Image ("Image", 2D) = ""
}
HLSLINCLUDE
// ENDHLSL
/*
ENDHLSL
*/
float4 shared(float2 uv) { return float4(uv, 0, 1); }
ENDHLSL
Pass "main" {
  Draw Fullscreen
  Target { Scale 0.5 Format Float16 }
  Input _Image "color" Previous
  HLSLPROGRAM
  const char* text = "ENDHLSL";
  float4 fragment_main(float2 uv : TEXCOORD0) : SV_Target0 { return shared(uv); }
  ENDHLSL
}
}`;
const tree = parser.parse(source);
assert.equal(tree.rootNode.hasError, false, tree.rootNode.toString());
const blocks = tree.rootNode.descendantsOfType('hlsl_content');
assert.equal(blocks.length, 2);
assert.match(blocks[0].text, /\/\*\nENDHLSL\n\*\//);
assert.match(blocks[1].text, /fragment_main/);
assert.doesNotMatch(blocks[1].text, /\n\s*ENDHLSL/);
const queries = path.join(root, 'tools/zed-shader/languages/olib-shader');
for (const filename of fs.readdirSync(queries).filter(name => name.endsWith('.scm'))) {
  const query = new Query(language, fs.readFileSync(path.join(queries, filename), 'utf8'));
  const captures = query.captures(tree.rootNode);
  assert.ok(captures.length, `${filename} should capture real syntax`);
  if (filename === 'highlights.scm') {
    assert.ok(captures.some(c => c.name === 'keyword' && c.node.text === 'Properties'));
    assert.ok(captures.some(c => c.name === 'property' && c.node.text === '_Speed'));
  }
  query.delete();
}
for (const tail of ['\n', '\r\n', '']) {
  const end = parser.parse(`Shader "E" { Pass "p" { HLSLPROGRAM\nfloat x;\nENDHLSL${tail}\n} }`);
  assert.equal(end.rootNode.hasError, false, end.rootNode.toString());
  end.delete();
}
const sample = path.resolve(root, '../olib_sample/src/shader_lab/shaders/Unified.oshader');
if (fs.existsSync(sample)) {
  const sampleTree = parser.parse(fs.readFileSync(sample, 'utf8'));
  assert.equal(sampleTree.rootNode.hasError, false, sampleTree.rootNode.toString());
  assert.equal(sampleTree.rootNode.descendantsOfType('hlsl_content').length, 3);
  sampleTree.delete();
}
tree.delete();
parser.delete();
console.log('PASS: grammar, HLSL boundaries, highlights, injections, outline, brackets, sample');
