## 提示词模板（复制使用）

```
请根据以下要求，生成一个可直接用 Word 打开并另存为 .docx 的 HTML 文件：

【基本信息】
- 学校名称：XXXXX学
- 年级/册次：____年级____册
- 单元范围：Unit ____（如"Unit 1-2"或"全册"）
- 单词数量：50个
- 满分分值：100分（每空2分）

【词汇来源】
（在此粘贴课本单词表图片或手动列出单词，格式如下）
Unit X：word1 中文, word2 中文, word3 中文, ...
Unit Y：word1 中文, word2 中文, word3 中文, ...

【排版要求】
1. 文件格式：HTML，包含 Word 兼容的 XML 命名空间声明（ProgId=Word.Document）
2. 页面尺寸：A4（595.3pt × 841.9pt），页边距上60pt 左右70pt 下50pt
3. 字体：Microsoft YaHei（微软雅黑），正文 11.5pt，标题 16pt
4. 布局：使用 <table> 三列等宽（各 33.3%），table-layout: fixed
5. 每行3个词，序号加粗左对齐
6. 填写区域：用 display:inline-block + border-bottom 实现下划线空白，宽度 80pt
7. 题目分布：中→英约 34 题，英→中约 16 题
8. 姓名/班级/得分行也使用下划线样式

【HTML 结构模板】
- <h1> 标题（学校+年级+副标题）
- <p class="sub"> 说明文字
- <p class="info-row"> 姓名/班级/得分
- <table> 主体内容，每 <tr> 包含 3 个 <td>
- 中→英格式：序号. 中文：+（下划线）
- 英→中格式：序号. english → +（下划线）

【CSS 关键样式】
@page { size: 595.3pt 841.9pt; margin: 60pt 70pt 50pt 70pt; }
table { width: 100%; border-collapse: collapse; table-layout: fixed; }
td { padding: 5pt 2pt; vertical-align: top; font-size: 11.5pt; width: 33.3%; }
.num { font-weight: bold; }
.blank { display: inline-block; width: 80pt; border-bottom: 1.5pt solid #000; }

请直接输出完整的 HTML 文件代码。
```

---

## 使用示例

```
请根据以下要求，生成一个可直接用 Word 打开并另存为 .docx 的 HTML 文件：

【基本信息】
- 学校名称：XXXXX学
- 年级/册次：X年级下册
- 单元范围：Unit 1-2
- 单词数量：50个
- 满分分值：100分（每空2分）

【词汇来源】
Unit 1：sorry 对不起, late 迟到, class 课, hurry up 快点, ready 准备好, ...
Unit 2：watch 看, TV 电视, homework 家庭作业, first 首先, wet 湿的, ...

（其余按模板填写即可）
```

---

## 注意事项

- 生成的 .html 文件可用 Word 直接打开，然后"另存为 → .docx"
- 如需调整下划线长度，修改 `.blank` 的 `width` 值（默认 80pt）
- 如需调整行间距，修改 `td` 的 `padding` 值
- 如需增加到每行4列，将 `width: 33.3%` 改为 `25%`，并相应缩小 `.blank` 宽度
- 如果单词总数不是3的倍数，最后一行空余的 `<td>` 留空即可