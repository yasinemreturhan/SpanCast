// Multi-share grid yerleşimi: kaynak sayısına göre satır/sütun ve her
// karonun (tile) piksel dikdörtgeni. Saf fonksiyonlar — node ile test edilir.

/** Kaynak sayısına göre grid boyutu. 0-1→1×1, 2→1×2, 3-4→2×2. */
export function gridFor(n) {
  if (n <= 1) return { rows: 1, cols: 1 };
  if (n === 2) return { rows: 1, cols: 2 };
  return { rows: 2, cols: 2 };
}

/** i. karonun (0 tabanlı) W×H alandaki dikdörtgeni. */
export function tileRect(i, n, W, H) {
  const { rows, cols } = gridFor(n);
  const w = Math.floor(W / cols);
  const h = Math.floor(H / rows);
  const col = i % cols;
  const row = Math.floor(i / cols);
  return { x: col * w, y: row * h, w, h };
}
