import { McpError, ErrorCode } from '@modelcontextprotocol/sdk/types.js';
import axios from 'axios';
import fs from 'fs';
import path from 'path';
import { randomUUID } from 'crypto';
import FormData from 'form-data';
import { unlink } from 'fs/promises';
import { ensureDirectoryExists, downloadFile, uploadToCfImgbed, processImageGenerationInBackground, processImageEditInBackground, isValidHttpUrl } from '../utils/index.js';

/** Resolve OpenAI-compatible base ending with /v1 without double prefix. */
function openaiV1Base(apiUrl) {
    const u = String(apiUrl || '').replace(/\/+$/, '');
    if (u.endsWith('/v1')) return u;
    return `${u}/v1`;
}

function absUrl(apiUrl, suffix) {
    // suffix like /images/generations
    return `${openaiV1Base(apiUrl)}${suffix.startsWith('/') ? suffix : '/' + suffix}`;
}

function isGenerateImageArgs(args) {
    return args && typeof args.prompt === 'string';
}
function isGenerateSpeechArgs(args) {
    return args && typeof args.input === 'string';
}
function isTranscribeAudioArgs(args) {
    return args && typeof args.file === 'string';
}
function isEditImageArgs(args) {
    return args && typeof args.image === 'string' && typeof args.prompt === 'string';
}

