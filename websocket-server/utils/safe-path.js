const path = require('path');
const fs = require('fs');

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

const ALLOWED_EXT = {
    image: ['.jpg', '.jpeg', '.png', '.webp'],
    video: ['.mp4', '.mov'],
};

const ALLOWED_COMMANDS = ['deface', 'python3', 'ffmpeg'];

function assertUuid(value, fieldName) {
    if (typeof value !== 'string' || !UUID_RE.test(value)) {
        const err = new Error(`Invalid ${fieldName}: expected UUID format`);
        err.statusCode = 400;
        throw err;
    }
    return value;
}

function assertUuidOrNull(value, fieldName) {
    if (value === null || value === undefined || value === '') return null;
    return assertUuid(value, fieldName);
}

function safeJoin(baseDir, ...segments) {
    const base = path.resolve(baseDir);
    const target = path.resolve(base, ...segments);
    if (target !== base && !target.startsWith(base + path.sep)) {
        const err = new Error('Path escapes base directory');
        err.statusCode = 400;
        throw err;
    }
    return target;
}

function safeExtension(originalName, kind) {
    const ext = path.extname(originalName || '').toLowerCase();
    if (!ALLOWED_EXT[kind] || !ALLOWED_EXT[kind].includes(ext)) {
        const err = new Error(`Unsupported ${kind} file extension`);
        err.statusCode = 415;
        throw err;
    }
    return ext;
}

function safeFilename(originalName, kind) {
    const ext = safeExtension(originalName, kind);
    return `${require('uuid').v4()}${ext}`;
}

function assertAllowedCommand(cmd) {
    const basename = path.basename(cmd);
    if (!ALLOWED_COMMANDS.includes(basename)) {
        const err = new Error(`Disallowed command: ${basename}`);
        err.statusCode = 500;
        throw err;
    }
    return cmd;
}

function resolveExecutable(envVar, fallback) {
    const exe = process.env[envVar] || fallback;
    const resolved = path.resolve(exe);
    try {
        fs.accessSync(resolved, fs.constants.X_OK);
        return resolved;
    } catch {
        try {
            fs.accessSync(exe, fs.constants.X_OK);
            return exe;
        } catch {
            console.warn(`[safe-path] Executable not found or not executable: ${exe}`);
            return exe;
        }
    }
}

function sanitizeCacheKey(key) {
    return key.replace(/[*?\[\]]/g, '');
}

module.exports = {
    UUID_RE,
    ALLOWED_EXT,
    ALLOWED_COMMANDS,
    assertUuid,
    assertUuidOrNull,
    safeJoin,
    safeExtension,
    safeFilename,
    assertAllowedCommand,
    resolveExecutable,
    sanitizeCacheKey,
};
