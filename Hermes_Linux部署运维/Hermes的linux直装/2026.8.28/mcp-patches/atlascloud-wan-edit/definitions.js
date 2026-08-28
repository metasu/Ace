import config from '../config/index.js';
const model = config.defaultEditImageModel || config.defaultImageConfig?.model || 'alibaba/wan-2.7/image-edit';
const toolDefinitions = [
  {
    name: 'edit_image',
    description: `AtlasCloud Wan 2.7 image edit. size must be 1K or 2K (NOT WIDTH*HEIGHT). Supports images[] up to 9 (first main, rest refs). n=1-4, thinking_mode default true. Local files auto-upload. Model: ${model}.`,
    inputSchema: {
      type: 'object',
      properties: {
        image: { type: 'string', description: 'Main image path or URL' },
        images: { type: 'array', items: { type: 'string' }, description: 'Up to 9 images; first is main' },
        prompt: { type: 'string' },
        model: { type: 'string' },
        size: { type: 'string', enum: ['1K', '2K'], description: 'Wan size tier (default 2K)' },
        n: { type: 'number', minimum: 1, maximum: 4, description: 'Independent results count' },
        thinking_mode: { type: 'boolean', description: 'Enable thinking mode (default true)' },
      },
      required: ['prompt', 'image'],
    },
  },
  {
    name: 'generate_image',
    description: `Wan 2.7 edit entry via generate_image tool name. Requires image. size 1K/2K. Model: ${model}.`,
    inputSchema: {
      type: 'object',
      properties: {
        prompt: { type: 'string' },
        image: { type: 'string' },
        images: { type: 'array', items: { type: 'string' } },
        model: { type: 'string' },
        size: { type: 'string', enum: ['1K', '2K'] },
        n: { type: 'number', minimum: 1, maximum: 4 },
        thinking_mode: { type: 'boolean' },
      },
      required: ['prompt', 'image'],
    },
  },
];
export default toolDefinitions;
