#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
阿德勒全集书籍转换合并脚本 (带总目录，修补扫描版)
"""

import os
import sys
import subprocess
import re

PANDOC = r'D:\soft6\pandoc\pandoc.exe'
OUTPUT_DIR = r'opt/Adler'
OUTPUT_FILE = os.path.join(OUTPUT_DIR, '阿德勒全集.md')
TEMP_DIR = os.path.join(OUTPUT_DIR, '_temp')

# 每本书: (源文件, 显示书名, 起始锚点, 结束锚点)
# "理解人性"扫描版PDF用"洞察人性"(set2锚点index_split_001)内容替换
BOOKS = [
    # ===== 套装1：阿德勒积极心理学(4册) =====
    (r'opt/阿德勒/2、洞察人性/阿德勒积极心理学(套装共4册) (阿德勒)(超越自卑+洞察人性+理解生命+性格的塑造).epub',
     '《超越自卑》', 'text00002.html', 'text00019.html'),
    (r'opt/阿德勒/2、洞察人性/阿德勒积极心理学(套装共4册) (阿德勒)(超越自卑+洞察人性+理解生命+性格的塑造).epub',
     '《洞察人性》', 'text00019.html', 'text00045.html'),
    (r'opt/阿德勒/2、洞察人性/阿德勒积极心理学(套装共4册) (阿德勒)(超越自卑+洞察人性+理解生命+性格的塑造).epub',
     '《理解生命》', 'text00045.html', 'text00135.html'),
    (r'opt/阿德勒/2、洞察人性/阿德勒积极心理学(套装共4册) (阿德勒)(超越自卑+洞察人性+理解生命+性格的塑造).epub',
     '《性格的塑造》', 'text00135.html', None),

    # ===== 套装2：阿德勒心理学经典(4册) =====
    (r'opt/阿德勒/2、洞察人性/阿德勒心理学经典(套装共4册)-、洞察人性超越自卑、生活的科学、儿童人格形成及培养/阿德勒心理学经典(套装共4册).epub',
     '《生活的科学》', 'index_split_024.html', 'index_split_040.html'),
    (r'opt/阿德勒/2、洞察人性/阿德勒心理学经典(套装共4册)-、洞察人性超越自卑、生活的科学、儿童人格形成及培养/阿德勒心理学经典(套装共4册).epub',
     '《儿童人格形成及培养》', 'index_split_040.html', None),

    # ===== 单书 =====
    (r'opt/阿德勒/2、阿德勒的生命重建课/阿德勒的生命重建课.epub',
     '《阿德勒的生命重建课》', None, None),
    # 理解人性 (扫描PDF) → 用套装2"洞察人性"(index_split_001)替换
    (r'opt/阿德勒/2、洞察人性/阿德勒心理学经典(套装共4册)-、洞察人性超越自卑、生活的科学、儿童人格形成及培养/阿德勒心理学经典(套装共4册).epub',
     '《理解人性》', 'index_split_001.html', 'index_split_008.html'),
    (r'opt/阿德勒/7、走出孤独：阿德勒孤独十五讲/走出孤独：阿德勒孤独十五讲.epub',
     '《走出孤独：阿德勒孤独十五讲》', None, None),
    (r'opt/阿德勒/8、阿德勒的情绪整理术/阿德勒的情绪整理术.epub',
     '《阿德勒的情绪整理术》', None, None),
    (r'opt/阿德勒/10、阿德勒心理学实践手册/2023-01《阿德勒心理学实践手册》.pdf',
     '《阿德勒心理学实践手册》', None, None),
    (r'opt/阿德勒/11、阿德勒的生活法则/2023-01《阿德勒的生活法则》.epub',
     '《阿德勒的生活法则》', None, None),
    (r'opt/阿德勒/12、阿德勒疗法/阿德勒疗法.txt',
     '《阿德勒疗法》', None, None),
    ('opt/阿德勒/13、被讨厌的勇气：\u201c自我启发之父\u201d阿德勒的哲学课PDF/被讨厌的勇气：\u201c自我启发之父\u201d阿德勒的哲学课.epub',
     '《被讨厌的勇气：「自我启发之父」阿德勒的哲学课》', None, None),
]


def pandoc_to_md(epub_path: str, out_md: str) -> bool:
    try:
        with open(out_md, 'w', encoding='utf-8') as f:
            result = subprocess.run(
                [PANDOC, '-f', 'epub', '-t', 'markdown_strict+pipe_tables',
                 epub_path, '--wrap=none'],
                stdout=f, stderr=subprocess.PIPE, timeout=300,
            )
        if result.returncode != 0:
            return False
        return os.path.getsize(out_md) > 100
    except Exception:
        return False


def clean(text: str) -> str:
    """清理HTML，保留章节标题结构。将 span/div 中的标题文本转换为 # 标记"""
    # 1. 保留锚点标记用于日志，但后续移除
    # 2. 将 <span class="bold">标题</span> 类型的行转换为 ## 标题
    # 3. 将 <span class="calibre_2">标题</span> 或类似结构转换为 # 或 ##
    # 先做转换：将突出的span标题行转为markdown标题
    text = re.sub(r'<span[^>]*>\s*<span[^>]*>\s*(.{1,80}?)\s*</span>\s*</span>', r'## \1', text)
    text = re.sub(r'<span[^>]*>\s*(.{1,80}?)\s*</span>', r' \1 ', text)
    text = re.sub(r'<div[^>]*>', '', text)
    text = re.sub(r'</div>', '', text)
    text = re.sub(r'<p[^>]*>', '', text)
    text = re.sub(r'</p>', '', text)
    text = re.sub(r'<\?xml[^>]*\?>', '', text)
    text = re.sub(r'<svg[^>]*>.*?</svg>', '', text, flags=re.DOTALL)
    text = re.sub(r'<image[^>]*/>', '', text)
    text = re.sub(r'<img[^>]*/>', '', text)
    text = re.sub(r'<img[^>]*>', '', text)
    # 移除所有剩余HTML标签
    text = re.sub(r'<[^>]+>', '', text)
    # 图片引用
    text = re.sub(r'!\[\]\([^)]+\)', '', text)
    # 清理多余空行
    text = re.sub(r'\n{4,}', '\n\n\n', text)
    return text.strip()


