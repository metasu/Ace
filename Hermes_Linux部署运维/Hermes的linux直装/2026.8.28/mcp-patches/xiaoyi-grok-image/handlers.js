import axios from 'axios';
import * as path from 'path';
import { randomUUID } from 'crypto';
import { ErrorCode, McpError } from '@modelcontextprotocol/sdk/types.js';
import { ensureDirectoryExists, downloadFile } from '../utils/index.js';

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
                    n: args.n || 1,
                    size: args.size || config.defaultImageSize,
                    quality: args.quality || 'auto',
                    output_format: args.output_format || 'png',
                    response_format: 'url',
                };

                if (args.background) requestBody.background = args.background;
                if (args.output_compression) requestBody.output_compression = args.output_compression;
                if (args.width) requestBody.width = args.width;
                if (args.height) requestBody.height = args.height;
                if (args.steps) requestBody.steps = args.steps;

                // Handle base URL that may or may not include /v1
                const baseUrl = apiUrl.endsWith('/v1') ? apiUrl : `${apiUrl}/v1`;
                const generateUrl = `${baseUrl}/images/generations`;
                console.error(`[xiaoyi-grok-image] Submitting generation request to ${generateUrl}`);
                console.error(`[xiaoyi-grok-image] Request body: ${JSON.stringify(requestBody, null, 2)}`);

                let response;
                try {
                    response = await axios.post(generateUrl, requestBody, {
                        headers: {
                            'Content-Type': 'application/json',
                            'Authorization': `Bearer ${apiKey}`,
                            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
                        },
                        timeout: config.requestTimeout,
                    });
                } catch (err) {
                    throw err;
                }

                const responseData = response.data?.data;
                if (!responseData || !Array.isArray(responseData) || responseData.length === 0) {
                    throw new McpError(ErrorCode.InternalError, `xiaoyi-grok-image API did not return image data. Response: ${JSON.stringify(response.data)}`);
                }

                const results = [];
                const imagesOutputDir = path.join(config.audioOutputDir, 'images');
                await ensureDirectoryExists(imagesOutputDir);

                for (const item of responseData) {
                    let localPath = null;
                    let saveError = null;
                    const imageUrl = item.url || item.b64_json;
                    if (!imageUrl) {
                        saveError = 'No URL or base64 data in response';
                    } else {
                        let ext;
                        if (item.mime_type) {
                            if (item.mime_type === 'image/jpeg' || item.mime_type === 'image/jpg') ext = 'jpg';
                            else if (item.mime_type === 'image/png') ext = 'png';
                            else if (item.mime_type === 'image/webp') ext = 'webp';
                            else ext = 'bin';
                        } else {
                            ext = requestBody.output_format === 'jpeg' ? 'jpg' : 'png';
                        }
                        const filename = `generated_xiaoyi_grok_imagine_${randomUUID()}.${ext}`;
                        try {
                            localPath = path.join(imagesOutputDir, filename);
                            if (item.url) {
                                await downloadFile(item.url, localPath);
                            } else if (item.b64_json) {
                                const buffer = Buffer.from(item.b64_json, 'base64');
                                await require('fs').promises.writeFile(localPath, buffer);
                            }
                            console.error(`[xiaoyi-grok-image] Generated image saved to: ${localPath}`);
                        } catch (err) {
                            console.error(`[xiaoyi-grok-image] Error saving generated image: ${err.message}`);
                            saveError = `Error saving generated image: ${err.message}`;
                        }
                    }
                    results.push({
                        local_path: localPath,
                        output_url: item.url,
                        mime_type: item.mime_type,
                        error: saveError,
                    });
                }

                const lines = [
                    'GENERATION_COMPLETE: xiaoyi grok-imagine-image generation succeeded.',
                    'Do not call generate_image again for this request. Report the result to the user and include the MEDIA: token so the WebUI renders the image inline.',
                    '',
                    ...results.flatMap((item, index) => {
                        const n = index + 1;
                        const parts = [`Image ${n}:`];
                        if (item.local_path) parts.push(`Local file: ${item.local_path}`);
                        if (item.output_url) parts.push(`Remote URL: ${item.output_url}`);
                        if (item.mime_type) parts.push(`MIME type: ${item.mime_type}`);
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
                return { content: [{ type: 'text', text: lines.join('\n') }] };
            }
            default:
                throw new McpError(ErrorCode.MethodNotFound, `Unknown tool: ${toolName}`);
        }
    } catch (error) {
        console.error(`[xiaoyi-grok-image] Error calling tool ${toolName}:`, error);
        if (error instanceof McpError) {
            throw error;
        }
        let errorMessage = `Error processing tool ${toolName}`;
        let mcpErrorCode = ErrorCode.InternalError;
        if (axios.isAxiosError(error)) {
            console.error('[xiaoyi-grok-image] Axios error details:', {
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
            errorMessage = `xiaoyi-grok-image API Error: ${apiErrorMessage}`;
            if (error.response?.status && error.response.status >= 400 && error.response.status < 500) {
                mcpErrorCode = ErrorCode.InvalidParams;
            }
        } else if (error instanceof Error) {
            errorMessage = error.message;
        }
        throw new McpError(mcpErrorCode, errorMessage);
    }
}
