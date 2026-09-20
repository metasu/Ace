import axios from 'axios';
import * as fs from 'fs';
import * as path from 'path';
import { randomUUID } from 'crypto';
import FormData from 'form-data';
import { ErrorCode, McpError } from '@modelcontextprotocol/sdk/types.js';
import { ensureDirectoryExists, isValidHttpUrl, downloadFile } from '../utils/index.js';

const POLL_INTERVAL = 3000;
const MAX_POLL_TIME = 180000;

async function uploadToAtlasCloud(imagePath, apiKey, apiUrl) {
    const uploadUrl = `${apiUrl}/api/v1/model/uploadMedia`;
    const imageBuffer = await fs.promises.readFile(imagePath);
    const formData = new FormData();
    formData.append('file', imageBuffer, path.basename(imagePath));
    const response = await axios.post(uploadUrl, formData, {
        headers: {
            ...formData.getHeaders(),
            'Authorization': `Bearer ${apiKey}`,
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
        },
        timeout: 60000,
    });
    const downloadUrl = response.data?.data?.download_url;
    if (!downloadUrl) {
        throw new Error('AtlasCloud upload did not return a download_url');
    }
    return downloadUrl;
}

async function pollPrediction(predictionId, apiKey, apiUrl) {
    const pollUrl = `${apiUrl}/api/v1/model/prediction/${predictionId}`;
    const startTime = Date.now();
    while (Date.now() - startTime < MAX_POLL_TIME) {
        const response = await axios.get(pollUrl, {
            headers: { 'Authorization': `Bearer ${apiKey}`, 'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36' },
            timeout: 30000,
        });
        const data = response.data?.data;
        if (!data) {
            throw new Error('AtlasCloud prediction response missing data');
        }
        const status = data.status;
        console.error(`[atlascloud-wan] Polling prediction ${predictionId}: status=${status}`);
        if (status === 'completed' || status === 'succeeded') {
            return data;
        }
        if (status === 'failed') {
            throw new Error(`AtlasCloud prediction failed: ${data.error || 'Unknown error'}`);
        }
        await new Promise(resolve => setTimeout(resolve, POLL_INTERVAL));
    }
    throw new Error(`AtlasCloud prediction ${predictionId} timed out after ${MAX_POLL_TIME / 1000}s`);
}

export async function handleToolCall({ toolName, args, axiosInstance, config }) {
    try {
        switch (toolName) {
            case 'edit_image': {
                if (!args || typeof args !== 'object' || !args.image || typeof args.image !== 'string' || !args.prompt || typeof args.prompt !== 'string') {
                    throw new McpError(ErrorCode.InvalidParams, 'Parameters "image" (string) and "prompt" (string) are required for edit_image.');
                }
                const modelToUse = args.model || config.defaultEditImageModel;
                const apiUrl = config.apiUrl;
                const apiKey = config.apiKey;

                // Handle image input - could be single URL/path or comma-separated
                let imageUrls = [];
                let imageInputs = args.image;
                if (typeof imageInputs === 'string') {
                    // Check if it's a comma-separated list of URLs
                    if (imageInputs.includes(',')) {
                        imageInputs = imageInputs.split(',').map(s => s.trim()).filter(s => s.length > 0);
                    } else {
                        imageInputs = [imageInputs];
                    }
                }
                if (!Array.isArray(imageInputs)) {
                    imageInputs = [imageInputs];
                }

                for (const img of imageInputs) {
                    if (isValidHttpUrl(img)) {
                        imageUrls.push(img);
                    } else {
                        try {
                            await fs.promises.access(img, fs.constants.R_OK);
                        } catch (accessError) {
                            throw new McpError(ErrorCode.InvalidParams, `Cannot access local image file: ${img}`);
                        }
                        console.error(`[atlascloud-wan] Uploading local image to AtlasCloud: ${img}`);
                        const uploadedUrl = await uploadToAtlasCloud(img, apiKey, apiUrl);
                        imageUrls.push(uploadedUrl);
                        console.error(`[atlascloud-wan] Image uploaded, URL: ${uploadedUrl}`);
                    }
                }

                const requestBody = {
                    model: modelToUse,
                    prompt: args.prompt,
                    images: imageUrls,
                    enable_base64_output: false,
                    size: args.size || '2K',
                    n: args.n || 1,
                    thinking_mode: args.thinking_mode !== undefined ? args.thinking_mode : true,
                };
                if (args.seed !== undefined) {
                    requestBody.seed = args.seed;
                }

                const generateUrl = `${apiUrl}/api/v1/model/generateImage`;
                console.error(`[atlascloud-wan] Submitting edit request to ${generateUrl}`);
                console.error(`[atlascloud-wan] Request body: ${JSON.stringify(requestBody, null, 2)}`);

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
                console.error(`[atlascloud-wan] Prediction ID: ${predictionId}, polling for result...`);

                const result = await pollPrediction(predictionId, apiKey, apiUrl);
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
                    const filename = `edited_image_${randomUUID()}.png`;
                    try {
                        localPath = path.join(imagesOutputDir, filename);
                        await downloadFile(outputUrl, localPath);
                        console.error(`[atlascloud-wan] Edited image saved to: ${localPath}`);
                    } catch (err) {
                        console.error(`[atlascloud-wan] Error saving edited image: ${err.message}`);
                        saveError = `Error saving edited image: ${err.message}`;
                    }
                    results.push({
                        local_path: localPath,
                        output_url: outputUrl,
                        error: saveError,
                    });
                }
                return { content: [{ type: 'text', text: JSON.stringify(results) }] };
            }
            default:
                throw new McpError(ErrorCode.MethodNotFound, `Unknown tool: ${toolName}`);
        }
    } catch (error) {
        console.error(`[atlascloud-wan] Error calling tool ${toolName}:`, error);
        if (error instanceof McpError) {
            throw error;
        }
        let errorMessage = `Error processing tool ${toolName}`;
        let mcpErrorCode = ErrorCode.InternalError;
        if (axios.isAxiosError(error)) {
            console.error('[atlascloud-wan] Axios error details:', {
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
