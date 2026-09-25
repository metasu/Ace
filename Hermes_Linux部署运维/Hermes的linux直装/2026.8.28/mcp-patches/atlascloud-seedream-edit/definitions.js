import config from '../config/index.js';
const model = config.defaultEditImageModel || config.defaultImageConfig?.model || 'bytedance/seedream-v5.0-lite/edit';
const toolDefinitions = [
  {
    name: 'edit_image',
    description: `AtlasCloud Seedream edit (image-to-image). Local files are auto-uploaded via uploadMedia. Native generateImage + poll. Default model: ${model}. size WIDTH*HEIGHT (e.g. 2048*2048). No moderation.`,
    inputSchema: {
      type: 'object',
      properties: {
        image: { type: 'string', description: 'Local path or URL of source image' },
        images: { type: 'array', items: { type: 'string' }, description: 'Optional multiple image URLs/paths' },
        prompt: { type: 'string', description: 'Edit instruction' },
        model: { type: 'string', description: `Model id (default: ${model})` },
        size: { type: 'string', description: 'WIDTH*HEIGHT e.g. 2048*2048' },
        width: { type: 'number' },
        height: { type: 'number' },
        output_format: { type: 'string', enum: ['jpeg', 'png'] },
      },
      required: ['prompt', 'image'],
    },
  },
  {
    name: 'generate_image',
    description: `Same as edit_image but accepts optional image; if image provided performs edit. Default model: ${model}.`,
    inputSchema: {
      type: 'object',
      properties: {
        prompt: { type: 'string' },
        image: { type: 'string', description: 'Local path or URL' },
        images: { type: 'array', items: { type: 'string' } },
        model: { type: 'string' },
        size: { type: 'string' },
        width: { type: 'number' },
        height: { type: 'number' },
      },
      required: ['prompt'],
    },
  },
];
export default toolDefinitions;
