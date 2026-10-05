// Funções puras do import do OpenStreetMap (sem emulator):
//   npx mocha tests/osm.test.js
const assert = require('node:assert/strict');
const fixtures = require('./fixtures/search-tokens.json');
const { fold, words, searchTokens, nameLower } = require('../seed/osm/tokens');
const { categoryFor, cuisineLabel, CATEGORIES } = require('../seed/osm/category');
const { pointInMultipolygon, neighborhoodAt, geohash } = require('../seed/osm/geo');
const { placeId, toPlace, buildSnapshot, parseNeighborhoods, checkSnapshot } = require('../seed/osm/places');
const { matchCurated, buildPlaceDocs } = require('../seed/osm/match');

/** Quadrado [lat0,lat1]×[lng0,lng1] partido em duas vias abertas (como membros OSM). */
function squareAsTwoWays(lat0, lat1, lng0, lng1) {
  return [
    [{ lat: lat0, lng: lng0 }, { lat: lat0, lng: lng1 }, { lat: lat1, lng: lng1 }],
    [{ lat: lat1, lng: lng1 }, { lat: lat1, lng: lng0 }, { lat: lat0, lng: lng0 }],
  ];
}

describe('tokens de busca (regras idênticas às do app)', () => {
  for (const c of fixtures.tokens) {
    it(`searchTokens(${JSON.stringify(c.input)})`, () => {
      assert.deepEqual(searchTokens(c.input), c.expected);
    });
  }
  for (const c of fixtures.words) {
    it(`words(${JSON.stringify(c.input)})`, () => {
      assert.deepEqual(words(c.input), c.expected);
    });
  }
  for (const c of fixtures.nameLower) {
    it(`nameLower(${JSON.stringify(c.input)})`, () => {
      assert.equal(nameLower(c.input), c.expected);
    });
  }

  it('fold remove acento e caixa', () => {
    assert.equal(fold('ÁGUA Ê ÇÃO'), 'agua e cao');
  });

  it('"camar" é token de "Camarões Potiguar"', () => {
    assert.ok(searchTokens('Camarões Potiguar').includes('camar'));
  });
});

describe('categoria pt-BR', () => {
  it('amenity sem cozinha', () => {
    assert.equal(categoryFor('restaurant'), 'Restaurante');
    assert.equal(categoryFor('fast_food'), 'Lanchonete');
    assert.equal(categoryFor('bar'), 'Bar');
    assert.equal(categoryFor('pub'), 'Pub');
    assert.equal(categoryFor('cafe'), 'Café');
    assert.equal(categoryFor('ice_cream'), 'Sorveteria');
    assert.equal(categoryFor('food_court'), 'Praça de alimentação');
    assert.equal(categoryFor('biergarten'), 'Cervejaria');
  });

  it('cozinha refina restaurante/lanchonete; a 1ª reconhecida vence', () => {
    assert.equal(categoryFor('restaurant', 'pizza;italian'), 'Pizzaria');
    assert.equal(categoryFor('restaurant', 'xyz;seafood'), 'Frutos do mar');
    assert.equal(categoryFor('fast_food', 'burger'), 'Hamburgueria');
    assert.equal(categoryFor('restaurant', 'regional'), 'Comida regional');
    assert.equal(categoryFor('restaurant', 'desconhecida'), 'Restaurante');
  });

  it('curados usam o mesmo vocabulário de categoria do OSM (chips não duplicam)', () => {
    const curated = require('../seed/places.json');
    for (const p of curated) assert.ok(CATEGORIES.includes(p.category), `${p.id}: "${p.category}"`);
  });

  it('cozinha não muda bar/café', () => {
    assert.equal(categoryFor('bar', 'pizza'), 'Bar');
    assert.equal(categoryFor('cafe', 'coffee_shop'), 'Café');
  });

  it('rótulo da cozinha (vocabulário próprio, não o de categoria)', () => {
    assert.equal(cuisineLabel('pizza;italian'), 'Pizza, Italiana');
    assert.equal(cuisineLabel('japanese;chinese'), 'Japonesa, Chinesa');
    assert.equal(cuisineLabel(' seafood ; fish_and_chips '), 'Frutos do mar, Fish and chips');
    assert.equal(cuisineLabel(undefined), '');
  });

  it('sinônimos de cozinha viram um rótulo só', () => {
    assert.equal(cuisineLabel('regional;local'), 'Comida regional');
    assert.equal(cuisineLabel('steak_house;barbecue;churrascaria'), 'Churrasco');
    assert.equal(cuisineLabel('acai;açaí'), 'Açaí');
    assert.equal(cuisineLabel('coffee_shop;cafe'), 'Café');
  });
});

