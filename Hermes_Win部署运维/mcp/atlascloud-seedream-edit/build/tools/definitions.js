import config from '../config/index.js';
const toolDefinitions = [
    {
        name: 'edit_image',
        description: 'Edits an image using AtlasCloud Seedream API. Supports local file paths or URLs as image input. No content filtering. Returns the edited image as a URL or local file path.',
        inputSchema: {
            type: 'object',
            properties: {
                image: {
                    type: 'string',
                    description: 'The image to edit. Can be a local file path or a URL.',
                },
                prompt: {
                    type: 'string',
                    description: 'A text description of the desired edit. Required.',
                    maxLength: 32000,
                },
                model: {
                    type: 'string',
                    description: `Model to use for editing (default: ${config.defaultEditImageModel}).`,
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
            },
            required: ['image', 'prompt'],
        },
    },
];
export default toolDefinitions;
