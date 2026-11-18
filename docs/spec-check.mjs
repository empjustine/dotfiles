#!/usr/bin/env node
// @fileoverview The documentation contract, enforced mechanically (DR-042).
//
// WHAT: walks the tree's Markdown, reads each document's frontmatter, and
// reports every violation of docs/spec-standard.md a machine can decide — the
// closed type/status vocabularies, required fields, id spelling and uniqueness,
// the parent edge, the decision log's record shape/numbering/status, every
// DR-NNN citation, relative links and anchors, section citations, and the
// component inventory against the files that actually exist.
//
// WHY: these docs are hand-maintained views over one system, and the drift is
// always the same shape — an inventory row for a deleted file, a citation to a
// record that moved, a path named in a requirement that no longer exists. The
// 2026-11-18 prune (DR-038) left exactly that debris.
//
// USAGE: node docs/spec-check.mjs [root] — the docs leg of ./lint.sh.
// Exit 0 clean, 1 findings, 2 cannot read the tree. Findings are plain lines
// 'path: [code] sentence' because a gate's output is meant to be read/diffed.

import fs from 'node:fs';
import path from 'node:path';

/** Scope, not genre — the five document roles this tree has. */
const TYPES = ['index', 'goal-and-requirements', 'architecture-design', 'decision-log', 'working-list'];

/** Lifecycle words; absence is drift, not a default. */
const STATUSES = ['draft', 'active', 'stale', 'done', 'deprecated'];

/** The decision log's own status vocabulary (heading cell 3). */
const DR_STATUSES = ['Accepted', 'Accidental', 'Proposed', 'Resolved', 'Withdrawn'];

/** Directories holding no repository prose. */
const SKIP_DIRS = new Set(['.git', '.vscode', 'node_modules']);

/** The one legal parent: the index is the graph root. */
const ROOT_ID = 'index';

/** The log is one file holding records; a node, not a shelf of nodes. */
const LOG_FILE = 'DECISIONS.md';

/** Trees whose every file must have a row in the inventory of docs/system.md. */
const INVENTORY_DIRS = ['profile.d', 'shortcuts/tasks'];

/** Directories whose shell files must carry a header comment (what/gate/DR). */
const SNIPPET_DIRS = ['profile.d'];

/** How far into a file the header block may sit. */
const HEADER_WINDOW = 16;

/** Loose files that must have a row there too. */
const INVENTORY_FILES = ['src-dotfiles.sh', 'deploy.sh', 'lint.sh', 'embed.mjs', 'unembed.mjs', 'docs/spec-check.mjs'];

/**
 * Docs held to the 'no path that no longer exists' rule: the normative pair
 * plus the inventory itself. design.md and execution-map.md are rationale
 * documents — they legitimately discuss pruned files and proposed paths,
 * and a gate that forbade those would forbid explaining the history.
 */
const PATH_STRICT_DOCS = new Set(['README.md', 'docs/system.md', 'docs/requirements.md']);

/** GitHub-ish heading slug: drop punctuation, spaces to dashes. */
function slug(text) {
  return text
    .toLowerCase()
    .replace(/\x60/g, '')
    .replace(/[^\p{L}\p{N} -]/gu, '')
    .trim()
    .replace(/ +/g, '-');
}

/** Reads the leading --- block. */
function readFrontmatter(source) {
  const fields = {};
  const lists = {};
  const lines = source.split('\n');
  if ((lines[0] ?? '').trim() !== '---') return { fields, lists, unterminated: false, present: false };
  let end = -1;
  for (let i = 1; i < lines.length; i += 1) {
    if (lines[i].trim() === '---') { end = i; break; }
  }
  if (end === -1) return { fields, lists, unterminated: true, present: true };
  let key;
  for (const line of lines.slice(1, end)) {
    if (line.trim() === '') continue;
    const pair = /^([A-Za-z][\w-]*):[ \t]*(.*)$/.exec(line);
    if (pair) { key = pair[1]; fields[key] = pair[2] ?? ''; continue; }
    const item = /^[ \t]*-[ \t]+(.*)$/.exec(line);
    if (item && key !== undefined) lists[key] = [...(lists[key] ?? []), unquote(item[1])];
  }
  for (const [name, raw] of Object.entries(fields)) {
    const trimmed = raw.trim();
    if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
      lists[name] = trimmed.slice(1, -1).split(',').map((part) => unquote(part)).filter((part) => part !== '');
      fields[name] = '';
    }
  }
  return { fields, lists, unterminated: false, present: true };
}