export async function handleToolCall({ toolName, args, config, axiosInstance }) {
    try {
        switch (toolName) {
            case 'generate_image': {
                if (!isGenerateImageArgs(args)) {
                    throw new McpError(ErrorCode.InvalidParams, 'Invalid parameters for generate_image');
                }
                const modelToUse = args.model || config.defaultImageConfig.model;
                const isSpecial = String(modelToUse).includes('dall-e-3') || String(modelToUse).includes('gpt-image-1');
                const genUrl = absUrl(config.apiUrl, '/images/generations');

                if (isSpecial) {
                    processImageGenerationInBackground(args, config, axiosInstance);
                    return {
                        content: [{
                            type: 'text',
                            text: JSON.stringify({
                                status: 'processing_in_background',
                                message: 'Image generation started in background for special model.',
                                model: modelToUse,
                            }),
                        }],
                    };
                }

                const { model: _m, ...rest } = config.defaultImageConfig || {};
                const body = {
                    prompt: args.prompt,
                    ...rest,
                    model: modelToUse,
                    ...(args.width && { width: args.width }),
                    ...(args.height && { height: args.height }),
                    ...(args.steps && { steps: args.steps }),
                    ...(args.n && { n: args.n }),
                    response_format: 'url',
                };
                delete body.size;
                delete body.quality;
                delete body.background;
                delete body.moderation;

                console.error('[kuaipao-image] POST', genUrl, JSON.stringify({ ...body, prompt: body.prompt?.slice?.(0, 80) }));
                const response = await axios.post(genUrl, body, {
                    headers: {
                        Authorization: `Bearer ${config.apiKey}`,
                        'Content-Type': 'application/json',
                    },
                    timeout: config.requestTimeout,
                });
                const responseData = response.data?.data;
                if (!responseData || !Array.isArray(responseData) || responseData.length === 0) {
                    throw new McpError(ErrorCode.InternalError, 'API response did not contain image data.');
                }
                const results = [];
                const imagesOutputDir = path.join(config.audioOutputDir, 'images');
                await ensureDirectoryExists(imagesOutputDir);
                for (const item of responseData) {
                    let imageBuffer = null;
                    let localPath = null;
                    let cloudflareUrl = null;
                    let cloudflareUploadSuccess = false;
                    let saveError;
                    const filenamePrefix = 'generated_image_sync';
                    let filename = `${filenamePrefix}_${randomUUID()}.png`;
                    try {
                        if (item.url && isValidHttpUrl(item.url)) {
                            const imageUrl = item.url;
                            const urlPath = new URL(imageUrl).pathname;
                            const ext = path.extname(urlPath) || '.png';
                            filename = `${filenamePrefix}_${randomUUID()}${ext}`;
                            localPath = path.join(imagesOutputDir, filename);
                            await downloadFile(imageUrl, localPath);
                            imageBuffer = await fs.promises.readFile(localPath);
                        } else if (item.b64_json) {
                            imageBuffer = Buffer.from(item.b64_json, 'base64');
                            localPath = path.join(imagesOutputDir, filename);
                            await fs.promises.writeFile(localPath, imageBuffer);
                        } else {
                            saveError = 'Missing image data (url or b64_json) in API response';
                        }
                    } catch (err) {
                        saveError = `Error processing image: ${err.message}`;
                    }
                    if (config.cfImgbedUploadUrl && config.cfImgbedApiKey && imageBuffer && localPath) {
                        cloudflareUrl = await uploadToCfImgbed(imageBuffer, filename, config.cfImgbedUploadUrl, config.cfImgbedApiKey);
                        if (cloudflareUrl) cloudflareUploadSuccess = true;
                    }
                    results.push({ local_path: localPath, cloudflare_url: cloudflareUrl, cloudflareUploadSuccess, error: saveError, source_url: item.url || null });
                }
                return { content: [{ type: 'text', text: JSON.stringify(results) }] };
            }
            case 'generate_speech': {
                if (!isGenerateSpeechArgs(args)) {
                    throw new McpError(ErrorCode.InvalidParams, 'Invalid parameters for generate_speech');
                }
                const requestBody = {
                    input: args.input,
                    model: args.model || config.defaultSpeechModel,
                    voice: args.voice || config.defaultSpeechVoice,
                    speed: args.speed ?? config.defaultSpeechSpeed,
                    response_format: 'mp3',
                };
                const speechOutputDir = path.join(config.audioOutputDir, 'audio');
                await ensureDirectoryExists(speechOutputDir);
                const response = await axios.post(absUrl(config.apiUrl, '/audio/speech'), requestBody, {
                    headers: {
                        Authorization: `Bearer ${config.apiKey}`,
                        'Content-Type': 'application/json',
                    },
                    responseType: 'arraybuffer',
                    timeout: config.requestTimeout,
                });
                const audioBuffer = Buffer.from(response.data);
                const outputPath = path.join(speechOutputDir, `speech_${randomUUID()}.mp3`);
                await fs.promises.writeFile(outputPath, audioBuffer);
                return { content: [{ type: 'text', text: JSON.stringify([{ local_path: outputPath }]) }] };
            }
            case 'transcribe_audio': {
                if (!isTranscribeAudioArgs(args)) {
                    throw new McpError(ErrorCode.InvalidParams, 'Invalid parameters for transcribe_audio');
                }
                let audioFilePath = args.file;
                let cleanupRequired = false;
                if (isValidHttpUrl(args.file)) {
                    const tmpDir = path.join(config.audioOutputDir, 'tmp');
                    await ensureDirectoryExists(tmpDir);
                    audioFilePath = path.join(tmpDir, `audio_${randomUUID()}`);
                    await downloadFile(args.file, audioFilePath);
                    cleanupRequired = true;
                }
                const formData = new FormData();
                formData.append('file', fs.createReadStream(audioFilePath));
                formData.append('model', args.model || config.defaultTranscriptionModel);
                try {
                    const response = await axios.post(absUrl(config.apiUrl, '/audio/transcriptions'), formData, {
                        headers: {
                            Authorization: `Bearer ${config.apiKey}`,
                            ...formData.getHeaders(),
                        },
                        timeout: config.requestTimeout,
                    });
                    const transcriptionText = response.data?.text;
                    if (typeof transcriptionText !== 'string') {
                        throw new McpError(ErrorCode.InternalError, 'API response did not contain valid transcription text.');
                    }
                    return { content: [{ type: 'text', text: JSON.stringify([{ text: transcriptionText }]) }] };
                } finally {
                    if (cleanupRequired) {
                        try { await unlink(audioFilePath); } catch (_) {}
                    }
                }
            }
            case 'edit_image': {
                if (!isEditImageArgs(args)) {
                    throw new McpError(ErrorCode.InvalidParams, 'Invalid parameters for edit_image');
                }
                const modelToUse = args.model || config.defaultEditImageModel || config.defaultImageConfig.model;
                const isSpecial = String(modelToUse).includes('dall-e-3') || String(modelToUse).includes('gpt-image-1');
                if (isSpecial) {
                    processImageEditInBackground(args, config, axiosInstance);
                    return {
                        content: [{
                            type: 'text',
                            text: JSON.stringify({ status: 'processing_in_background', message: 'Image edit started in background.', model: modelToUse }),
                        }],
                    };
                }
                let imagePath = args.image;
                let cleanup = false;
                if (isValidHttpUrl(args.image)) {
                    const tmpDir = path.join(config.audioOutputDir, 'tmp');
                    await ensureDirectoryExists(tmpDir);
                    imagePath = path.join(tmpDir, `edit_src_${randomUUID()}.png`);
                    await downloadFile(args.image, imagePath);
                    cleanup = true;
                }
                if (!fs.existsSync(imagePath)) {
                    throw new McpError(ErrorCode.InvalidParams, `Image file not found: ${args.image}`);
                }
                const formData = new FormData();
                formData.append('image', fs.createReadStream(imagePath));
                formData.append('prompt', args.prompt);
                formData.append('model', modelToUse);
                formData.append('n', String(args.n || 1));
                formData.append('response_format', 'b64_json');
                try {
                    const response = await axios.post(absUrl(config.apiUrl, '/images/edits'), formData, {
                        headers: {
                            Authorization: `Bearer ${config.apiKey}`,
                            ...formData.getHeaders(),
                        },
                        timeout: config.requestTimeout,
                    });
                    const responseData = response.data?.data || [];
                    const results = [];
                    const imagesOutputDir = path.join(config.audioOutputDir, 'images');
                    await ensureDirectoryExists(imagesOutputDir);
                    for (const item of responseData) {
                        const filename = `edited_image_${randomUUID()}.png`;
                        const localPath = path.join(imagesOutputDir, filename);
                        if (item.b64_json) {
                            await fs.promises.writeFile(localPath, Buffer.from(item.b64_json, 'base64'));
                            results.push({ local_path: localPath });
                        } else if (item.url) {
                            await downloadFile(item.url, localPath);
                            results.push({ local_path: localPath, source_url: item.url });
                        }
                    }
                    return { content: [{ type: 'text', text: JSON.stringify(results) }] };
                } finally {
                    if (cleanup) {
                        try { await unlink(imagePath); } catch (_) {}
                    }
                }
            }
            default:
                throw new McpError(ErrorCode.MethodNotFound, `Unknown tool: ${toolName}`);
        }
    } catch (error) {
        console.error(`Error calling tool ${toolName}:`, error);
        if (error instanceof McpError) throw error;
        let errorMessage = `Error processing tool ${toolName}`;
        let mcpErrorCode = ErrorCode.InternalError;
        if (axios.isAxiosError(error)) {
            let apiErrorMessage = error.message;
            const data = error.response?.data;
            if (data && typeof data === 'object') {
                apiErrorMessage = data?.error?.message || data?.message || data?.msg || apiErrorMessage;
            }
            errorMessage = `API Error: ${apiErrorMessage}`;
            if (error.response?.status && error.response.status >= 400 && error.response.status < 500) {
                mcpErrorCode = ErrorCode.InvalidParams;
            }
        } else if (error instanceof Error) {
            errorMessage = error.message;
        }
        throw new McpError(mcpErrorCode, errorMessage);
    }
}
