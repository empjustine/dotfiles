#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';

function unescapeHtml(str) {
  // Named entities first, *then* &amp; — otherwise &amp;lt; would become
  // &lt; (via &amp;→&) and then be further unescaped to <.
  return str
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'")
    .replace(/&amp;/g, '&');
}

/**
 * Return the text content of a balanced tag at position `start`.
 * Expects `<tagName…>` at `html[start]`, returns { content, end }
 * where end is the position right after `</tagName>`.
 */
function extractTag(html, start, tagName) {
  const openEnd = html.indexOf('>', start);
  if (openEnd === -1) return null;
  const contentStart = openEnd + 1;

  const closeTag = `</${tagName}>`;
  const closeStart = html.indexOf(closeTag, contentStart);
  if (closeStart === -1) return null;

  const content = html.slice(contentStart, closeStart);
  return {
    content,
    end: closeStart + closeTag.length,
  };
}

// String scanning (no regex); entry contract with embed.mjs: { filename, buffer }.
function parseHtml(html) {
  const entries = [];
  let pos = 0;

  while (true) {
    const dtStart = html.indexOf('<dt>', pos);
    if (dtStart === -1) break;

    const dtEnd = html.indexOf('</dt>', dtStart + 4);
    if (dtEnd === -1) break;
    const rawFilename = html.slice(dtStart + 4, dtEnd);
    const filename = unescapeHtml(rawFilename.trim());

    const ddStart = html.indexOf('<dd>', dtEnd + 5);
    if (ddStart === -1) break;

    // Extract dd content
    const ddEnd = html.indexOf('</dd>', ddStart + 4);
    if (ddEnd === -1) break;
    const rawDd = html.slice(ddStart + 4, ddEnd);

    let buffer = null;

    // Case 1: <img src="data:…;base64,…">
    if (rawDd.startsWith('<img ')) {
      const srcIdx = rawDd.indexOf(' src="');
      if (srcIdx !== -1) {
        const valStart = srcIdx + 6; // past ' src="'
        const valEnd = rawDd.indexOf('"', valStart);
        if (valEnd !== -1) {
          const src = rawDd.slice(valStart, valEnd);
          const comma = src.lastIndexOf(',');
          if (comma !== -1) {
            const b64 = src.slice(comma + 1);
            buffer = Buffer.from(b64, 'base64');
          }
        }
      }
    }

    // Case 2: <p>-----BEGIN BASE64-----</p><pre>…</pre><p>-----END BASE64-----</p>
    if (buffer === null && rawDd.indexOf('<p>-----BEGIN BASE64-----</p>') !== -1) {
      const preStart = rawDd.indexOf('<pre>');
      if (preStart !== -1) {
        const pre = extractTag(rawDd, preStart, 'pre');
        if (pre) {
          const joined = pre.content.replace(/\s+/g, '');
          buffer = Buffer.from(joined, 'base64');
        }
      }
    }

    // Case 3: <pre>…</pre>  (plaintext, possibly with <code> wrapper)
    if (buffer === null) {
      const preStart = rawDd.indexOf('<pre>');
      if (preStart !== -1) {
        const pre = extractTag(rawDd, preStart, 'pre');
        if (pre) {
          let raw;
          // If pre content is wrapped in <code>, unwrap it
          if (pre.content.trimStart().startsWith('<code>')) {
            const code = extractTag(rawDd, preStart + 5, 'code');
            if (code) {
              raw = code.content;
            } else {
              raw = pre.content;
            }
          } else {
            raw = pre.content;
          }
          const decoded = unescapeHtml(raw);
          buffer = Buffer.from(decoded, 'utf8');
        }
      }
    }

    if (buffer !== null) {
      entries.push({ filename, buffer });
    }

    pos = ddEnd + 5;
  }

  return entries;
}

function usage() {
  console.error('Usage: unembed-files <input.html> [output-directory]');
  process.exit(1);
}

function main() {
  const args = process.argv.slice(2);
  if (args.length < 1) usage();

  const inputHtml = args[0];
  const outDir = args[1] || '.';

  if (!fs.existsSync(inputHtml)) {
    console.error(`Error: '${inputHtml}' does not exist`);
    process.exit(1);
  }

  const html = fs.readFileSync(inputHtml, 'utf8');
  const entries = parseHtml(html);

  if (entries.length === 0) {
    console.error('Error: No embedded files found in the HTML');
    process.exit(1);
  }

  fs.mkdirSync(outDir, { recursive: true });

  for (const entry of entries) {
    const outPath = path.join(outDir, path.basename(entry.filename));
    fs.writeFileSync(outPath, entry.buffer);
    console.log(`  ${outPath}  (${entry.buffer.length} bytes)`);
  }

  console.log(`\nExtracted ${entries.length} file(s) to ${path.resolve(outDir)}`);
}

main();
