import config from '../config/index.js';

const toolDefinitions = [
    {
        name: 'generate_image',
        description: 'Generates one image using AtlasCloud Seedream v5.0 Pro text-to-image API. Uses AtlasCloud native async polling endpoint. No moderation parameter is sent by this MCP. Call this tool only once per user image request; when the tool returns GENERATION_COMPLETE, report the result and include the line "MEDIA:<remote_url>" in your response so the WebUI renders the image inline. Do not call generate_image again.',
        inputSchema: {
            type: 'object',
            properties: {
                prompt: {
                    type: 'string',
                    description: 'Text prompt for image generation. Required.',
                    maxLength: 32000,
                },
                model: {
                    type: 'string',
                    description: `Model to use for generation (default: ${config.defaultImageModel}).`,
                },
                size: {
                    type: 'string',
                    description: 'Output image size in WIDTH*HEIGHT format (e.g. "2048*2048", "1280*720"). Default: 2048*2048',
                },
                output_format: {
                    type: 'string',
                    enum: ['jpeg', 'png'],
                    description: 'Output image file format. Default: png',
                },
                seed: {
                    type: 'integer',
                    description: 'Random seed for reproducibility (-1 for random).',
                },
                guidance_scale: {
                    type: 'number',
                    description: 'Optional guidance scale if supported by AtlasCloud for this model.',
                },
                num_inference_steps: {
                    type: 'integer',
                    description: 'Optional inference steps if supported by AtlasCloud for this model.',
                },
            },
            required: ['prompt'],
        },
    },
];

export default toolDefinitions;
