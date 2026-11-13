import { inflateRawSync } from "node:zlib";
import { DomainError } from "./core.mjs";

export const MAX_ATTACHMENT_BYTES = 1_500_000;
const MIME_TYPES = new Set([
  "application/pdf", "image/png", "image/jpeg", "image/webp",
  "text/plain", "text/markdown",
  "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
]);
const wordMime = "application/vnd.openxmlformats-officedocument.wordprocessingml.document";
function isValid(buffer, mime) {
  if (mime === "application/pdf") return buffer.subarray(0, 5).toString("latin1") === "%PDF-";
  if (mime === "image/png") return buffer.subarray(0, 8).equals(Buffer.from("89504e470d0a1a0a", "hex"));
  if (mime === "image/jpeg") return buffer.subarray(0, 3).equals(Buffer.from("ffd8ff", "hex"));
  if (mime === "image/webp") return buffer.subarray(0, 4).toString() === "RIFF" && buffer.subarray(8, 12).toString() === "WEBP";
  if (mime === wordMime) return buffer.subarray(0, 4).toString() === "PK\x03\x04";
  if (mime === "text/plain" || mime === "text/markdown") {
    try { return !new TextDecoder("utf-8", { fatal: true }).decode(buffer).includes("\0"); }
    catch { return false; }
  }
  return false;
}
export function validateFile({ name, mimeType, base64 } = {}) {
  if (typeof name !== "string" || !/^[^\u0000-\u001f\\/]{1,120}$/.test(name) ||
      !MIME_TYPES.has(mimeType) || typeof base64 !== "string" ||
      base64.length > Math.ceil(MAX_ATTACHMENT_BYTES / 3) * 4 + 8 ||
      !/^[A-Za-z0-9+/]+={0,2}$/.test(base64)) throw new DomainError(400, "Unsupported or oversized attachment");
  const buffer = Buffer.from(base64, "base64");
  if (!buffer.length || buffer.length > MAX_ATTACHMENT_BYTES ||
      buffer.toString("base64") !== base64 || !isValid(buffer, mimeType)) {
    throw new DomainError(400, "Attachment format does not match content or exceeds size limit");
  }
  return buffer;
}
const decodeXml = str => str.replace(/&lt;/g, "<").replace(/&gt;/g, ">")
  .replace(/&quot;/g, '"').replace(/&apos;/g, "'").replace(/&amp;/g, "&")
  .replace(/&#(\d+);/g, (_, code) => String.fromCodePoint(Math.min(Number(code), 0x10ffff)));
// Read ONLY word/document.xml through the ZIP central directory. Do not extract
// arbitrary archive members or trust paths. Bound decompressed output to avoid bombs.
export function docxText(zip) {
  let eocd = -1;
  for (let i = zip.length - 22; i >= Math.max(0, zip.length - 65557); i--) {
    if (zip.readUInt32LE(i) === 0x06054b50) { eocd = i; break; }
  }
  if (eocd < 0) throw new DomainError(400, "Invalid DOCX archive");
  let cursor = zip.readUInt32LE(eocd + 16);
  const total = zip.readUInt16LE(eocd + 10);
  if (total > 1000) throw new DomainError(400, "DOCX contains too many entries");
  let xml;
  for (let i = 0; i < total; i++) {
    if (cursor + 46 > zip.length || zip.readUInt32LE(cursor) !== 0x02014b50) break;
    const nameLength = zip.readUInt16LE(cursor + 28);
    const extra = zip.readUInt16LE(cursor + 30);
    const comment = zip.readUInt16LE(cursor + 32);
    const name = zip.subarray(cursor + 46, cursor + 46 + nameLength).toString("utf8");
    if (name === "word/document.xml") {
      const method = zip.readUInt16LE(cursor + 10);
      const flags = zip.readUInt16LE(cursor + 8);
      const compressed = zip.readUInt32LE(cursor + 20);
      const uncompressed = zip.readUInt32LE(cursor + 24);
      const offset = zip.readUInt32LE(cursor + 42);
      if (flags & 1 || compressed > MAX_ATTACHMENT_BYTES || uncompressed > 500_000 ||
          offset + 30 > zip.length || zip.readUInt32LE(offset) !== 0x04034b50) {
        throw new DomainError(400, "Unsupported DOCX encoding");
      }
      const start = offset + 30 + zip.readUInt16LE(offset + 26) + zip.readUInt16LE(offset + 28);
      if (start + compressed > zip.length) throw new DomainError(400, "Corrupt DOCX content");
      const body = zip.subarray(start, start + compressed);
      try { xml = method === 0 ? body.toString("utf8") :
        method === 8 ? inflateRawSync(body, { maxOutputLength: 500_001 }).toString("utf8") : null; }
      catch { throw new DomainError(400, "DOCX decompression rejected"); }
      break;
    }
    cursor += 46 + nameLength + extra + comment;
  }
  if (!xml || !xml.includes("<w:document")) throw new DomainError(400, "DOCX document text not found");
  const normalized = xml.replace(/<w:tab\b[^>]*\/>/g, "\t")
    .replace(/<w:br\b[^>]*\/>/g, "\n").replace(/<\/w:p>/g, "\n");
  const text = normalized.replace(/<w:t(?:\s[^>]*)?>([\s\S]*?)<\/w:t>/g, (_, value) =>
    decodeXml(value)).replace(/<[^>]*>/g, "");
  return text.slice(0, 50000).trim();
}
export function attachmentForModel(item, binary) {
  const buffer = Buffer.from(binary, "base64");
  if (item.mimeType === wordMime) {
    return { name: item.name, mimeType: "text/plain", text: docxText(buffer) };
  }
  if (item.mimeType === "text/plain" || item.mimeType === "text/markdown") {
    return { name: item.name, mimeType: "text/plain",
      text: new TextDecoder("utf-8", { fatal: true }).decode(buffer).slice(0, 50000) };
  }
  return { name: item.name, mimeType: item.mimeType, base64: binary };
}
