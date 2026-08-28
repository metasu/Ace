import { McpError, ErrorCode } from '@modelcontextprotocol/sdk/types.js';
import axios from 'axios';
import fs from 'fs';
import path from 'path';
import { randomUUID } from 'crypto';
import FormData from 'form-data';
import { unlink } from 'fs/promises';
import { ensureDirectoryExists, downloadFile, isValidHttpUrl } from '../utils/index.js';

/**
 * AtlasCloud native image MCP (patched)
 * - POST {API_URL}/api/v1/model/generateImage
 * - poll GET {API_URL}/api/v1/model/prediction/{id} until completed/failed
 * - local images: POST {API_URL}/api/v1/model/uploadMedia → download_url → images[]
 * - NO moderation param (0-review client-side)
 * Profile: seedream-t2i
 */

const PROFILE = 'seedream-t2i';

function rootBase(apiUrl) {
  return String(apiUrl || '').replace(/\/+$/, '').replace(/\/(api|v1)$/,'');
}

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

function authHeaders(config, extra = {}) {
  return { Authorization: `Bearer ${config.apiKey}`, ...extra };
}

function defaultModel(config, args) {
  if (args.model) return args.model;
  const img = config.defaultImageConfig?.model || process.env.DEFAULT_IMAGE_MODEL;
  const edit = config.defaultEditImageModel || process.env.DEFAULT_EDIT_IMAGE_MODEL;
  // upstream config always sets defaultEditImageModel='gpt-image-1' — ignore that generic default
  const editUseful = edit && edit !== 'gpt-image-1' ? edit : null;
  if (PROFILE === 'seedream-t2i') return img || editUseful;
  // edit-oriented profiles prefer specialized edit model, then image model
  return editUseful || img || edit;
}

function toSeedreamSize(args, config) {
  // Seedream requires WIDTH*HEIGHT and total pixels >= 3686400 (~1920*1920)
  if (args.size && String(args.size).includes('*')) return String(args.size);
  if (args.size && String(args.size).includes('x')) {
    const [w, h] = String(args.size).toLowerCase().split('x');
    if (w && h) return `${w}*${h}`;
  }
  const w = Number(args.width || config.defaultImageConfig?.width || 2048);
  const h = Number(args.height || config.defaultImageConfig?.height || 2048);
  let W = w, H = h;
  if (W * H < 3686400) {
    // bump to 2048*2048 minimum safe default
    W = 2048; H = 2048;
  }
  return `${W}*${H}`;
}

function toWanSize(args) {
  // Wan uses preset tiers 1K / 2K
  const s = String(args.size || args.wan_size || '2K').toUpperCase();
  if (s === '1K' || s === '2K') return s;
  // map pixel sizes roughly
  if (args.width && args.height) {
    const px = Number(args.width) * Number(args.height);
    return px >= 1500 * 1500 ? '2K' : '1K';
  }
  return '2K';
}

function isGenerateImageArgs(args) {
  return args && typeof args.prompt === 'string';
}
function isEditImageArgs(args) {
  return args && typeof args.prompt === 'string' && (typeof args.image === 'string' || Array.isArray(args.images));
}

async function uploadLocalImage(config, localPath) {
  const form = new FormData();
  form.append('file', fs.createReadStream(localPath));
  const url = `${rootBase(config.apiUrl)}/api/v1/model/uploadMedia`;
  const resp = await axios.post(url, form, {
    headers: { ...authHeaders(config), ...form.getHeaders() },
    timeout: config.requestTimeout,
    maxBodyLength: Infinity,
    maxContentLength: Infinity,
  });
  const data = resp.data?.data || resp.data || {};
  const downloadUrl = data.download_url || data.url;
  if (!downloadUrl) {
    throw new Error(`uploadMedia failed: ${JSON.stringify(resp.data).slice(0, 400)}`);
  }
  return downloadUrl;
}