def find_anchor_positions(text: str):
    positions = []
    for m in re.finditer(r'\[\]\{#([^}]+)\}', text):
        positions.append((m.start(), m.group(1)))
    for m in re.finditer(r'<span\s+id="([^"]+)"\s*>\s*</span>', text):
        positions.append((m.start(), m.group(1)))
    positions.sort(key=lambda x: x[0])
    return positions


def extract_section(text: str, start_id: str, end_id: str = None):
    positions = find_anchor_positions(text)
    if not positions:
        return f'\n\n> 错误: 未找到任何锚点标记\n\n'
    start_pos = None
    end_pos = None
    for pos, aid in positions:
        if aid == start_id:
            start_pos = pos
        if end_id and aid == end_id:
            end_pos = pos
            if start_pos is not None:
                break
    if start_pos is None:
        sample = '\n'.join([f'    {aid}' for _, aid in positions[:15]])
        return f'\n\n> 错误: 未找到锚点 [{start_id}] | 可用锚点({len(positions)}个):\n{sample}\n\n'
    segment = text[start_pos:end_pos] if end_pos else text[start_pos:]
    return clean(segment)


def read_pdf(filepath: str) -> str:
    try:
        from pypdf import PdfReader
        reader = PdfReader(filepath)
        pages = []
        for page in reader.pages:
            t = page.extract_text()
            if t and t.strip():
                pages.append(t.strip())
        return '\n\n'.join(pages)
    except Exception as e:
        return f'\n\n> 错误: PDF处理失败: {e}\n\n'


