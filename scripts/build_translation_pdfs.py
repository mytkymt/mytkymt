#!/usr/bin/env python3
"""Build Japanese reading PDFs from the same Markdown used by Hugo.

Usage: python scripts/build_translation_pdfs.py --font /path/to/NotoSansJP.ttf --latin-font /path/to/NotoSans.ttf
Dependencies: scripts/translation-requirements.txt
Accepts a static or variable TrueType Japanese font. Never calls a translation API.
"""
from __future__ import annotations

import argparse
import html
import re
import tempfile
import unicodedata
from pathlib import Path

import markdown
import yaml
from bs4 import BeautifulSoup, NavigableString
from fontTools.ttLib import TTFont as FontToolsFont
from fontTools.varLib.instancer import instantiateVariableFont
from reportlab.lib import colors
from reportlab.lib.enums import TA_LEFT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (
    HRFlowable, Image, KeepTogether, Paragraph, SimpleDocTemplate, Spacer,
    Table, TableStyle,
)

ROOT = Path(__file__).resolve().parent.parent
WIDTH = A4[0] - 100
INK = colors.HexColor('#20252a')
BLUE = colors.HexColor('#36576c')
JP_CHARS = set()
LATIN_CHARS = set()


def escaped_text(value):
    value = unicodedata.normalize('NFC', str(value))
    parts = []
    for char in value:
        code = ord(char)
        if 0x2080 <= code <= 0x2089:
            parts.append(f'<sub>{code - 0x2080}</sub>')
        elif code in JP_CHARS or char.isspace():
            parts.append(html.escape(char))
        elif code in LATIN_CHARS:
            parts.append(f'<font name="Latin">{html.escape(char)}</font>')
        else:
            raise ValueError(f'No font glyph for U+{code:04X}: {char!r}')
    return ''.join(parts)


def inline(node):
    if isinstance(node, NavigableString):
        return escaped_text(node)
    body = ''.join(inline(child) for child in node.children)
    if node.name in ('strong', 'b'):
        return f'<b>{body}</b>'
    if node.name in ('em', 'i'):
        return body  # Japanese face has no italic; preserve readable glyphs.
    if node.name in ('sup', 'sub'):
        return f'<{node.name}>{body}</{node.name}>'
    if node.name == 'br':
        return '<br/>'
    if node.name == 'a' and node.get('href', '').startswith(('https://', 'http://')):
        return f'<a href="{html.escape(node["href"], quote=True)}" color="#36576c">{body}</a>'
    return body


