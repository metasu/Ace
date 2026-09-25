import config from '../config/index.js';
const model = config.defaultEditImageModel || config.defaultImageConfig?.model || 'alibaba/wan-2.7-pro/image-edit';
const toolDefinitions = [
  {
    name: 'edit_image',
    description: `AtlasCloud Wan 2.7 Pro image edit. size 1K/2K only. images[] up to 9. n=1-4, thinking_mode default true. Local auto-upload. Model: ${model}.`,
    inputSchema: {
      type: 'object',
      properties: {
        image: { type: 'string' },
        images: { type: 'array', items: { type: 'string' } },
        prompt: { type: 'string' },
        model: { type: 'string' },
        size: { type: 'string', enum: ['1K', '2K'] },
        n: { type: 'number', minimum: 1, maximum: 4 },
        thinking_mode: { type: 'boolean' },
      },
      required: ['prompt', 'image'],
    },
  },
  {
    name: 'generate_image',
    description: `Wan 2.7 Pro edit entry. Requires image. size 1K/2K. Model: ${model}.`,
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