/** A value carrying a colon-space unquoted truncates in every YAML reader. */
function unquotedColon(raw) {
  const trimmed = raw.trim();
  if (trimmed.startsWith('"') || trimmed.startsWith("'")) return false;
  return trimmed.includes(': ');
}

function unquote(raw) {
  const trimmed = raw.trim();
  const quoted =
    (trimmed.startsWith('"') && trimmed.endsWith('"')) ||
    (trimmed.startsWith("'") && trimmed.endsWith("'"));
  return quoted && trimmed.length > 1 ? trimmed.slice(1, -1) : trimmed;
}

/** Brace form in a path names several files: a.{bash,zsh}. */
function expandBraces(token) {
  const match = /\{([^{}]*)\}/.exec(token);
  if (!match) return [token];
  const head = token.slice(0, match.index);
  const tail = token.slice(match.index + match[0].length);
  return match[1].split(',').flatMap((part) => expandBraces(head + part + tail));
}

/** @returns {string[]} repo-relative Markdown paths, forward slashes, sorted */
function walkMarkdown(root) {
  const found = [];
  const walk = (dir) => {
    const entries = fs.readdirSync(dir, { withFileTypes: true });
    entries.sort((left, right) => (left.name < right.name ? -1 : 1));
    for (const entry of entries) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) {
        if (SKIP_DIRS.has(entry.name)) continue;
        walk(full);
        continue;
      }
      if (!entry.name.endsWith('.md')) continue;
      found.push(path.relative(root, full).split(path.sep).join('/'));
    }
  };
  walk(root);
  return found;
}

