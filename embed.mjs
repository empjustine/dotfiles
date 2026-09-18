#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';

function escapeHtml(str) {
  return str
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

const TEXT_EXTENSIONS = new Set([
  '.txt', '.text', '.md', '.markdown',
  '.js', '.mjs', '.cjs', '.jsx', '.ts', '.tsx',
  '.json', '.xml', '.html', '.htm', '.xhtml',
  '.css', '.scss', '.sass', '.less',
  '.yaml', '.yml', '.toml', '.ini', '.cfg', '.conf',
  '.sh', '.bash', '.zsh', '.fish',
  '.py', '.rb', '.php', '.pl', '.pm', '.lua',
  '.java', '.c', '.h', '.cpp', '.hpp', '.cs', '.go', '.rs',
  '.sql', '.csv', '.tsv',
  '.svg', '.diff', '.patch',
  '.log', '.env', '.gitignore', '.editorconfig',
  '.vue', '.svelte', '.astro',
]);

function isPlaintexty(filePath, buffer) {
  const ext = path.extname(filePath).toLowerCase();
  if (TEXT_EXTENSIONS.has(ext)) return true;

  const sniffLen = Math.min(buffer.length, 4096);
  for (let i = 0; i < sniffLen; i++) {
    if (buffer[i] === 0) return false;
  }
  try {
    const decoded = buffer.toString('utf8');
    // Re-encode and compare length to catch multi-byte corruption
    const reEncoded = Buffer.from(decoded, 'utf8');
    if (reEncoded.length !== buffer.length) return false;
    return true;
  } catch {
    return false;
  }
}

const IMAGE_EXTENSIONS = {
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.gif': 'image/gif',
  '.webp': 'image/webp',
  '.bmp': 'image/bmp',
  '.tiff': 'image/tiff',
  '.tif': 'image/tiff',
  '.avif': 'image/avif',
  '.ico': 'image/x-icon',
};

function usage() {
  console.error('Usage: embed-files <input1> [input2 ...]');
  process.exit(1);
}

function main() {
  const inputPaths = process.argv.slice(2);
  if (inputPaths.length < 1) usage();

  const files = inputPaths.map((filePath) => {
    if (!fs.existsSync(filePath)) {
      console.error(`Error: Input file '${filePath}' does not exist`);
      process.exit(1);
    }
    const buffer = fs.readFileSync(filePath);
    return {
      displayPath: filePath,
      name: path.basename(filePath),
      buffer,
      plaintexty: isPlaintexty(filePath, buffer),
    };
  });

  let html = `<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en">
<head>
<meta charset="utf-8"/>
<title>Embedded Files</title>
</head>
<body>
<dl>`;

  for (const file of files) {
    html += `\n<dt>${escapeHtml(file.displayPath)}</dt>`;

    if (file.plaintexty) {
      const content = file.buffer.toString('utf8');
      html += `\n<dd><pre>${escapeHtml(content)}</pre></dd>`;
    } else {
      const ext = path.extname(file.name).toLowerCase();
      const mime = IMAGE_EXTENSIONS[ext];
      if (mime) {
        const b64 = file.buffer.toString('base64');
        html += `\n<dd><img src="data:${mime};base64,${escapeHtml(b64)}" alt="${escapeHtml(file.name)}"/></dd>`;
      } else {
        const b64 = file.buffer.toString('base64');
        // Fold at 72 columns and wrap in pseudo-ascii-armor markers.
        const folded = [];
        for (let i = 0; i < b64.length; i += 72) {
          folded.push(b64.slice(i, i + 72));
        }
        html += `\n<dd>`;
        html += `\n<p>-----BEGIN BASE64-----</p>`;
        html += `\n<pre>${escapeHtml(folded.join('\n'))}</pre>`;
        html += `\n<p>-----END BASE64-----</p>`;
        html += `\n</dd>`;
      }
    }
  }

  html += `\n</dl>\n</body>\n</html>\n`;

  process.stdout.write(html);

  // Progress messages go to stderr so they don't pollute the HTML on stdout.
  console.error(`Embedded ${files.length} file(s):`);
  for (const file of files) {
    let kind;
    if (file.plaintexty) {
      kind = 'plaintext';
    } else if (IMAGE_EXTENSIONS[path.extname(file.name).toLowerCase()]) {
      kind = 'image';
    } else {
      kind = 'base64';
    }
    console.error(`  - ${file.displayPath}  [${kind}]`);
  }
}

main();
