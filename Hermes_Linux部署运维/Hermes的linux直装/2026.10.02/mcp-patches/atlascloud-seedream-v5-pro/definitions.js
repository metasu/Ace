import config from '../config/index.js';
const model = config.defaultImageConfig?.model || 'bytedance/seedream-v5.0-lite';
const toolDefinitions = [
  {
    name: 'generate_image',
    description: `AtlasCloud Seedream v5.0 Lite text-to-image via native generateImage + async poll. Default model: ${model}. size uses WIDTH*HEIGHT (e.g. 2048*2048); min pixels ~3.6MP. No moderation param. Returns local_path + source_url.`,
    inputSchema: {
      type: 'object',
      properties: {
        prompt: { type: 'string', description: 'Text prompt for image generation' },
        model: { type: 'string', description: `Model id (default: ${model})` },
        width: { type: 'number', description: 'Width px (default 2048). Combined with height must be >= 3686400 pixels unless size is set.', minimum: 512, maximum: 4096 },
        height: { type: 'number', description: 'Height px (default 2048).', minimum: 512, maximum: 4096 },
        size: { type: 'string', description: 'Atlas size WIDTH*HEIGHT (preferred), e.g. 2048*2048, 2560*1440' },
        output_format: { type: 'string', enum: ['jpeg', 'png'], description: 'Optional output format for Seedream' },
        n: { type: 'number', description: 'Unused for plain seedream t2i (kept for compatibility)', minimum: 1, maximum: 4 },
      },
      required: ['prompt'],
    },
  },
];
export default toolDefinitions;
