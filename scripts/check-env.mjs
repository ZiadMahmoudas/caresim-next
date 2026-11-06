const required = [
  'NEXT_PUBLIC_APP_URL',
  'NEXT_PUBLIC_SITE_URL',
  'NEXT_PUBLIC_NEON_DATA_API_URL',
  'NEON_AUTH_BASE_URL',
  'NEON_AUTH_COOKIE_SECRET',
  'DATABASE_URL',
  'AWS_ACCESS_KEY_ID',
  'AWS_SECRET_ACCESS_KEY',
  'AWS_ENDPOINT_URL_S3',
  'AWS_REGION',
  'GEMINI_API_KEY',
  'GEMINI_MODEL',
  'NEXT_PUBLIC_EMAILJS_SERVICE_ID',
  'NEXT_PUBLIC_EMAILJS_TEMPLATE_ID',
  'NEXT_PUBLIC_EMAILJS_PUBLIC_KEY',
];

const placeholders = /^(PASTE_|REPLACE_|https:\/\/YOUR-|postgresql:\/\/USER:|$)/;
const missing = required.filter((name) => {
  const value = process.env[name] || '';
  return placeholders.test(value);
});

if ((process.env.NEON_AUTH_COOKIE_SECRET || '').length < 32) {
  if (!missing.includes('NEON_AUTH_COOKIE_SECRET')) missing.push('NEON_AUTH_COOKIE_SECRET');
}

if (missing.length) {
  console.error('CareSim environment is NOT production-ready. Fix:');
  for (const name of missing) console.error(`- ${name}`);
  process.exit(1);
}

console.log('CareSim environment variables look production-ready.');
