# Procedência dos ativos de mídia

O vídeo do sponsor pode ser anexado a edital público, então toda faixa usada
precisa ter licença rastreável registrada aqui.

## Faixa musical

| Campo | Valor |
|---|---|
| Arquivo | `holiznacc0-cosmic-waves.mp3` (gitignored — rebaixe pelo link abaixo) |
| Título | Cosmic Waves |
| Artista | HoliznaCC0 |
| Licença | **CC0 1.0 Universal** (dedicação ao domínio público) |
| Texto da licença | <https://creativecommons.org/publicdomain/zero/1.0/> |
| Fonte | <https://archive.org/details/holizna-cc-0-cosmic-waves> |
| Verificado em | 2026-09-10, via campo `licenseurl` da API de metadados do Internet Archive |
| Duração original | 33 min 04 s |

**CC0 não exige atribuição** — o crédito acima é para rastreabilidade interna e
prestação de contas, não obrigação legal.

Uso no vídeo: leito musical de 0:20 a 2:45 (blocos 2 a 6), a partir do minuto
3:00 da faixa, normalizado a −22 LUFS, com fade de 2 s na entrada e 4 s na
saída. Os blocos 1 e 7 ficam em **silêncio deliberado**, conforme
`docs/roteiro-video-sponsor.md`.

Para rebaixar:

```bash
curl -L -o video/assets/holiznacc0-cosmic-waves.mp3 \
  "https://archive.org/download/holizna-cc-0-cosmic-waves/HoliznaCC0%20-%20Cosmic%20Waves.mp3"
```

### Fontes descartadas, e por quê

- **Pixabay** — aparece em toda lista de "música CC0", mas **não é CC0**: usa
  licença própria, com restrições. Inadequado para anexo de edital.
- **Free Music Archive** — tem CC0 legítimo do mesmo artista (álbum
  *Background Music*, piano e caixinha de música), mas o download exige login,
  então não dá para automatizar. Continua sendo boa opção manual.

## Capturas de tela e filmagem

Geradas pelos scripts em `video/capture/` a partir dos apps Flutter deste
repositório, com **dados exclusivamente sintéticos** (Maria Oliveira, João
Pereira, Ana Costa). Nenhum dado real de paciente, conforme a invariante de
privacidade do projeto.
