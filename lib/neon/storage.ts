import { PutObjectCommand, S3Client } from '@aws-sdk/client-s3';

function required(name: string) {
  const value = process.env[name];
  if (!value) throw new Error(`${name} is not configured. Add Neon Object Storage credentials in Vercel.`);
  return value;
}

export function storageConfigured() {
  return Boolean(
    process.env.AWS_ACCESS_KEY_ID &&
    process.env.AWS_SECRET_ACCESS_KEY &&
    process.env.AWS_ENDPOINT_URL_S3 &&
    process.env.AWS_REGION
  );
}

export function storageClient() {
  return new S3Client({
    region: required('AWS_REGION'),
    endpoint: required('AWS_ENDPOINT_URL_S3'),
    forcePathStyle: true,
    // Required by current AWS SDK builds for S3-compatible endpoints such as Neon Object Storage.
    requestChecksumCalculation: 'WHEN_REQUIRED',
    credentials: {
      accessKeyId: required('AWS_ACCESS_KEY_ID'),
      secretAccessKey: required('AWS_SECRET_ACCESS_KEY'),
    },
  });
}

export async function putPublicObject(
  bucket: string,
  key: string,
  body: Uint8Array,
  contentType: string
) {
  const client = storageClient();
  await client.send(
    new PutObjectCommand({
      Bucket: bucket,
      Key: key,
      Body: body,
      ContentType: contentType,
      CacheControl: 'public, max-age=3600',
    })
  );

  const endpoint = required('AWS_ENDPOINT_URL_S3').replace(/\/$/, '');
  const encoded = key.split('/').map(encodeURIComponent).join('/');
  return `${endpoint}/${bucket}/${encoded}`;
}
