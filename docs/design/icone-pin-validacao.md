# Novo ícone NaÁrea

Referência da usuária: `codex-clipboard-12f73f84-2908-48e1-a5e0-c504391cf952.png`.

Arte preparada com a ferramenta integrada image_gen, a partir da referência fornecida. Grade e moldura da captura foram retiradas. O sistema operacional aplica o recorte externo ao ícone quadrado; Android recebe camada adaptativa transparente e fundo creme `#FDF6E6`.

Arquivos definitivos no projeto:

- `app/assets/icon/naarea-pin.png` — arte principal.
- `app/assets/icon/naarea-pin-foreground.png` — camada transparente adaptativa.
- `app/assets/icon/stitch-source.png` — referência interna do app atualizada.
- Android: mipmaps, camadas adaptativas e cor de fundo em `app/android/app/src/main/res`.
- iOS: `app/ios/Runner/Assets.xcassets/AppIcon.appiconset`.
- Web: favicon, ícones e manifesto em `app/web`.

Regeneração: `dart run flutter_launcher_icons`, a partir de `app`. A configuração utiliza os arquivos novos; o gerador antigo de pôr do sol não os sobrescreve.

Prompt da arte principal:

> Prepare this exact user-supplied NaÁrea app icon for production launcher assets, faithfully preserving its design. Remove ONLY the surrounding dark grid, purple screenshot border and rounded-square clipping. Output a clean full-bleed square 1024px icon with the same solid cream background extended to every edge, no rounded outer corners and no external frame. Preserve the exact centered dark forest-green outlined teardrop map pin, terracotta filled circular center, and terracotta downward chevron underneath the pin. Keep original proportions, stroke thickness, spacing, colors and crisp flat vector-like edges; no text, no shadows, no gradients, no other elements. The phone OS will apply its own corner mask. Do not redesign or stylize the mark.

Prompt da camada adaptativa:

> Create the Android adaptive foreground layer of this exact approved logo. Remove the cream background completely, preserving only the forest-green outlined map pin, the terracotta circular center and terracotta downward chevron. Preserve their existing geometry, colors, positions and proportions. Square canvas with genuine transparent alpha, symbol centered and its total bounding height 60% of canvas (safe adaptive launcher margins). Crisp flat clean logo edges, no shadows, no text, no extra marks. Do not include a cream field anywhere, including inside the outlined pin: the interior must also be transparent except the terracotta disk.

Ícones de lançamento gerados com flutter_launcher_icons 0.14.4, com sucesso. O ícone aparece no dispositivo ao instalar a próxima versão do aplicativo; nenhum novo APK foi gerado nesta etapa de validação visual.
