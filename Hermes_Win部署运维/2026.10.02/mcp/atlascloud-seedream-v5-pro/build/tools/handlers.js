import axios from 'axios';
import * as path from 'path';
import { randomUUID } from 'crypto';
import { ErrorCode, McpError } from '@modelcontextprotocol/sdk/types.js';
import { ensureDirectoryExists, downloadFile } from '../utils/index.js';

const POLL_INTERVAL = 3000;
const DEFAULT_MAX_POLL_TIME = 600000;

async function pollPrediction(predictionId, apiKey, apiUrl, maxPollTime = DEFAULT_MAX_POLL_TIME) {
    const pollUrl = `${apiUrl}/api/v1/model/prediction/${predictionId}`;
    const startTime = Date.now();
    while (Date.now() - startTime < maxPollTime) {
        const response = await axios.get(pollUrl, {
            headers: { 'Authorization': `Bearer ${apiKey}`, 'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36' },
            timeout: 30000,
        });
        const data = response.data?.data;
        if (!data) {
            throw new Error('AtlasCloud prediction response missing data');
        }
        const status = data.status;
        console.error(`[atlascloud-seedream-v5-lite] Polling prediction ${predictionId}: status=${status}`);
        if (status === 'completed' || status === 'succeeded') {
            return data;
        }
        if (status === 'failed') {
            throw new Error(`AtlasCloud prediction failed: ${data.error || 'Unknown error'}`);
        }
        await new Promise(resolve => setTimeout(resolve, POLL_INTERVAL));
    }
    throw new Error(`AtlasCloud prediction ${predictionId} timed out after ${maxPollTime / 1000}s`);
}

