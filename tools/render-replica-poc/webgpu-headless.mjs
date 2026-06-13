// webgpu-headless.mjs — stand up a browser-compatible WebGPU global in Node via Dawn.
//
// The `webgpu` npm package (Dawn N-API bindings) gives us a real WebGPU
// implementation that runs headless (no canvas, no swap-chain). It exposes:
//   create([...flags]) -> a GPU object (=== navigator.gpu)
//   globals            -> all the GPU* constructor classes + flag enums
//                         (GPUBufferUsage, GPUTextureUsage, GPUShaderStage, GPUColorWrite, ...)
//
// The project's render modules (pvr2-renderer.mjs / texture-manager.mjs /
// ta-parser.mjs / shaders.mjs) are pure WebGPU + typed-array code EXCEPT for
// PVR2Renderer.init()/initShared() which touch a real <canvas> (getContext,
// configure, getCurrentTexture). We never call those: we call _init() directly
// and render through renderFrame()'s `renderTarget` offscreen path, which needs
// no canvas. So installing these globals is sufficient to run the GOLD-STANDARD
// rasterizer VERBATIM.
//
// NOTE: imported for side effects (installs onto globalThis) BEFORE any module
// that references GPUBufferUsage etc. at import/instantiation time.
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const webgpu = require('webgpu');

// Install all GPU* classes + flag enums onto globalThis so the unchanged
// modules resolve GPUBufferUsage/GPUTextureUsage/GPUShaderStage/GPUColorWrite.
for (const [k, v] of Object.entries(webgpu.globals)) {
    if (globalThis[k] === undefined) globalThis[k] = v;
}

// Dawn flags: enable timestamp/debug as needed. [] = defaults.
const gpu = webgpu.create([]);

// Provide a browser-shaped navigator.gpu (PVR2Renderer.init reads navigator.gpu;
// _init does not, but keep parity so the same code path works if ever exercised).
if (!globalThis.navigator) globalThis.navigator = {};
if (!globalThis.navigator.gpu) {
    Object.defineProperty(globalThis.navigator, 'gpu', { value: gpu, configurable: true });
}

// performance.now() is used by pvr2-renderer for the effect-time uniform.
if (!globalThis.performance) globalThis.performance = { now: () => Number(process.hrtime.bigint() / 1000n) / 1000 };

export async function initDevice() {
    const adapter = await gpu.requestAdapter({ powerPreference: 'high-performance' });
    if (!adapter) throw new Error('No WebGPU adapter (Dawn). Check GPU/driver availability.');
    const device = await adapter.requestDevice();
    const info = adapter.info || (adapter.requestAdapterInfo && await adapter.requestAdapterInfo()) || {};
    return { gpu, adapter, device, info };
}

export { gpu };
