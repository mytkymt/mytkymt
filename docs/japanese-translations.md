# Japanese reading editions

Five project-level reading editions were prepared on 2026-09-16. Each HTML page and PDF uses the same Markdown source under `content/jp/translations/<slug>/index.md`.

| Project | Selected source | Earlier work covered by this edition |
| --- | --- | --- |
| TastePrint | arXiv:2603.22887v2, 15 April 2026 | — |
| ChewTect | Author manuscript of the DIS 2026 full paper | UIST 2025 texture/molding poster |
| EateryTag | Author submission manuscript | interiqr UIST 2022 and the SIGGRAPH Asia 2024 poster |
| HaptoMapping | Author-supplied TVCG preprint | EuroHaptics 2020 and SIGGRAPH Asia 2020 |
| Conductive gels / OleoCircuit | Author-supplied UIST 2025 poster manuscript | — |

`japanese-translation-sources.json` records the selected PDF hashes and official DOIs. Source PDFs remain in the author's source collection. The hashes identify the exact versions used. Publication dates in the portfolio refer to the official publications; the translation date is separate.

## Editorial policy

The Japanese prose conventions are maintained in [japanese-style.md](japanese-style.md).

- These are AI-generated translations and formatting of preprint/author manuscripts. They carry the original authors' names as original authors only.
- The visible notice identifies the automated translation and directs readers to the official version for details.
- Keep sentences short. Establish clear modifier relationships through word order and sentence division. Add Japanese commas only where needed to separate clauses. Avoid automatic commas after connectors such as また.
- Translate the body and captions. Preserve original figures, figure labels, citation markers, and bibliographic titles.
- Preserve reported numerical values. Mark source inconsistencies as translation notes rather than silently resolving them.
- HaptoMapping has inconsistent maximum latency values (abstract: 93.4 ms; body/table: 96.3 ms), static-mode data lengths (introduction: 24 bit; implementation: 32 bit), and significance wording for continuity at 80 mm/s (reported p=.074). These are flagged in the reading edition.
- EateryTag has conflicting covering-layer thicknesses in the text and Figure 7 caption. Both are recorded.
- TastePrint's equation and prose differ on square root versus squared transformations. The equation is retained and the discrepancy is marked.
- Conductive gels reports “resistance” in Ω·cm. The source label and unit are made explicit.

## Rebuild PDFs

Install Python dependencies from `scripts/translation-requirements.txt`. Supply the Noto Sans JP and Noto Sans TrueType fonts (static or variable). Noto Sans provides extended Latin glyphs for bibliographic names. The font is available under the SIL Open Font License from [Google Fonts](https://github.com/google/fonts/tree/main/ofl/notosansjp).

```sh
python -m pip install -r scripts/translation-requirements.txt
python scripts/build_translation_pdfs.py --font /path/to/NotoSansJP.ttf --latin-font /path/to/NotoSans.ttf
# Optional: --slug tasteprint
hugo
```

Generated `translation-ja.pdf` files are checked in as page resources. Hosting only requires the existing Hugo build. Python and the font are needed when regenerating PDFs after a text or figure edit. Render and visually inspect changed PDFs before publishing them.

The dedicated layouts are in `layouts/translations/`. A publication's `japanese_translation` field enables a link in both language versions. One representative publication per project carries that link.

## Related metadata correction

The two UIST 2025 poster DOI values were swapped in the portfolio. The conductive-gel poster uses `10.1145/3746058.3758423`. The texture/molding poster uses `10.1145/3746058.3758407`. The supplied conductive-gel manuscript and [Saitama University's researcher record](https://rdb.eva.saitama-u.ac.jp/search/detail.html?lang=en&systemId=a166407bdf319c38520e17560c007669) confirm this mapping. Existing directory names were retained to preserve URLs.

## Validation

- Hugo 0.147.6 builds both language sites.
- All five selected publications link to their Japanese editions from both homepages.
- All 58 figures render. Each article links to its generated PDF and official DOI.
- Desktop (1440 px) and mobile (390 px) checks show no page-level horizontal overflow.
- Reference counts match the selected sources: TastePrint 29; ChewTect 74; EateryTag 51; HaptoMapping 62; conductive gels 6.
- PDFs were rendered and visually inspected for figure cropping, layout, tables, equations, and Japanese glyphs.
