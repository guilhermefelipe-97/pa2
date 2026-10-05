// Geometria: bairro por polígono (ray casting) e geohash.
//
// Um bairro do OSM é uma relação multipolígono cujas vias-membro, juntas,
// fecham um ou mais anéis (externos e furos). A regra par-ímpar sobre TODAS as
// arestas dá o resultado certo sem precisar costurar os anéis: cada anel
// fechado contribui com a paridade dele, e um furo dentro de um anel externo
// cancela a do externo.

/**
 * @param {{lat:number,lng:number}} point
 * @param {Array<Array<{lat:number,lng:number}>>} lines vias-membro (abertas ou fechadas)
 */
function pointInMultipolygon(point, lines) {
  const { lat: y, lng: x } = point;
  let inside = false;
  for (const line of lines) {
    // Arestas (i-1 → i) da via; ela não fecha sozinha — o anel fecha com as
    // outras vias do mesmo multipolígono.
    for (let i = 1; i < line.length; i++) {
      const a = line[i - 1];
      const b = line[i];
      if (a.lat > y !== b.lat > y) {
        const xCross = a.lng + ((y - a.lat) / (b.lat - a.lat)) * (b.lng - a.lng);
        if (x < xCross) inside = !inside;
      }
    }
  }
  return inside;
}

/** Caixa envolvente para descartar polígonos distantes rapidamente. */
function bbox(lines) {
  let minLat = Infinity, maxLat = -Infinity, minLng = Infinity, maxLng = -Infinity;
  for (const line of lines) {
    for (const p of line) {
      if (p.lat < minLat) minLat = p.lat;
      if (p.lat > maxLat) maxLat = p.lat;
      if (p.lng < minLng) minLng = p.lng;
      if (p.lng > maxLng) maxLng = p.lng;
    }
  }
  return { minLat, maxLat, minLng, maxLng };
}

/**
 * Nome do bairro que contém o ponto, ou null.
 * @param {Array<{name:string, lines:Array, box?:object}>} neighborhoods
 */
function neighborhoodAt(point, neighborhoods) {
  for (const n of neighborhoods) {
    const b = n.box ?? (n.box = bbox(n.lines));
    if (point.lat < b.minLat || point.lat > b.maxLat || point.lng < b.minLng || point.lng > b.maxLng) {
      continue;
    }
    if (pointInMultipolygon(point, n.lines)) return n.name;
  }
  return null;
}

const BASE32 = '0123456789bcdefghjkmnpqrstuvwxyz';

/** Geohash padrão (alfabeto base32 de Niemeyer). */
function geohash(lat, lng, precision = 9) {
  let latLo = -90, latHi = 90, lngLo = -180, lngHi = 180;
  let hash = '';
  let bit = 0;
  let ch = 0;
  let even = true; // bits pares = longitude
  while (hash.length < precision) {
    if (even) {
      const mid = (lngLo + lngHi) / 2;
      if (lng >= mid) { ch = (ch << 1) | 1; lngLo = mid; } else { ch <<= 1; lngHi = mid; }
    } else {
      const mid = (latLo + latHi) / 2;
      if (lat >= mid) { ch = (ch << 1) | 1; latLo = mid; } else { ch <<= 1; latHi = mid; }
    }
    even = !even;
    if (++bit === 5) {
      hash += BASE32[ch];
      bit = 0;
      ch = 0;
    }
  }
  return hash;
}

module.exports = { pointInMultipolygon, neighborhoodAt, geohash, bbox };
