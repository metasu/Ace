import config from '../config/index.js';
const model = config.defaultEditImageModel || config.defaultImageConfig?.model || 'bytedance/seedream-v5.0-lite/edit-sequential';
const toolDefinitions = [
  {
    name: 'edit_image',
    description: `AtlasCloud Seedream sequential edit. Supports max_images (1-15) for related series. Default model: ${model}. size WIDTH*HEIGHT. Local images auto-upload. No moderation.`,
    inputSchema: {
      type: 'object',
      properties: {
        image: { type: 'string' },
        images: { type: 'array', items: { type: 'string' } },
        prompt: { type: 'string' },
        model: { type: 'string' },
        size: { type: 'string', description: 'WIDTH*HEIGHT e.g. 2048*2048' },
        max_images: { type: 'number', minimum: 1, maximum: 15, description: 'How many related images to generate (sequential)' },
        n: { type: 'number', minimum: 1, maximum: 15, description: 'Alias of max_images' },
        width: { type: 'number' },
        height: { type: 'number' },
      },
      required: ['prompt', 'image'],
    },
  },
  {
    name: 'generate_image',
    description: `Sequential seedream generation/edit. Prefer max_images for multi-image series. Model: ${model}.`,
    inputSchema: {
      type: 'object',
      properties: {
        prompt: { type: 'string' },
        image: { type: 'string' },
        images: { type: 'array', items: { type: 'string' } },
        model: { type: 'string' },
        size: { type: 'string' },
        max_images: { type: 'number', minimum: 1, maximum: 15 },
        n: { type: 'number', minimum: 1, maximum: 15 },
      },
      required: ['prompt'],
    },
  },
];
export default toolDefinitions;
