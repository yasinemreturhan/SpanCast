// Sunucudan WebRTC ICE yapılandırmasını çeker. Hata durumunda boş dizi döner
// (LAN bağlantısı STUN olmadan da çalışabilir).
export async function fetchIceServers(fetchFn = fetch) {
  try {
    const r = await fetchFn('/api/ice');
    if (!r.ok) return [];
    const data = await r.json();
    return Array.isArray(data.iceServers) ? data.iceServers : [];
  } catch {
    return [];
  }
}