def read_txt(filepath: str) -> str:
    for enc in ['utf-8', 'gbk', 'gb2312', 'utf-16']:
        try:
            with open(filepath, 'r', encoding=enc) as f:
                return f.read()
        except Exception:
            continue
    return '\n\n> 错误: 无法解码\n\n'


def main():
    os.makedirs(TEMP_DIR, exist_ok=True)

    # ========== 第一步：生成所有书的(raw_title, content)对 ==========
    book_contents = []  # [(raw_title, content)]
    source_cache = {}
    total = len(BOOKS)

    for i, (filepath, book_name, start_id, end_id) in enumerate(BOOKS, 1):
        if not os.path.exists(filepath):
            print(f'[{i}/{total}] 不存在: {filepath}')
            book_contents.append((book_name, f'\n\n> 源文件不存在\n\n'))
            continue

        ext = os.path.splitext(filepath)[1].lower()

        if ext not in ('.epub',) or start_id is None:
            # 单书
            print(f'[{i}/{total}] {book_name}')
            if ext == '.pdf':
                content = read_pdf(filepath)
            elif ext == '.txt':
                content = read_txt(filepath)
            elif ext == '.epub':
                tmp = os.path.join(TEMP_DIR, f'single_{i}.md')
                ok = pandoc_to_md(filepath, tmp)
                content = clean(open(tmp, 'r', encoding='utf-8').read()) if ok else '\n\n> 转换失败\n\n'
            else:
                content = ''
            book_contents.append((book_name, content))
            continue

        # 套装
        if filepath not in source_cache:
            tmp = os.path.join(TEMP_DIR, f'set_{i}.md')
            ok = pandoc_to_md(filepath, tmp)
            source_cache[filepath] = ('ok' if ok else 'err', tmp if ok else None)

        status, tmp = source_cache[filepath]
        if status == 'err':
            print(f'[{i}/{total}] {book_name} - 源文件错误')
            book_contents.append((book_name, '\n\n> 源文件转换错误\n\n'))
            continue

        print(f'[{i}/{total}] {book_name} [{start_id}->{end_id or "END"}]')
        raw = open(tmp, 'r', encoding='utf-8').read()
        content = extract_section(raw, start_id, end_id)
        book_contents.append((book_name, content))

    # ========== 第二步：生成总目录标题 ==========
    toc_lines = []
    toc_lines.append('# 阿德勒全集\n')
    toc_lines.append(f'\n> 共收录 {len(book_contents)} 部阿德勒著作 | 自动合并生成\n')
    toc_lines.append('\n---\n')
    toc_lines.append('\n## 目录\n')
    toc_lines.append('\n| 序号 | 书名 |\n| --- | --- |\n')
    for idx, (name, _) in enumerate(book_contents, 1):
        anchor_id = f'book-{idx}'
        toc_lines.append(f'| {idx} | [{name}](#{anchor_id}) |\n')
    toc_lines.append('\n---\n')

    # ========== 第三步：写入内容（每本书前面加锚点链接） ==========
    with open(OUTPUT_FILE, 'w', encoding='utf-8', newline='\n') as f:
        f.write(''.join(toc_lines))

        for idx, (book_name, content) in enumerate(book_contents, 1):
            anchor_id = f'book-{idx}'
            f.write(f'\n\n<span id="{anchor_id}"></span>\n\n')
            f.write('='*80 + '\n')
            f.write(f'# {book_name}\n\n')
            f.write('='*80 + '\n\n')
            f.write(content)
            f.write('\n\n')

    sz = os.path.getsize(OUTPUT_FILE)
    print(f'\n完成! 输出: {OUTPUT_FILE}')
    print(f'大小: {sz/1024/1024:.1f} MB')
    print(f'共 {len(book_contents)} 本独立书籍')


if __name__ == '__main__':
    main()