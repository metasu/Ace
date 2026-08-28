import config from '../config/index.js';

const toolDefinitions = [
    {
        name: 'generate_image',
        description: 'Generates a 2K image using the xiaoyi grok-imagine-image model via an OpenAI-compatible API. When the tool returns GENERATION_COMPLETE, report the result and include the line "MEDIA:<output_url>" in your response so the WebUI renders the image inline. Do not call generate_image again.',
        inputSchema: {
            type: 'object',
            properties: {
                prompt: {
                    type: 'string',
                    description: 'Text prompt for image generation. Required.',
                },
                model: {
                    type: 'string',
                    description: `Model to use for generation (default: ${config.defaultImageModel}).`,
                },
                n: {
                    type: 'integer',
                    description: 'Number of images to generate. Default: 1',
                    minimum: 1,
                    maximum: 10,
                },
                size: {
                    type: 'string',
                    enum: ['2048x2048', '2048x1536', '1536x2048', '1024x1024', '1536x1024', '1024x1536', 'auto'],
                    description: `Image size. Default: ${config.defaultImageSize} (2K).`,
                },
                quality: {
                    type: 'string',
                    enum: ['auto', 'high', 'medium', 'low'],
                    description: 'Image quality. Default: auto.',
                },
                output_format: {
                    type: 'string',
                    enum: ['jpeg', 'png'],
                    description: 'Output image format. Default: jpeg for faster generation.',
                },
                background: {
                    type: 'string',
                    description: 'Optional background parameter if supported.',
                },
                output_compression: {
                    type: 'number',
                    description: 'Optional output compression if supported.',
                },
                width: {
                    type: 'integer',
                    description: 'Image width (non-standard param, only sent if explicitly set).',
                    minimum: 128,
                    maximum: 2048,
                },
                height: {
                    type: 'integer',
                    description: 'Image height (non-standard param, only sent if explicitly set).',
                    minimum: 128,
                    maximum: 2048,
                },
                steps: {
                    type: 'integer',
                    description: 'Inference steps (non-standard param, only sent if explicitly set).',
                },
            },
            required: ['prompt'],
        },
    },
];

export default toolDefinitions;