async function resolveImageUrls(config, imageOrList) {
  const list = Array.isArray(imageOrList) ? imageOrList : [imageOrList];
  const out = [];
  const cleanups = [];
  for (const item of list) {
    if (!item) continue;
    if (isValidHttpUrl(item)) {
      out.push(item);
      continue;
    }
    // local path
    const p = path.isAbsolute(item) ? item : path.resolve(item);
    if (!fs.existsSync(p)) {
      throw new McpError(ErrorCode.InvalidParams, `Image not found: ${item}`);
    }
    const url = await uploadLocalImage(config, p);
    out.push(url);
  }
  return { urls: out, cleanups };
}

async function submitGenerate(config, body) {
  const url = `${rootBase(config.apiUrl)}/api/v1/model/generateImage`;
  console.error('[atlascloud-mcp] generateImage', url, JSON.stringify({ ...body, prompt: String(body.prompt || '').slice(0, 120) }));
  const resp = await axios.post(url, body, {
    headers: authHeaders(config, { 'Content-Type': 'application/json' }),
    timeout: config.requestTimeout,
  });
  return resp.data;
}

async function pollPrediction(config, submitJson) {
  const data = submitJson?.data || submitJson || {};
  const id = data.id || data.prediction_id;
  let getUrl = data?.urls?.get;
  if (!getUrl) {
    if (!id) throw new Error(`No prediction id in response: ${JSON.stringify(submitJson).slice(0, 500)}`);
    getUrl = `${rootBase(config.apiUrl)}/api/v1/model/prediction/${id}`;
  }
  const started = Date.now();
  const timeout = config.requestTimeout || 600000;
  let attempt = 0;
  while (Date.now() - started < timeout) {
    attempt += 1;
    const pr = await axios.get(getUrl, {
      headers: authHeaders(config),
      timeout: Math.min(60000, timeout),
      validateStatus: () => true,
    });
    const pj = pr.data;
    const dd = pj?.data || pj || {};
    const st = String(dd.status || dd.state || '').toLowerCase();
    const outs = dd.outputs;
    const err = dd.error || pj?.message || '';
    console.error(`[atlascloud-mcp] poll#${attempt} status=${st} outputs=${Array.isArray(outs) ? outs.length : 0}`);
    if (Array.isArray(outs) && outs.length > 0) {
      return { ok: true, outputs: outs, raw: pj };
    }
    if (['failed', 'error', 'canceled', 'cancelled'].includes(st) || (pr.status >= 400 && st !== 'processing' && st !== 'pending' && st !== 'running' && st !== 'queued')) {
      throw new Error(err || `prediction failed: ${JSON.stringify(pj).slice(0, 800)}`);
    }
    if (['completed', 'succeeded', 'success'].includes(st) && (!outs || outs.length === 0)) {
      // completed but empty
      throw new Error(`prediction ${st} but empty outputs: ${JSON.stringify(pj).slice(0, 800)}`);
    }
    await sleep(2000);
  }
  throw new Error(`prediction poll timeout after ${timeout}ms id=${id}`);
}

async function saveOutputs(config, outputs, prefix) {
  const imagesOutputDir = path.join(config.audioOutputDir, 'images');
  await ensureDirectoryExists(imagesOutputDir);
  const results = [];
  for (const item of outputs) {
    let url = null;
    if (typeof item === 'string') url = item;
    else if (item && typeof item === 'object') url = item.url || item.image_url || item.download_url;
    if (!url) {
      results.push({ error: 'unknown output item', item });
      continue;
    }
    const ext = path.extname(new URL(url).pathname) || '.jpg';
    const filename = `${prefix}_${randomUUID()}${ext}`;
    const localPath = path.join(imagesOutputDir, filename);
    try {
      await downloadFile(url, localPath);
      results.push({ local_path: localPath, source_url: url });
    } catch (e) {
      results.push({ source_url: url, error: e.message });
    }
  }
  return results;
}