describe('point-in-polygon (ray casting, multipolígono)', () => {
  const square = squareAsTwoWays(0, 10, 0, 10);

  it('dentro e fora de um anel formado por vias abertas', () => {
    assert.equal(pointInMultipolygon({ lat: 5, lng: 5 }, square), true);
    assert.equal(pointInMultipolygon({ lat: 5, lng: 15 }, square), false);
    assert.equal(pointInMultipolygon({ lat: -1, lng: 5 }, square), false);
  });

  it('furo (inner) exclui o ponto', () => {
    const withHole = [...square, ...squareAsTwoWays(4, 6, 4, 6)];
    assert.equal(pointInMultipolygon({ lat: 5, lng: 5 }, withHole), false);
    assert.equal(pointInMultipolygon({ lat: 2, lng: 2 }, withHole), true);
  });

  it('dois anéis externos separados', () => {
    const two = [...square, ...squareAsTwoWays(20, 30, 20, 30)];
    assert.equal(pointInMultipolygon({ lat: 25, lng: 25 }, two), true);
    assert.equal(pointInMultipolygon({ lat: 15, lng: 15 }, two), false);
  });

  it('neighborhoodAt devolve o bairro ou null', () => {
    const ns = [
      { name: 'A', lines: squareAsTwoWays(0, 10, 0, 10) },
      { name: 'B', lines: squareAsTwoWays(0, 10, 10, 20) },
    ];
    assert.equal(neighborhoodAt({ lat: 5, lng: 15 }, ns), 'B');
    assert.equal(neighborhoodAt({ lat: 50, lng: 50 }, ns), null);
  });
});

describe('geohash', () => {
  it('valores de referência', () => {
    assert.equal(geohash(57.64911, 10.40744, 11), 'u4pruydqqvj');
    assert.equal(geohash(-5.8031189, -35.2199833), '7nyyyx9d6');
  });

  it('precisão padrão 9', () => {
    assert.equal(geohash(-5.79, -35.2).length, 9);
  });
});