function headingsOf(source) {
  const out = [];
  for (const line of source.split('\n')) {
    const match = /^(#{1,6})[ \t]+(.*)$/.exec(line);
    if (!match) continue;
    const text = match[2].replace(/[ \t]+#+[ \t]*$/, '');
    out.push({ level: match[1].length, text, slug: slug(text) });
  }
  return out;
}

/** Fenced code blocks hold examples, not claims. */
function fencedLines(source) {
  const flags = [];
  let inside = false;
  for (const line of source.split('\n')) {
    if (/^\s*(\x60\x60\x60|~~~)/.test(line)) { flags.push(true); inside = !inside; continue; }
    flags.push(inside);
  }
  return flags;
}

function decisionRecords(source) {
  const records = [];
  source.split('\n').forEach((line, index) => {
    const match = /^## DR-(\d+) \| (.+) \| (.+) \| (\d{4}-\d{2}(?:-\d{2})?)$/.exec(line);
    if (!match) return;
    records.push({ number: match[1], status: match[3].split(/[ ,(]/)[0], line: index + 1 });
  });
  return records;
}

function main() {
  const root = process.argv[2] ?? '.';
  let docs;
  try {
    docs = walkMarkdown(root).map((rel) => ({ path: rel, source: fs.readFileSync(path.join(root, rel), 'utf8') }));
  } catch (error) {
    console.error('spec-check: cannot read the tree: ' + error.message);
    process.exit(2);
  }

  const findings = [];
  const report = (file, code, message) => findings.push({ file, code, message });
  const nodes = [];
  const edges = [];
  const byId = new Map();
  const headings = new Map();
  for (const doc of docs) headings.set(doc.path, headingsOf(doc.source));

  // --- frontmatter contract ----------------------------------------------
  for (const doc of docs) {
    const fm = readFrontmatter(doc.source);
    if (fm.unterminated) { report(doc.path, 'frontmatter-unterminated', 'opening --- with no closing ---'); continue; }
    if (!fm.present) {
      report(doc.path, 'frontmatter-missing', 'every Markdown file here is a node: it needs id, type, status, title');
      continue;
    }
    for (const [key, raw] of Object.entries(fm.fields)) {
      if (unquotedColon(raw)) {
        report(doc.path, 'value-unquoted', key + ': contains a colon-space unquoted — every YAML reader truncates it there');
      }
    }
    const field = (name) => (fm.fields[name] ? unquote(fm.fields[name]) : undefined);
    const id = field('id');
    const type = field('type');
    const status = field('status');
    const title = field('title');
    const parent = field('parent');
    if (!id) report(doc.path, 'id-missing', 'no id — nothing can cite this document');
    if (!type) report(doc.path, 'type-missing', 'no type');
    if (!status) report(doc.path, 'status-missing', 'no status — absence is drift, not a default');
    if (!title) report(doc.path, 'title-missing', 'no title');
    if (id && !/^[a-z][a-z0-9]*(-[a-z0-9]+)*$/.test(id)) report(doc.path, 'id-spelling', 'id ' + id + ' is not lowercase kebab-case');
    if (type && !TYPES.includes(type)) report(doc.path, 'type-unknown', 'type ' + type + ' is not one of: ' + TYPES.join(', '));
    if (status && !STATUSES.includes(status)) report(doc.path, 'status-unknown', 'status ' + status + ' is not one of: ' + STATUSES.join(', '));
    if (type !== undefined && type !== 'index' && !parent) report(doc.path, 'parent-missing', 'no parent — every node but the root hangs off ' + ROOT_ID);
    if (parent && parent !== ROOT_ID) report(doc.path, 'parent-not-index', 'parent ' + parent + ' — the only legal parent here is ' + ROOT_ID);
    if (id && type) {
      nodes.push({ path: doc.path, id, type });
      const first = byId.get(id);
      if (first) report(doc.path, 'id-duplicate', 'id ' + id + ' is also claimed by ' + first);
      else byId.set(id, doc.path);
    }
    for (const edge of ['references', 'depends-on']) {
      for (const target of fm.lists[edge] ?? []) edges.push({ from: doc.path, edge, target });
    }
  }
  if (!nodes.some((node) => node.type === 'index')) report('README.md', 'root-missing', 'no node of type index — the graph has no root');
  // edges resolve after the whole tree is read: a doc may legitimately cite one
  // that sorts later (DECISIONS.md comes before docs/*.md in walk order)
  for (const edge of edges) {
    if (!byId.has(edge.target)) report(edge.from, 'edge-unresolved', edge.edge + ' names ' + edge.target + ', which is no node');
  }

  // --- every document opens with what it is ------------------------------
  for (const doc of docs) {
    const lines = doc.source.split('\n');
    const h1 = lines.findIndex((line) => /^#[ \t]+/.test(line));
    if (h1 === -1) { report(doc.path, 'opening-block-missing', 'no level-1 heading'); continue; }
    const after = lines.slice(h1 + 1);
    const stop = after.findIndex((line) => /^#{2,6}[ \t]+/.test(line));
    const block = (stop === -1 ? after : after.slice(0, stop)).filter((line) => line.trim() !== '');
    if (block.length === 0) report(doc.path, 'opening-block-missing', 'opens straight into sections — say what the document is first');
  }

  // --- links, anchors, section citations ---------------------------------
  for (const doc of docs) {
    const lines = doc.source.split('\n');
    lines.forEach((line, index) => {
      for (const match of line.matchAll(/\]\(([^)\s]+)\)/g)) {
        const target = match[1];
        if (/^(https?:|mailto:)/.test(target)) continue;
        const parts = target.split('#');
        const file = parts[0];
        const fragment = parts[1];
        let targetHeadings = headings.get(doc.path) ?? [];
        if (file) {
          const resolved = path.posix.normalize(path.posix.join(path.posix.dirname(doc.path), file));
          if (!fs.existsSync(path.join(root, resolved))) {
            report(doc.path + ':' + (index + 1), 'doc-link-unresolved', 'link target ' + resolved + ' does not exist');
            continue;
          }
          targetHeadings = headings.get(resolved) ?? headingsOf(fs.readFileSync(path.join(root, resolved), 'utf8'));
        }
        if (fragment && !targetHeadings.some((entry) => entry.slug === fragment)) {
          report(doc.path + ':' + (index + 1), 'doc-anchor-unresolved', 'no heading matching #' + fragment);
        }
      }
      for (const match of line.matchAll(/\u00a7(\d+(?:\.\d+)?)/g)) {
        const number = match[1];
        let targetPath = doc.path;
        // the cite names its document: the nearest path before it on the same
        // line, else the nearest one a few lines above (a list of cites can be
        // wrapped across lines)
        const nearest = (text, before) => {
          let found;
          for (const hit of text.matchAll(/\]\(([^)\s#]+\.md)|\x60([A-Za-z0-9_./-]+\.md)\x60/g)) {
            if (before !== undefined && hit.index >= before) break;
            found = hit[1] ?? hit[2];
          }
          return found;
        };
        const here = nearest(line, match.index);
        if (here !== undefined) {
          targetPath = path.posix.normalize(path.posix.join(path.posix.dirname(doc.path), here));
        } else {
          for (let back = index - 1; back >= Math.max(0, index - 6); back -= 1) {
            const above = nearest(lines[back] ?? '');
            if (above !== undefined) {
              targetPath = path.posix.normalize(path.posix.join(path.posix.dirname(doc.path), above));
              break;
            }
          }
        }
        const targetHeadings = headings.get(targetPath);
        if (!targetHeadings) {
          report(doc.path + ':' + (index + 1), 'section-cite-unresolved', 'cites ' + targetPath + ', which is no document');
          continue;
        }
        const pattern = new RegExp('^' + number.replaceAll('.', '\\.') + '(?:[.\\s]|$)');
        if (!targetHeadings.some((entry) => pattern.test(entry.text))) {
          report(doc.path + ':' + (index + 1), 'section-cite-unresolved', 'section ' + number + ' matches no heading in ' + targetPath);
        }
      }
    });
  }

  // --- the decision log --------------------------------------------------
  const log = docs.find((doc) => doc.path === LOG_FILE);
  const recordNumbers = new Set();
  if (!log) {
    report(LOG_FILE, 'log-missing', 'the decision log is part of the doc set');
  } else {
    const records = decisionRecords(log.source);
    let previous = 0;
    log.source.split('\n').forEach((line, index) => {
      if (!line.startsWith('## DR-')) return;
      if (!/^## DR-(\d{3}) \| (.+) \| (.+) \| (\d{4}-\d{2}(?:-\d{2})?)$/.test(line)) {
        report(LOG_FILE + ':' + (index + 1), 'dr-format', 'records read: ## DR-NNN | Title | Status | YYYY-MM-DD (day optional in older records)');
      }
    });
    for (const record of records) {
      const where = LOG_FILE + ':' + record.line;
      if (recordNumbers.has(record.number)) report(where, 'dr-numbering', 'DR-' + record.number + ' is claimed twice');
      recordNumbers.add(record.number);
      const numeric = Number(record.number);
      if (numeric <= previous) report(where, 'dr-numbering', 'DR-' + record.number + ' appears after a higher number — the log is append-only');
      previous = numeric;
      if (!DR_STATUSES.includes(record.status)) {
        report(where, 'dr-status-unknown', 'status ' + record.status + ' is not one of: ' + DR_STATUSES.join(', '));
      }
    }
    for (const doc of docs) {
      doc.source.split('\n').forEach((line, index) => {
        if (doc.path === LOG_FILE && line.startsWith('## DR-')) return;
        for (const match of line.matchAll(/DR-(\d{3})/g)) {
          if (!recordNumbers.has(match[1])) {
            report(doc.path + ':' + (index + 1), 'dr-unresolved', 'DR-' + match[1] + ' is not a record in ' + LOG_FILE);
          }
        }
      });
    }
  }

  // --- the component inventory vs the tree -------------------------------
  const inventoryPath = 'docs/system.md';
  const inventoryDoc = docs.find((doc) => doc.path === inventoryPath);
  const pathTokens = (source) => {
    const out = [];
    const joined = source.replace(/,\n[ \t]*/g, ',');
    for (const match of joined.matchAll(/(?:profile\.d|shortcuts\/tasks)\/[A-Za-z0-9_.{},-]+/g)) {
      for (const variant of expandBraces(match[0])) out.push(variant.replace(/[.,]$/, ''));
    }
    return out;
  };
  if (!inventoryDoc) {
    report(inventoryPath, 'inventory-doc-missing', 'the component inventory lives here');
  } else {
    const tokens = new Set(pathTokens(inventoryDoc.source));
    const basenames = new Set([...tokens].map((token) => token.split('/').pop()));
    const expected = [];
    for (const dir of INVENTORY_DIRS) {
      const full = path.join(root, dir);
      if (!fs.existsSync(full)) continue;
      for (const name of fs.readdirSync(full).sort()) expected.push(dir + '/' + name);
    }
    for (const name of INVENTORY_FILES) if (fs.existsSync(path.join(root, name))) expected.push(name);
    for (const name of expected) {
      const base = name.split('/').pop();
      const mentioned = tokens.has(name) || basenames.has(base) || inventoryDoc.source.includes(name);
      if (!mentioned) report(inventoryPath, 'inventory-missing', name + ' exists but has no row in the inventory');
    }
    for (const token of tokens) {
      if (token.endsWith('/')) continue;
      if (!fs.existsSync(path.join(root, token))) {
        report(inventoryPath, 'inventory-stale', token + ' has a row but no longer exists');
      }
    }
  }
  for (const doc of docs) {
    if (!PATH_STRICT_DOCS.has(doc.path)) continue;
    const fenced = fencedLines(doc.source);
    doc.source.split('\n').forEach((line, index) => {
      if (fenced[index]) return;
      for (const token of pathTokens(line)) {
        if (token.endsWith('/')) continue;
        if (!fs.existsSync(path.join(root, token))) {
          report(doc.path + ':' + (index + 1), 'doc-path-stale', token + ' does not exist — drop the mention or restore the file');
        }
      }
    });
  }

  // --- snippet headers (the comment half of the contract) -----------------
  for (const dir of SNIPPET_DIRS) {
    const full = path.join(root, dir);
    if (!fs.existsSync(full)) continue;
    for (const name of fs.readdirSync(full).sort()) {
      if (!/[.](sh|bash|zsh)$/.test(name)) continue;
      const rel = dir + '/' + name;
      const lines = fs.readFileSync(path.join(root, rel), 'utf8').split('\n');
      const head = lines.slice(1, 1 + HEADER_WINDOW).filter((line) => line.startsWith('#'));
      if (!head.some((line) => /Gate:/.test(line))) {
        report(rel, 'snippet-header', "no 'Gate:' line in the header — say when this snippet is allowed to run");
      }
      if (!head.some((line) => /DR-\d{3}/.test(line))) {
        report(rel, 'snippet-header', 'no DR-### in the header — point at the record that decided this shape');
      }
    }
  }

  // --- output ------------------------------------------------------------
  findings.sort((left, right) => (left.file + left.code < right.file + right.code ? -1 : 1));
  for (const finding of findings) console.log(finding.file + ': [' + finding.code + '] ' + finding.message);
  process.exit(findings.length === 0 ? 0 : 1);
}

main();
