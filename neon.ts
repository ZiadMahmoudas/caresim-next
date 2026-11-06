import { defineConfig } from '@neon/config/v1';

export default defineConfig({
  auth: true,
  dataApi: true,

  buckets: {
    avatars: {
      access: 'public_read',
    },

    'scenario-assets': {
      access: 'public_read',
    },
  },
});