describe('conversão do Overpass', () => {
  const bairro = {
    type: 'relation',
    id: 1,
    tags: { admin_level: '10', name: 'Ponta Negra' },
    members: [
      { type: 'way', role: 'outer', geometry: [{ lat: -6, lon: -36 }, { lat: -6, lon: -35 }, { lat: -5, lon: -35 }] },
      { type: 'way', role: 'outer', geometry: [{ lat: -5, lon: -35 }, { lat: -5, lon: -36 }, { lat: -6, lon: -36 }] },
    ],
  };

  it('id osm-{n|w|r}{id}', () => {
    assert.equal(placeId({ type: 'node', id: 1 }), 'osm-n1');
    assert.equal(placeId({ type: 'way', id: 2 }), 'osm-w2');
    assert.equal(placeId({ type: 'relation', id: 3 }), 'osm-r3');
  });

  it('local com bairro por polígono, endereço, horário bruto e tokens', () => {
    const ns = parseNeighborhoods([bairro]);
    const p = toPlace(
      {
        type: 'way',
        id: 9,
        center: { lat: -5.5, lon: -35.5 },
        tags: {
          amenity: 'restaurant',
          name: 'Camarões Potiguar',
          cuisine: 'seafood',
          'addr:street': 'Rua Pedro Fonseca Filho',
          'addr:housenumber': '8887',
          opening_hours: 'Mo-Su 11:30-23:00',
          'addr:suburb': 'Outro',
        },
      },
      ns,
    );
    assert.deepEqual(p, {
      id: 'osm-w9',
      osmId: 'way/9',
      name: 'Camarões Potiguar',
      category: 'Frutos do mar',
      cuisine: 'Frutos do mar',
      neighborhood: 'Ponta Negra',
      city: 'Natal',
      address: 'Rua Pedro Fonseca Filho, 8887',
      openingHours: 'Mo-Su 11:30-23:00',
      lat: -5.5,
      lng: -35.5,
      geohash: geohash(-5.5, -35.5, 9),
    });
    assert.equal(p.searchTokens, undefined, 'tokens são derivados no seed, não vão ao snapshot');
  });

  it('fora dos bairros: addr:suburb ou ""', () => {
    const ns = parseNeighborhoods([bairro]);
    const base = { type: 'node', id: 1, lat: 10, lon: 10 };
    assert.equal(toPlace({ ...base, tags: { amenity: 'bar', name: 'X', 'addr:suburb': 'Redinha' } }, ns).neighborhood, 'Redinha');
    assert.equal(toPlace({ ...base, tags: { amenity: 'bar', name: 'X' } }, ns).neighborhood, '');
  });

  it('ignora sem nome, amenity fora da lista ou sem coordenada', () => {
    assert.equal(toPlace({ type: 'node', id: 1, lat: 0, lon: 0, tags: { amenity: 'bar' } }, []), null);
    assert.equal(toPlace({ type: 'node', id: 1, lat: 0, lon: 0, tags: { amenity: 'bank', name: 'B' } }, []), null);
    assert.equal(toPlace({ type: 'way', id: 1, tags: { amenity: 'bar', name: 'B' } }, []), null);
  });

  it('centro só vale com lat E lon numéricos', () => {
    const tags = { amenity: 'bar', name: 'B' };
    assert.equal(toPlace({ type: 'way', id: 1, center: { lat: -5.8 }, tags }, []), null);
    assert.equal(toPlace({ type: 'way', id: 1, center: { lat: -5.8, lon: '-35' }, tags }, []), null);
    assert.equal(toPlace({ type: 'way', id: 1, center: { lat: -5.8, lon: -35.2 }, tags }, []).lng, -35.2);
  });

  it('mesmo local como node e way (mesmo nome, geohash com prefixo 7 igual): fica o way', () => {
    const tags = { amenity: 'restaurant', name: 'Mangai' };
    const snap = buildSnapshot([
      { type: 'node', id: 1, lat: -5.80001, lon: -35.20001, tags: { ...tags, name: 'MANGAÍ' } },
      { type: 'way', id: 2, center: { lat: -5.80002, lon: -35.20002 }, tags },
      // Mesmo nome, longe (outra unidade): fica.
      { type: 'node', id: 3, lat: -5.88, lon: -35.17, tags },
      // Perto, nome diferente: fica.
      { type: 'node', id: 4, lat: -5.80001, lon: -35.20001, tags: { amenity: 'bar', name: 'Outro' } },
    ]);
    assert.deepEqual(snap.places.map((p) => p.id), ['osm-n3', 'osm-n4', 'osm-w2']);
  });

  it('snapshot determinístico: ordenado por id, sem duplicados, bairros fora da lista de locais', () => {
    const els = [
      { type: 'node', id: 20, lat: -5.5, lon: -35.5, tags: { amenity: 'bar', name: 'B' } },
      bairro,
      { type: 'node', id: 10, lat: -5.5, lon: -35.5, tags: { amenity: 'cafe', name: 'A' } },
      { type: 'node', id: 10, lat: -5.5, lon: -35.5, tags: { amenity: 'cafe', name: 'A' } },
    ];
    const a = buildSnapshot(els);
    const b = buildSnapshot([...els].reverse());
    assert.deepEqual(a, b);
    assert.deepEqual(a.places.map((p) => p.id), ['osm-n10', 'osm-n20']);
    assert.deepEqual(a.neighborhoods, ['Ponta Negra']);
    assert.match(a.attribution, /OpenStreetMap/);
  });
});

