# Créditos dos dados e das fotos dos locais (seed)

## Dados dos locais: OpenStreetMap

O catálogo de locais de comer/beber de Natal (`osm-natal.json`: nome, categoria, cozinha,
endereço, horário, coordenadas) e os polígonos dos 38 bairros usados para calcular o bairro
vêm do **OpenStreetMap**: © [colaboradores do OpenStreetMap](https://www.openstreetmap.org/copyright),
disponíveis sob a [Open Database License (ODbL) 1.0](https://opendatacommons.org/licenses/odbl/).

- Obtidos pela [Overpass API](https://overpass-api.de/) com `npm run import:osm`
  (`importar-osm.js`); o snapshot versionado é um banco de dados derivado e segue a ODbL.
- O app mostra "© colaboradores do OpenStreetMap" no seletor de locais e no detalhe dos
  locais com dados do OSM.
- Os 20 locais curados de `places.json` mantêm o id; quando casam (nome normalizado + bairro
  compatível, casamento único, ou `osmId` explícito no curado) com um local do OSM, recebem
  dele coordenadas, `osmId`, cozinha, endereço e horário.

## Fotos dos locais

As fotos de capa em `places.json` (`photoUrl`) são miniaturas de 1280 px servidas pelo
Wikimedia Commons (`upload.wikimedia.org`, com CORS liberado para a web), usadas por URL (sem cópia no repositório nem no
Firebase Storage). Todas têm licença livre que permite reuso, inclusive comercial.

Não há fotos oficiais dos estabelecimentos com licença livre para a maioria dos locais; nesses
casos a capa é uma foto do **bairro** do local ou de um **prato típico de Natal**, e está
marcada como tal na coluna "O que mostra" e com `photoIllustrative: true` no seed (o app mostra o
selo "ilustrativa" e o leitor de tela anuncia "Imagem ilustrativa"). O app também exibe
"Foto: autor · licença" no detalhe do local (`photoAuthor`, `photoLicense`). Conferido em 2026-09-28: todas as URLs respondem 200.

Licenças CC BY / CC BY-SA exigem atribuição: esta tabela é essa atribuição (autor, licença e
link para a página do arquivo). CC0 não exige, mas o crédito é mantido por cortesia.

| Local (id) | O que mostra | Arquivo no Commons | Autor | Licença |
|---|---|---|---|---|
| Camarões Potiguar (`camaroes-potiguar-ponta-negra`) | Prato típico de Natal (camarão, ginga com tapioca) | [Camarão com limão, pastel, ovo de codorna e ginga com tapioca.jpg](https://commons.wikimedia.org/wiki/File:Camar%C3%A3o_com_lim%C3%A3o,_pastel,_ovo_de_codorna_e_ginga_com_tapioca.jpg) | Sashopotiguar | [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0) |
| Camarões (`camaroes-petropolis`) | Bairro Petrópolis | [Bairro Petrópolis - Natal-RN.jpg](https://commons.wikimedia.org/wiki/File:Bairro_Petr%C3%B3polis_-_Natal-RN.jpg) | Beraldo Leal | [CC BY 2.0](https://creativecommons.org/licenses/by/2.0) |
| Mangai (`mangai-natal`) | Rua Alberto Maranhão (limite Tirol/Barro Vermelho) | [Rua Alberto Maranhão, Natal (RN).jpg](https://commons.wikimedia.org/wiki/File:Rua_Alberto_Maranh%C3%A3o,_Natal_(RN).jpg) | Marcos Elias de Oliveira Júnior | [CC0](https://creativecommons.org/publicdomain/zero/1.0/deed.en) |
| Tábua de Carne (`tabua-de-carne-ponta-negra`) | Praia de Ponta Negra | [Natal RN Brasil - Ponta Negra.jpg](https://commons.wikimedia.org/wiki/File:Natal_RN_Brasil_-_Ponta_Negra.jpg) | Beraldo Leal | [CC BY 2.0](https://creativecommons.org/licenses/by/2.0) |
| Farofa d'Água (`farofa-dagua-ponta-negra`) | Ponta Negra e Morro do Careca | [Vista do Morro do Careca em Ponta Negra pela manhã.jpg](https://commons.wikimedia.org/wiki/File:Vista_do_Morro_do_Careca_em_Ponta_Negra_pela_manh%C3%A3.jpg) | Ppulbatu | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0) |
| Casa de Taipa (`casa-de-taipa-ponta-negra`) | Morro do Careca (Ponta Negra) | [Morro do Careca - Natal.jpg](https://commons.wikimedia.org/wiki/File:Morro_do_Careca_-_Natal.jpg) | Robertomarcio | [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0) |
| Paçoca de Pilão (`pacoca-de-pilao`) | Praia de Ponta Negra | [Praia de Ponta Negra - Natal.jpg](https://commons.wikimedia.org/wiki/File:Praia_de_Ponta_Negra_-_Natal.jpg) | Beto Quissak | [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0) |
| Coco Bambu (`coco-bambu-natal`) | Praia de Ponta Negra | [Ponta Negra Beach, Natal, Brazil.jpg](https://commons.wikimedia.org/wiki/File:Ponta_Negra_Beach,_Natal,_Brazil.jpg) | CivArmy | [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0) |
| Sal e Brasa (`sal-e-brasa-natal`) | Av. Prudente de Morais, Lagoa Nova | [Trecho da Avenida Prudente de Morais, Lagoa Nova, Natal (RN).jpg](https://commons.wikimedia.org/wiki/File:Trecho_da_Avenida_Prudente_de_Morais,_Lagoa_Nova,_Natal_(RN).jpg) | Marcos Elias de Oliveira Júnior | [CC0](https://creativecommons.org/publicdomain/zero/1.0/deed.en) |
| Outback Steakhouse (Midway Mall) (`outback-midway`) | Cinemark do Midway Mall (o próprio shopping) | [Cinemark Natal 03.jpg](https://commons.wikimedia.org/wiki/File:Cinemark_Natal_03.jpg) | Amancio do Compromisso | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0) |
| Mercado de Petrópolis (`mercado-de-petropolis`) | Praça Pedro Velho (Praça Cívica), Petrópolis | [Praça Cívica Natal RN.jpg](https://commons.wikimedia.org/wiki/File:Pra%C3%A7a_C%C3%ADvica_Natal_RN.jpg) | R. Lucena | [CC BY 2.0](https://creativecommons.org/licenses/by/2.0) |
| Mercado da Redinha (`mercado-da-redinha`) | Ginga com tapioca, prato típico do Mercado da Redinha | [Ginga com tapioca.jpg](https://commons.wikimedia.org/wiki/File:Ginga_com_tapioca.jpg) | Peddrodaniel | [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0) |
| Buraco da Catita (`buraco-da-catita`) | Rua Ulisses Caldas, Cidade Alta | [Rua Ulisses Caldas, Natal (RN).jpg](https://commons.wikimedia.org/wiki/File:Rua_Ulisses_Caldas,_Natal_(RN).jpg) | Marcos Elias de Oliveira Júnior | [CC0](https://creativecommons.org/publicdomain/zero/1.0/deed.en) |
| Beco da Lama (`beco-da-lama`) | Bairro da Cidade Alta | [Cidade Alta.jpg](https://commons.wikimedia.org/wiki/File:Cidade_Alta.jpg) | - mariNa | [CC BY 2.0](https://creativecommons.org/licenses/by/2.0) |
| Chaplin (`chaplin-ponta-negra`) | Ponta Negra | [Ponta Negra, Natal (20150814-DSC05647).jpg](https://commons.wikimedia.org/wiki/File:Ponta_Negra,_Natal_(20150814-DSC05647).jpg) | Matti Blume | [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0) |
| Taverna Pub (`taverna-pub-ponta-negra`) | Morro do Careca (Ponta Negra) | [Morro do Careca2.jpg](https://commons.wikimedia.org/wiki/File:Morro_do_Careca2.jpg) | Luiz Antonio Mendes | [CC BY-SA 2.0](https://creativecommons.org/licenses/by-sa/2.0) |
| Cervejaria Ponta Negra (`cervejaria-ponta-negra`) | Praia de Ponta Negra com o Morro do Careca | [Praia da Ponta Negra 20150814-DSC05653.JPG](https://commons.wikimedia.org/wiki/File:Praia_da_Ponta_Negra_20150814-DSC05653.JPG) | Matti Blume | [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0) |
| Centro de Turismo (`centro-de-turismo-natal`) | O próprio Centro de Turismo | [Centro de Turismo, Natal (RN).jpg](https://commons.wikimedia.org/wiki/File:Centro_de_Turismo,_Natal_(RN).jpg) | Marcos Elias de Oliveira Júnior | [CC0](https://creativecommons.org/publicdomain/zero/1.0/deed.en) |
| Feirinha de Artesanato de Ponta Negra (`feirinha-ponta-negra`) | Praia de Ponta Negra | [Foto diagonal da Praia de Ponta Negra.jpg](https://commons.wikimedia.org/wiki/File:Foto_diagonal_da_Praia_de_Ponta_Negra.jpg) | Ppulbatu | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0) |
| Praia Shopping (Praça de alimentação) (`praia-shopping-natal`) | Cinema do Praia Shopping (o próprio shopping) | [Moviecom Praia Shopping 03.jpg](https://commons.wikimedia.org/wiki/File:Moviecom_Praia_Shopping_03.jpg) | Amancio do Compromisso | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0) |

## Como trocar uma foto

1. Escolha um arquivo no Wikimedia Commons com licença CC0, domínio público, CC BY ou CC BY-SA.
2. Use a miniatura de 1280 px (campo `thumburl` da API do Commons com `iiurlwidth=1280`, sem os parâmetros `utm_*`) —
   larguras-padrão do Commons (960, 1280) evitam erro de miniatura não gerada.
3. Confira que a URL responde 200, atualize `places.json` e esta tabela, e rode o seed de novo.
