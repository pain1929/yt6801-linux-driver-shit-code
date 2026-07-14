const fs = require('fs');
const path = require('path');

const root = process.cwd();
const exts = new Set([
  '.sh',
  '.c',
  '.h',
  '.txt',
  '.md',
  '.conf',
]);
const names = new Set([
  'Makefile',
  'README',
  'motorcomm',
  'dkms.conf',
]);

function shouldConvert(filePath) {
  const base = path.basename(filePath);
  return names.has(base) || exts.has(path.extname(filePath));
}

function normalizeFile(filePath) {
  const original = fs.readFileSync(filePath, 'utf8');
  const normalized = original.replace(/\r\n/g, '\n');
  if (normalized !== original) {
    fs.writeFileSync(filePath, normalized, 'utf8');
    console.log(`LF fixed: ${path.relative(root, filePath)}`);
  }
}

function walk(dirPath) {
  for (const entry of fs.readdirSync(dirPath, { withFileTypes: true })) {
    if (entry.name === '.git') {
      continue;
    }

    const fullPath = path.join(dirPath, entry.name);
    if (entry.isDirectory()) {
      walk(fullPath);
      continue;
    }

    if (entry.isFile() && shouldConvert(fullPath)) {
      normalizeFile(fullPath);
    }
  }
}

walk(root);
console.log('done');