describe('sanidade do snapshot antes de gravar', () => {
  const snap = (places, neighborhoods) => ({
    places: Array.from({ length: places }, (_, i) => ({ id: `osm-n${i}` })),
    neighborhoods: Array.from({ length: neighborhoods }, (_, i) => `B${i}`),
  });

  it('aceita 34+ bairros e 80%+ dos locais do snapshot anterior', () => {
    assert.equal(checkSnapshot(snap(80, 34), snap(100, 38)), null);
    assert.equal(checkSnapshot(snap(500, 38), undefined), null);
  });

  it('recusa menos de 34 bairros', () => {
    assert.match(checkSnapshot(snap(600, 33), snap(600, 38)), /33 bairros/);
  });

  it('recusa menos de 80% dos locais do snapshot anterior', () => {
    assert.match(checkSnapshot(snap(79, 38), snap(100, 38)), /79 locais/);
  });

  it('recusa snapshot sem locais mesmo sem anterior', () => {
    assert.ok(checkSnapshot(snap(0, 38), undefined));
  });
});

describe('casamento com os curados', () => {
  const osmPlace = (id, name, neighborhood, extra = {}) => ({
    id,
    osmId: id.replace('osm-n', 'node/').replace('osm-w', 'way/'),
    name,
    category: 'Restaurante',
    neighborhood,
    city: 'Natal',
    lat: -5.8,
    lng: -35.2,
    geohash: 'abc',
    ...extra,
  });
  const curated = [
    { id: 'mangai-natal', name: 'Mangai', category: 'Restaurante', neighborhood: 'Tirol', city: 'Natal', photoUrl: 'https://f/m.jpg' },
    { id: 'camaroes-petropolis', name: 'Camarões', category: 'Restaurante', neighborhood: 'Petrópolis', city: 'Natal' },
    { id: 'beco-da-lama', name: 'Beco da Lama', category: 'Bar', neighborhood: 'Cidade Alta', city: 'Natal' },
  ];
  const osm = [
    osmPlace('osm-w1', 'MANGAÍ', 'Tirol', { category: 'Comida regional', cuisine: 'Comida regional', address: 'Av. Amintas Barros, 3300', openingHours: '' }),
    osmPlace('osm-n2', 'Camarões', 'Ponta Negra'),
    osmPlace('osm-n3', 'Camaroes', 'Petrópolis'),
    osmPlace('osm-n5', 'Camarões', 'Petropolis'),
    osmPlace('osm-n4', 'Bar do Zé', 'Rocas'),
  ];

  it('casamento único por nome + bairro; 2+ no mesmo bairro é ambíguo', () => {
    const { matches, ambiguous } = matchCurated(curated, osm);
    assert.deepEqual([...matches.keys()], ['mangai-natal']);
    assert.equal(matches.get('mangai-natal').id, 'osm-w1');
    assert.deepEqual(ambiguous, [{ curatedId: 'camaroes-petropolis', name: 'Camarões', osmIds: ['osm-n3', 'osm-n5'] }]);
  });

  it('bairro diferente não casa; bairro ausente em um dos lados não impede', () => {
    const c = [{ id: 'x', name: 'Camarões', neighborhood: 'Tirol' }, { id: 'y', name: 'Bar do Zé', neighborhood: '' }];
    const { matches, ambiguous } = matchCurated(c, [osmPlace('osm-n2', 'Camarões', 'Ponta Negra'), osmPlace('osm-n4', 'Bar do Zé', 'Rocas')]);
    assert.deepEqual([...matches.keys()], ['y']);
    assert.deepEqual(ambiguous, []);
    const semBairroOsm = matchCurated([{ id: 'x', name: 'Camarões', neighborhood: 'Tirol' }], [osmPlace('osm-n2', 'Camarões', '')]);
    assert.equal(semBairroOsm.matches.get('x').id, 'osm-n2');
  });

  it('nome que normaliza para vazio nunca casa', () => {
    const { matches, ambiguous } = matchCurated([{ id: 'x', name: '!!!', neighborhood: '' }], [osmPlace('osm-n1', '???', '')]);
    assert.equal(matches.size, 0);
    assert.deepEqual(ambiguous, []);
  });

  it('osmId no curado força o casamento (resolve ambíguo)', () => {
    const forced = [{ ...curated[1], osmId: 'node/5' }];
    const { matches, ambiguous } = matchCurated(forced, osm);
    assert.equal(matches.get('camaroes-petropolis').id, 'osm-n5');
    assert.deepEqual(ambiguous, []);
  });

  it('osmId forçado inexistente: loga, não casa e não grava osmId', () => {
    const logs = [];
    const forced = [{ ...curated[2], osmId: 'node/999' }];
    const { docs } = buildPlaceDocs(forced, { places: osm }, (m) => logs.push(m));
    const beco = docs.find((d) => d.id === 'beco-da-lama');
    assert.equal(beco.osmId, undefined);
    assert.equal(beco.lat, undefined);
    assert.match(logs.join('\n'), /node\/999/);
  });

  it('um local do OSM disputado por dois curados é ambíguo para ambos', () => {
    const c = [{ id: 'a', name: 'Mangai', neighborhood: 'Tirol' }, { id: 'b', name: 'Mangai', neighborhood: '' }];
    const { matches, ambiguous } = matchCurated(c, [osm[0]]);
    assert.equal(matches.size, 0);
    assert.deepEqual(ambiguous.map((a) => a.curatedId), ['a', 'b']);
  });

  it('curado mantém id, nome, categoria, bairro e foto e ganha lat/lng/osmId; duplicado do OSM não é criado', () => {
    const logs = [];
    const { docs, matched } = buildPlaceDocs(curated, { places: osm }, (m) => logs.push(m));
    const byId = Object.fromEntries(docs.map((d) => [d.id, d]));
    assert.equal(matched, 1);
    assert.equal(byId['osm-w1'], undefined);
    assert.deepEqual(byId['mangai-natal'], {
      id: 'mangai-natal',
      name: 'Mangai',
      category: 'Restaurante',
      neighborhood: 'Tirol',
      city: 'Natal',
      photoUrl: 'https://f/m.jpg',
      source: 'curated',
      osmId: 'way/1',
      lat: -5.8,
      lng: -35.2,
      geohash: 'abc',
      cuisine: 'Comida regional',
      address: 'Av. Amintas Barros, 3300',
      nameLower: 'mangai',
      searchTokens: ['ma', 'man', 'mang', 'manga', 'mangai'],
    });
    // Ambíguo: mantém o curado e os do OSM, e loga.
    assert.ok(byId['camaroes-petropolis'] && byId['osm-n2'] && byId['osm-n3'] && byId['osm-n5']);
    assert.equal(byId['camaroes-petropolis'].lat, undefined);
    assert.equal(logs.length, 1);
    assert.match(logs[0], /amb[ií]guo/);
    // Não casados entram como source 'osm', com campos de busca.
    assert.equal(byId['osm-n4'].source, 'osm');
    assert.equal(byId['osm-n4'].nameLower, 'bar do ze');
    assert.ok(byId['osm-n4'].searchTokens.includes('ze'));
    // Curado sem par no OSM segue curado e sem coordenadas.
    assert.equal(byId['beco-da-lama'].source, 'curated');
    assert.equal(byId['beco-da-lama'].lat, undefined);
  });

  it('idempotente: mesma entrada → mesmos documentos, ordenados por id', () => {
    const a = buildPlaceDocs(curated, { places: osm }).docs;
    const b = buildPlaceDocs(curated, { places: [...osm].reverse() }).docs;
    assert.deepEqual(a, b);
    const ids = a.map((d) => d.id);
    assert.deepEqual(ids, [...ids].sort());
  });

  it('sem snapshot: só os curados', () => {
    const { docs } = buildPlaceDocs(curated, undefined);
    assert.equal(docs.length, 3);
  });
});
