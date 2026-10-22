#!/usr/bin/env node
/*
 * patch-asar.js - build-time patcher for Pinokio's app.asar.
 *
 * Fixed here, both regressions of the stock 8.2.0 Linux build:
 *
 *  1. main.js calls app.disableHardwareAcceleration(). On Linux that pins the
 *     renderer to SwiftShader (software rendering). We neutralise the call so
 *     Electron keeps using a GPU when one is present.
 *
 *  2. pinokiod's local-sharing proxy (node_modules/pinokiod/kernel/lproxy.js)
 *     calls proxy.listen(port) with a caller supplied, fixed port. Starting a
 *     second app that also wants local sharing throws EADDRINUSE, which
 *     nothing catches: it becomes an uncaughtException and kills pinokiod.
 *     We make listen() fall back to a free port when the requested one is
 *     taken.
 *
 * Uses @electron/asar for extraction/packing, so the archive's integrity hash
 * is rewritten correctly.
 *
 * Usage: patch-asar.js /opt/Pinokio/resources/app.asar
 */
'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync } = require('child_process');

const asar = require('@electron/asar');

const asarPath = process.argv[2] || '/opt/Pinokio/resources/app.asar';

const GPU_MARK = 'app.disableHardwareAcceleration()';
const LPROXY_MARK = 'proxy.listen(port)';

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'asar-patch-'));
let changed = 0;

try {
  asar.extractAll(asarPath, tmp);

  // --- 1. re-enable GPU acceleration -------------------------------------
  const mainPath = path.join(tmp, 'main.js');
  if (fs.existsSync(mainPath)) {
    let src = fs.readFileSync(mainPath, 'utf8');
    if (src.includes(GPU_MARK)) {
      src = src.replace(
        /app\.disableHardwareAcceleration\(\);/g,
        'void 0; /* disabled by pinokio-docker: keep GPU acceleration */'
      );
      fs.writeFileSync(mainPath, src);
      changed++;
      console.log('[patch-asar] re-enabled GPU acceleration in main.js');
    } else {
      console.log('[patch-asar] main.js: nothing to do');
    }
  }

  // --- 2. make the local-sharing proxy tolerate a busy port ---------------
  const lproxyPath = path.join(
    tmp,
    'node_modules/pinokiod/kernel/lproxy.js'
  );
  if (fs.existsSync(lproxyPath)) {
    let src = fs.readFileSync(lproxyPath, 'utf8');
    if (src.includes(LPROXY_MARK) && !src.includes('LPROXY_FALLBACK')) {
      const replacement = [
        '{ /* LPROXY_FALLBACK */',
        '      try {',
        '        proxy.listen(port)',
        '      } catch (err) {',
        '        if (err && (err.code === "EADDRINUSE" || err.code === "EACCES")) {',
        '          const fallback = await portfinder.getPortPromise({ port: 42003 })',
        '          console.log("lproxy: port", port, "unavailable (" + err.code + "), falling back to", fallback)',
        '          port = fallback',
        '          proxy.listen(fallback)',
        '        } else {',
        '          throw err',
        '        }',
        '      }',
        '    }',
      ].join('\n');
      src = src.replace(LPROXY_MARK, replacement);
      fs.writeFileSync(lproxyPath, src);
      changed++;
      console.log('[patch-asar] made lproxy.listen() tolerate a busy port');
    } else {
      console.log('[patch-asar] lproxy.js: nothing to do');
    }
  }

  if (changed === 0) {
    console.log('[patch-asar] archive already patched or expected code absent');
    process.exit(0);
  }

  // Repack in place: asar.createPackage writes a fresh archive with a valid
  // integrity hash, then we move it over the original.
  const repacked = asarPath + '.repacked';
  asar.createPackage(tmp, repacked).then(() => {
    fs.renameSync(repacked, asarPath);
    console.log('[patch-asar] archive rewritten');
  }).catch((e) => {
    console.error('[patch-asar] repack failed:', e);
    process.exit(1);
  });
} finally {
  // tmp is cleaned up by the caller (Dockerfile) via rm -rf of the build dir;
  // do not delete here so failures can be inspected.
}
