import { test } from 'node:test';
import assert from 'node:assert/strict';
import { gridFor, tileRect } from './layout.js';

test('gridFor: 1 kaynak tam ekran', () => {
  assert.deepEqual(gridFor(1), { rows: 1, cols: 1 });
});

test('gridFor: 2 kaynak yan yana', () => {
  assert.deepEqual(gridFor(2), { rows: 1, cols: 2 });
});

test('gridFor: 3-4 kaynak 2x2', () => {
  assert.deepEqual(gridFor(3), { rows: 2, cols: 2 });
  assert.deepEqual(gridFor(4), { rows: 2, cols: 2 });
});

test('gridFor: 0 kaynakta 1x1 (eşleşme ekranı)', () => {
  assert.deepEqual(gridFor(0), { rows: 1, cols: 1 });
});

test('tileRect: 1920x1080 ekranda 2 kaynak', () => {
  assert.deepEqual(tileRect(0, 2, 1920, 1080), { x: 0, y: 0, w: 960, h: 1080 });
  assert.deepEqual(tileRect(1, 2, 1920, 1080), { x: 960, y: 0, w: 960, h: 1080 });
});

test('tileRect: 4 kaynakta 2. satıra geçer', () => {
  assert.deepEqual(tileRect(2, 4, 1000, 800), { x: 0, y: 400, w: 500, h: 400 });
});