function buildText2ImgBody(config, args) {
  const model = defaultModel(config, args);
  const body = {
    model,
    prompt: args.prompt,
  };
  if (PROFILE === 'seedream-t2i' || PROFILE === 'seedream-edit' || PROFILE === 'seedream-edit-seq') {
    body.size = toSeedreamSize(args, config);
    if (args.output_format) body.output_format = args.output_format;
    if (PROFILE === 'seedream-edit-seq') {
      const mi = args.max_images || args.n;
      if (mi) body.max_images = Number(mi);
    }
  } else if (PROFILE === 'wan-edit' || PROFILE === 'wan-edit-pro') {
    body.size = toWanSize(args);
    if (args.n) body.n = Number(args.n);
    if (typeof args.thinking_mode === 'boolean') body.thinking_mode = args.thinking_mode;
    else body.thinking_mode = true;
  }
  // never send moderation
  return body;
}

function buildEditBody(config, args, imageUrls) {
  const body = buildText2ImgBody(config, args);
  body.images = imageUrls;
  body.model = defaultModel(config, args);
  return body;
}

export async function handleToolCall({ toolName, args, config, axiosInstance }) {
  try {
    switch (toolName) {
      case 'generate_image': {
        if (!isGenerateImageArgs(args)) {
          throw new McpError(ErrorCode.InvalidParams, 'Invalid parameters for generate_image (prompt required)');
        }
        // For edit-oriented profiles, allow generate_image as text2img if no image; if image provided treat as edit
        let body;
        if ((PROFILE !== 'seedream-t2i') && (args.image || args.images)) {
          const { urls } = await resolveImageUrls(config, args.images || args.image);
          body = buildEditBody(config, args, urls);
        } else if (PROFILE === 'seedream-t2i') {
          body = buildText2ImgBody(config, args);
        } else {
          // edit profiles without image: still allow pure prompt if API accepts; else require image
          if (PROFILE.startsWith('wan') || PROFILE.includes('edit')) {
            // require image for edit profiles
            if (!(args.image || args.images)) {
              throw new McpError(ErrorCode.InvalidParams, 'This MCP is image-edit oriented: pass image (local path or URL) or images[]');
            }
          }
          body = buildText2ImgBody(config, args);
        }
        const submitted = await submitGenerate(config, body);
        const polled = await pollPrediction(config, submitted);
        const results = await saveOutputs(config, polled.outputs, 'atlas_gen');
        return { content: [{ type: 'text', text: JSON.stringify({ profile: PROFILE, model: body.model, results }) }] };
      }
      case 'edit_image': {
        if (!isEditImageArgs(args)) {
          throw new McpError(ErrorCode.InvalidParams, 'Invalid parameters for edit_image (prompt + image/images required)');
        }
        const src = args.images || args.image;
        const { urls } = await resolveImageUrls(config, src);
        if (!urls.length) throw new McpError(ErrorCode.InvalidParams, 'No valid images provided');
        const body = buildEditBody(config, args, urls);
        if (PROFILE === 'seedream-edit-seq') {
          const mi = args.max_images || args.n;
          if (mi) body.max_images = Number(mi);
        }
        if (PROFILE === 'wan-edit' || PROFILE === 'wan-edit-pro') {
          // wan supports up to 9 images
          if (urls.length > 9) body.images = urls.slice(0, 9);
        }
        const submitted = await submitGenerate(config, body);
        const polled = await pollPrediction(config, submitted);
        const results = await saveOutputs(config, polled.outputs, 'atlas_edit');
        return { content: [{ type: 'text', text: JSON.stringify({ profile: PROFILE, model: body.model, results }) }] };
      }
      default:
        throw new McpError(ErrorCode.MethodNotFound, `Unknown tool: ${toolName} (atlas profile ${PROFILE} supports generate_image/edit_image)`);
    }
  } catch (error) {
    console.error(`[atlascloud-mcp:${PROFILE}] Error ${toolName}:`, error);
    if (error instanceof McpError) throw error;
    let errorMessage = error?.message || String(error);
    let code = ErrorCode.InternalError;
    if (axios.isAxiosError(error)) {
      const data = error.response?.data;
      if (data && typeof data === 'object') {
        errorMessage = data?.error?.message || data?.message || data?.msg || errorMessage;
      }
      if (error.response?.status >= 400 && error.response?.status < 500) code = ErrorCode.InvalidParams;
      errorMessage = `API Error: ${errorMessage}`;
    }
    throw new McpError(code, errorMessage);
  }
}
