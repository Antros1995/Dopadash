import type { EncryptedValue } from "./types";

function toBase64(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary);
}

function fromBase64(value: string): Uint8Array<ArrayBuffer> {
  const binary = atob(value);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) {
    bytes[index] = binary.charCodeAt(index);
  }
  return bytes;
}

async function importKey(base64Key: string): Promise<CryptoKey> {
  const bytes = fromBase64(base64Key);
  if (bytes.byteLength !== 32) {
    throw new Error("MICROSOFT_TOKEN_ENCRYPTION_KEY must contain 32 bytes");
  }
  return crypto.subtle.importKey("raw", bytes, "AES-GCM", false, [
    "encrypt",
    "decrypt",
  ]);
}

export async function encryptSecret(
  value: string,
  base64Key: string,
): Promise<EncryptedValue> {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const ciphertext = await crypto.subtle.encrypt(
    { name: "AES-GCM", iv },
    await importKey(base64Key),
    new TextEncoder().encode(value),
  );
  return {
    iv: toBase64(iv),
    ciphertext: toBase64(new Uint8Array(ciphertext)),
  };
}

export async function decryptSecret(
  value: EncryptedValue,
  base64Key: string,
): Promise<string> {
  const plaintext = await crypto.subtle.decrypt(
    { name: "AES-GCM", iv: fromBase64(value.iv) },
    await importKey(base64Key),
    fromBase64(value.ciphertext),
  );
  return new TextDecoder().decode(plaintext);
}

export function randomBase64Url(byteLength = 32): string {
  return toBase64(crypto.getRandomValues(new Uint8Array(byteLength)))
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replace(/=+$/u, "");
}

export async function sha256Base64Url(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return toBase64(new Uint8Array(digest))
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replace(/=+$/u, "");
}
