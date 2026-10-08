import config from '../config/index.js';
const toolDefinitions = [
    {
        name: 'edit_image',
        description: 'Edits an image using AtlasCloud Wan 2.7 Pro API (higher quality). Supports local file paths or URLs as image input. Supports multi-image reference composition. No content filtering. Returns the edited image as a URL or local file path.',
        inputSchema: {
            type: 'object',
            properties: {
                image: {
                    type: 'string',
                    description: 'The primary image to edit. Can be a local file path or a URL. Additional reference images can be provided as a comma-separated list or array.',
                },
                prompt: {
                    type: 'string',
                    description: 'A text instruction describing the desired edit. Required. Max 5000 characters.',
                    maxLength: 5000,
                },
                model: {
                    type: 'string',
                    description: `Model to use for editing (default: ${config.defaultEditImageModel}).`,
                },
                size: {
                    type: 'string',
                    enum: ['1K', '2K'],
                    description: 'Output image resolution. "1K" ~1024x1024, "2K" ~2048x2048. Default: 2K',
                },
                n: {
                    type: 'number',
                    description: 'Number of images to generate (1-4). Default: 1',
                    minimum: 1,
                    maximum: 4,
                },
                thinking_mode: {
                    type: 'boolean',
                    description: 'Enable thinking mode for higher-quality generation. Default: true',
                },
                seed: {
                    type: 'integer',
                    description: 'Random seed for reproducibility (-1 for random).',
                },
            },
            required: ['image', 'prompt'],
        },
    },
];
export default toolDefinitions;