def build(bundle, styles):
    raw = (bundle / 'index.md').read_text()
    _, front, body = raw.split('---', 2)
    meta = yaml.safe_load(front)
    soup = BeautifulSoup(markdown.markdown(body, extensions=['tables', 'fenced_code']), 'html.parser')
    target = bundle / 'translation-ja.pdf'
    doc = SimpleDocTemplate(str(target), pagesize=A4, rightMargin=50, leftMargin=50,
                            topMargin=48, bottomMargin=48, title=meta['title'],
                            author='AI translation of ' + ' / '.join(meta['original_authors']),
                            subject='AIで自動翻訳・整形した日本語参考資料', pageCompression=1)
    story = [Paragraph('論文の日本語版 · AI自動翻訳', styles['meta']), Spacer(1, 10),
             Paragraph(html.escape(meta['title']), styles['title']),
             Paragraph(html.escape(meta['original_title']), styles['meta']),
             Spacer(1, 8), Paragraph('原著：' + html.escape(' / '.join(meta['original_authors'])), styles['meta']),
             Paragraph(html.escape(f"{meta['original_publication']} · {meta['original_year']}"), styles['meta']),
             Paragraph('日本語版の作成日：' + str(meta['date']), styles['meta']), Spacer(1, 14)]
    notice = [Paragraph('<b>この日本語版について</b>', styles['body']),
              Paragraph(html.escape(meta['translation_notice']), styles['body'])]
    box = Table([[notice]], colWidths=[WIDTH])
    box.setStyle(TableStyle([('BACKGROUND',(0,0),(-1,-1),colors.HexColor('#f1f5f7')),
                            ('BOX',(0,0),(-1,-1),.5,colors.HexColor('#dce2e7')),
                            ('LEFTPADDING',(0,0),(-1,-1),12),('RIGHTPADDING',(0,0),(-1,-1),12),
                            ('TOPPADDING',(0,0),(-1,-1),10),('BOTTOMPADDING',(0,0),(-1,-1),8)]))
    story += [box, Spacer(1, 12)]
    doi = 'https://doi.org/' + meta['original_doi']
    story += [Paragraph(f'<a href="{doi}" color="#36576c">正式版を確認する：{doi}</a>', styles['meta'])]
    if meta.get('source_url'):
        url = html.escape(meta['source_url'], quote=True)
        story += [Paragraph(f'<a href="{url}" color="#36576c">翻訳元を確認する：{url}</a>', styles['meta'])]
    story += [Spacer(1, 15), HRFlowable(width='100%', color=colors.HexColor('#dce2e7')), Spacer(1, 8)]

    def append_elements(parent, reference=False):
        nonlocal story
        for el in parent.children:
            if isinstance(el, NavigableString):
                continue
            if el.name in ('h2', 'h3', 'h4'):
                story.append(Paragraph(inline(el), styles[el.name]))
            elif el.name == 'p':
                style = 'ref' if reference else ('tablecaption' if re.match(r'^表[0-9]', el.get_text()) else 'body')
                story.append(Paragraph(inline(el), styles[style]))
            elif el.name in ('ul', 'ol'):
                for i, li in enumerate(el.find_all('li', recursive=False), 1):
                    prefix = f'{i}. ' if el.name == 'ol' else '• '
                    story.append(Paragraph(prefix + inline(li), styles['body']))
            elif el.name == 'figure':
                img = el.find('img')
                figure = Image(str(bundle / img['src']))
                factor = min(WIDTH / figure.imageWidth, 330 / figure.imageHeight, 1)
                figure.drawWidth = figure.imageWidth * factor
                figure.drawHeight = figure.imageHeight * factor
                cap = el.find('figcaption')
                parts = [Spacer(1, 10), figure]
                if cap:
                    parts += [Spacer(1, 6), Paragraph(inline(cap), styles['caption'])]
                parts.append(Spacer(1, 10))
                story.append(KeepTogether(parts))
            elif el.name == 'table':
                rows = [[Paragraph(inline(cell), styles['table']) for cell in row.find_all(['th','td'])]
                        for row in el.find_all('tr')]
                table = Table(rows, colWidths=[WIDTH / len(rows[0])] * len(rows[0]), repeatRows=1, hAlign='LEFT')
                table.setStyle(TableStyle([('BACKGROUND',(0,0),(-1,0),colors.HexColor('#eef2f5')),
                                          ('GRID',(0,0),(-1,-1),.4,colors.HexColor('#dce2e7')),
                                          ('VALIGN',(0,0),(-1,-1),'TOP'),
                                          ('TOPPADDING',(0,0),(-1,-1),6),('BOTTOMPADDING',(0,0),(-1,-1),6)]))
                story += [Spacer(1, 8), KeepTogether([table]), Spacer(1, 10)]
            elif el.name in ('div', 'section', 'blockquote'):
                append_elements(el, reference or 'references' in el.get('class', []))
            elif el.name == 'hr':
                story.append(HRFlowable(width='100%', color=colors.HexColor('#dce2e7')))
            else:
                raise ValueError(f'Unsupported top-level element: {el.name} in {bundle}')

    append_elements(soup)

    def furniture(canvas, document):
        canvas.saveState()
        canvas.setFont('JP', 7.5)
        canvas.setFillColor(colors.HexColor('#596670'))
        canvas.drawString(50, A4[1] - 28, meta.get('short_title', meta['title'][:35]) + ' | AI自動翻訳')
        canvas.drawString(50, 27, '内容の詳細は正式版をご確認ください。')
        canvas.drawRightString(A4[0] - 50, 27, str(document.page))
        canvas.restoreState()

    doc.build(story, onFirstPage=furniture, onLaterPages=furniture)
    print(target)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--font', required=True, type=Path)
    parser.add_argument('--latin-font', required=True, type=Path, help='Noto Sans TTF for extended Latin names')
    parser.add_argument('--slug', help='Build one translation only')
    args = parser.parse_args()
    global JP_CHARS, LATIN_CHARS
    JP_CHARS = set(FontToolsFont(args.font).getBestCmap())
    LATIN_CHARS = set(FontToolsFont(args.latin_font).getBestCmap())
    with tempfile.TemporaryDirectory(prefix='translation-fonts-') as tmp:
        for name, weight in [('JP', 400), ('JP-Bold', 700)]:
            face = FontToolsFont(args.font)
            if 'fvar' in face:
                face = instantiateVariableFont(face, {'wght': weight}, inplace=True)
            output = Path(tmp) / (name + '.ttf')
            face.save(output)
            pdfmetrics.registerFont(TTFont(name, str(output)))
        face = FontToolsFont(args.latin_font)
        if 'fvar' in face:
            axes = {axis.axisTag: axis.defaultValue for axis in face['fvar'].axes}
            face = instantiateVariableFont(face, axes, inplace=True)
        latin = Path(tmp) / 'Latin.ttf'
        face.save(latin)
        pdfmetrics.registerFont(TTFont('Latin', str(latin)))
        pdfmetrics.registerFontFamily('JP', normal='JP', bold='JP-Bold', italic='JP', boldItalic='JP-Bold')
        base = dict(fontName='JP', fontSize=9.5, leading=17, textColor=INK, wordWrap='CJK',
                    spaceAfter=7, alignment=TA_LEFT, splitLongWords=True)
        styles = {'body': ParagraphStyle('body', **base)}
        for name, changes in {
            'title': dict(fontName='JP-Bold', fontSize=19, leading=28, spaceAfter=10),
            'meta': dict(fontSize=8, leading=13, textColor=colors.HexColor('#53616b'), spaceAfter=4),
            'h2': dict(fontName='JP-Bold',fontSize=14, leading=21, spaceBefore=20, spaceAfter=10, keepWithNext=True),
            'h3': dict(fontName='JP-Bold',fontSize=11.5, leading=18, spaceBefore=14, spaceAfter=7, keepWithNext=True),
            'h4': dict(fontName='JP-Bold',fontSize=10, leading=17, spaceBefore=10, keepWithNext=True),
            'caption': dict(fontSize=8, leading=13, textColor=colors.HexColor('#45535e')),
            'tablecaption': dict(keepWithNext=True),
            'table': dict(fontSize=7.5, leading=12, spaceAfter=0),
            'ref': dict(fontSize=7.5, leading=11, spaceAfter=6),
        }.items():
            styles[name] = ParagraphStyle(name, **(base | changes))
        for path in sorted((ROOT / 'content/jp/translations').glob('*/index.md')):
            if args.slug and path.parent.name != args.slug:
                continue
            build(path.parent, styles)


if __name__ == '__main__':
    main()