export async function handleToolCall({ toolName, args, config }) {
    try {
        switch (toolName) {
            case 'generate_image': {
                if (!args || typeof args !== 'object' || !args.prompt || typeof args.prompt !== 'string') {
                    throw new McpError(ErrorCode.InvalidParams, 'Parameter "prompt" (string) is required for generate_image.');
                }

                const modelToUse = args.model || config.defaultImageModel;
                const apiUrl = config.apiUrl;
                const apiKey = config.apiKey;
                const requestBody = {
                    model: modelToUse,
                    prompt: args.prompt,
                    enable_base64_output: false,
                    size: args.size || '2048*2048',
                    output_format: args.output_format || 'png',
                };
                if (args.seed !== undefined) {
                    requestBody.seed = args.seed;
                }
                if (args.guidance_scale !== undefined) {
                    requestBody.guidance_scale = args.guidance_scale;
                }
                if (args.num_inference_steps !== undefined) {
                    requestBody.num_inference_steps = args.num_inference_steps;
                }

                const generateUrl = `${apiUrl}/api/v1/model/generateImage`;
                console.error(`[atlascloud-seedream-v5-lite] Submitting generation request to ${generateUrl}`);
                console.error(`[atlascloud-seedream-v5-lite] Request body: ${JSON.stringify(requestBody, null, 2)}`);

                const submitResponse = await axios.post(generateUrl, requestBody, {
                    headers: {
                        'Content-Type': 'application/json',
                        'Authorization': `Bearer ${apiKey}`,
                        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
                    },
                    timeout: config.requestTimeout,
                });

                const predictionId = submitResponse.data?.data?.id;
                if (!predictionId) {
                    throw new McpError(ErrorCode.InternalError, `AtlasCloud API did not return a prediction ID. Response: ${JSON.stringify(submitResponse.data)}`);
                }
                console.error(`[atlascloud-seedream-v5-lite] Prediction ID: ${predictionId}, polling for result...`);

                const result = await pollPrediction(predictionId, apiKey, apiUrl, config.requestTimeout || DEFAULT_MAX_POLL_TIME);
                const outputs = result.outputs;
                if (!outputs || !Array.isArray(outputs) || outputs.length === 0) {
                    throw new McpError(ErrorCode.InternalError, 'AtlasCloud prediction completed but no output URLs found.');
                }

                const results = [];
                const imagesOutputDir = path.join(config.audioOutputDir, 'images');
                await ensureDirectoryExists(imagesOutputDir);
                for (const outputUrl of outputs) {
                    let localPath = null;
                    let saveError = null;
                    const ext = requestBody.output_format === 'jpeg' ? 'jpg' : 'png';
                    const filename = `generated_seedream_v5_lite_${randomUUID()}.${ext}`;
                    try {
                        localPath = path.join(imagesOutputDir, filename);
                        await downloadFile(outputUrl, localPath);
                        console.error(`[atlascloud-seedream-v5-lite] Generated image saved to: ${localPath}`);
                    } catch (err) {
                        console.error(`[atlascloud-seedream-v5-lite] Error saving generated image: ${err.message}`);
                        saveError = `Error saving generated image: ${err.message}`;
                    }
                    results.push({
                        local_path: localPath,
                        output_url: outputUrl,
                        error: saveError,
                    });
                }
                const lines = [
                    'GENERATION_COMPLETE: AtlasCloud Seedream image generation succeeded.',
                    'Do not call generate_image again for this request. Report the result to the user and include the MEDIA: token so the WebUI renders the image inline.',
                    '',
                    ...results.flatMap((item, index) => {
                        const n = index + 1;
                        const parts = [`Image ${n}:`];
                        if (item.local_path) parts.push(`Local file: ${item.local_path}`);
                        if (item.output_url) parts.push(`Remote URL: ${item.output_url}`);
                        if (item.output_url) {
                            parts.push(`MEDIA token (paste this exact line into your response to render the image inline): MEDIA:${item.output_url}`);
                            parts.push(`Markdown preview: ![Generated image ${n}](${item.output_url})`);
                        }
                        if (item.local_path) {
                            const localUri = `file:///${item.local_path.replace(/\\/g, '/')}`;
                            parts.push(`Local file link: [Open local image](${localUri})`);
                        }
                        if (item.error) parts.push(`Save warning: ${item.error}`);
                        return parts;
                    }),
                    '',
                    `Raw JSON: ${JSON.stringify(results)}`,
                ];
                // Return text-only result. The text already contains the local
                // file path, remote URL, and markdown preview — sufficient for
                // the model to report to the user. Attaching the image as a
                // base64 ImageContent block was removed because a 2048x2048 PNG
                // is 5-15 MB, which adds 20-60+ seconds of stdio transfer time
                // after the image is already saved, causing user interruptions
                // and redundant generate_image calls. All other MCP handlers in
                // this project (sudocx-image, seedream-edit, wan-edit, etc.)
                // already return text-only results for the same reason.
                return { content: [{ type: 'text', text: lines.join('\n') }] };
            }
            default:
                throw new McpError(ErrorCode.MethodNotFound, `Unknown tool: ${toolName}`);
        }
    } catch (error) {
        console.error(`[atlascloud-seedream-v5-lite] Error calling tool ${toolName}:`, error);
        if (error instanceof McpError) {
            throw error;
        }
        let errorMessage = `Error processing tool ${toolName}`;
        let mcpErrorCode = ErrorCode.InternalError;
        if (axios.isAxiosError(error)) {
            console.error('[atlascloud-seedream-v5-lite] Axios error details:', {
                message: error.message,
                url: error.config?.url,
                method: error.config?.method,
                status: error.response?.status,
                data: error.response?.data,
            });
            let apiErrorMessage = error.message;
            if (error.response?.data) {
                apiErrorMessage = error.response.data?.error?.message || error.response.data?.message || JSON.stringify(error.response.data) || apiErrorMessage;
            }
            errorMessage = `AtlasCloud API Error: ${apiErrorMessage}`;
            if (error.response?.status && error.response.status >= 400 && error.response.status < 500) {
                mcpErrorCode = ErrorCode.InvalidParams;
            }
        } else if (error instanceof Error) {
            errorMessage = error.message;
        }
        throw new McpError(mcpErrorCode, errorMessage);
    }
}
