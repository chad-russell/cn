---
name: explain-html
description: Present explanations, summaries, and answers as a polished self-contained HTML page opened in the browser. Use when the user asks to explain, summarize, teach, describe, or break down a concept — and it's clear they want an informational answer, not code changes or file edits. Also triggers on /skill:explain. Produces a single HTML file with inline styles, opened via xdg-open.
---

# Explain as HTML

When this skill is active, your job is to answer the user's question by producing a single, self-contained HTML file and opening it in their default browser — not by writing a long markdown response in the chat.

## When to Use

- The user asks you to **explain**, **summarize**, **describe**, **teach**, or **break down** something.
- The user asks a conceptual question that deserves a rich, well-organized answer.
- The user invokes `/skill:explain`.
- The user asks a question and it's clear they just want information — not code changes, file edits, or terminal output.

Do **not** use this skill when the user explicitly asks for code, file edits, a quick one-liner answer, or when the answer is trivial (a single word/number).

## Workflow

1. **Gather information.** Read files, search, use bash — do whatever research is needed to answer thoroughly. You can use all your tools for this phase.

2. **Write the HTML file.** Create a single self-contained HTML file at:

   ```
   /tmp/pi-explain-<slug>.html
   ```

   Where `<slug>` is a short, dashed version of the topic (e.g., `nfs-mount-options`, `rust-lifetimes`, `how-systemd-timers-work`).

   The file must be **completely self-contained**: all CSS inline or in a `<style>` block, all JS inline. No external fonts, CDNs, or linked resources.

3. **Open it in the browser:**

   ```bash
   xdg-open file:///tmp/pi-explain-<slug>.html
   ```

4. **Confirm in chat.** Just say you've opened the explanation in the browser. No need to repeat the content.

## HTML Design Guidelines

Produce pages that are genuinely pleasant to read. The HTML should feel like a well-designed article or reference page — not a barebones document or a generic template.

### Structure

- Use semantic HTML (`<article>`, `<section>`, `<h1>`–`<h4>`, `<p>`, `<ul>`, `<ol>`, `<dl>`, `<table>`, `<code>`, `<pre>`, `<details>`, `<summary>`).
- Start with a clear `<h1>` title, optionally a one-line subtitle or intro.
- Break content into logical sections with headings.
- Use `<details>/<summary>` for supplementary or deep-dive content that would otherwise clutter the page.
- For code examples, use `<pre><code>` with a subtle background. Add a small label above the block indicating the language when relevant.

### Typography

- Use a system font stack that looks good: `'Iowan Old Style', 'Palatino Linotype', 'Book Antiqua', Palatino, Georgia, serif` for body text, and `'SF Mono', 'Cascadia Code', 'Fira Code', 'Consolas', monospace` for code.
- Body font size: 16–18px. Line height: 1.6–1.8.
- Generous paragraph spacing (0.8–1em).
- Max content width: 720–800px, centered.

### Color and Theme

- Default to a **light, warm** theme: off-white background (`#fafaf8` or similar), dark text (`#1a1a1a`).
- Use color intentionally — for callout boxes, section accents, or highlighted terms — not everywhere.
- Accent color: pick one that fits the topic. Muted blues, teals, warm oranges, or soft greens all work. Avoid harsh neon colors.
- Code blocks: light gray background (`#f4f4f4`), slightly darker border.

### Interactive and Visual Elements

Use these when they genuinely improve the answer:

- **Tables** — for comparisons, option lists, parameter references. Stripe rows, add borders or hover effects.
- **Collapsible sections** (`<details>/<summary>`) — for "learn more" deep-dives, advanced notes, long code examples.
- **Callout boxes** — for warnings, tips, or key takeaways. Use a left border + background tint.
- **Inline code** — for filenames, commands, short values. Subtle background highlight.
- **Numbered steps** — for procedural/how-to content.
- **Definition lists** — for term → explanation pairs.

### What to Avoid

- No external fonts, scripts, or stylesheets.
- No JavaScript frameworks or build tools.
- No cookie-cutter "AI aesthetic" — no generic purple gradients, no predictable card grids, no hero sections.
- No dark theme by default (unless the topic strongly suggests it).
- Do not over-design. If the content is simple, the page should be simple.

### Minimal Template

Adapt freely — this is a starting point, not a constraint:

```html
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Topic</title>
<style>
  /* Reset and base */
  *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
  body {
    font-family: 'Iowan Old Style', 'Palatino Linotype', 'Book Antiqua', Palatino, Georgia, serif;
    font-size: 17px;
    line-height: 1.7;
    color: #1a1a1a;
    background: #fafaf8;
    padding: 2rem 1rem;
  }
  article {
    max-width: 760px;
    margin: 0 auto;
  }
  h1 {
    font-size: 2rem;
    margin-bottom: 0.3em;
    letter-spacing: -0.01em;
  }
  .subtitle {
    color: #666;
    font-size: 1.05rem;
    margin-bottom: 2rem;
  }
  h2 {
    font-size: 1.4rem;
    margin-top: 2rem;
    margin-bottom: 0.6rem;
    padding-bottom: 0.3rem;
    border-bottom: 1px solid #e0e0e0;
  }
  h3 {
    font-size: 1.15rem;
    margin-top: 1.5rem;
    margin-bottom: 0.4rem;
  }
  p { margin-bottom: 0.9em; }
  ul, ol { margin-bottom: 0.9em; padding-left: 1.5em; }
  li { margin-bottom: 0.3em; }
  code {
    font-family: 'SF Mono', 'Cascadia Code', 'Fira Code', Consolas, monospace;
    font-size: 0.88em;
    background: #f0efe8;
    padding: 0.15em 0.4em;
    border-radius: 3px;
  }
  pre {
    background: #f4f4f4;
    border: 1px solid #e0e0e0;
    border-radius: 5px;
    padding: 1em;
    overflow-x: auto;
    margin-bottom: 1em;
    font-size: 0.9em;
    line-height: 1.5;
  }
  pre code { background: none; padding: 0; }
  details {
    margin-bottom: 1em;
    border: 1px solid #e0e0e0;
    border-radius: 5px;
    padding: 0.6em 1em;
  }
  summary {
    cursor: pointer;
    font-weight: 600;
    color: #444;
  }
  table {
    width: 100%;
    border-collapse: collapse;
    margin-bottom: 1em;
    font-size: 0.95em;
  }
  th, td {
    text-align: left;
    padding: 0.5em 0.8em;
    border-bottom: 1px solid #e0e0e0;
  }
  th { background: #f4f4f4; font-weight: 600; }
  tr:hover { background: #f8f8f5; }
  .callout {
    border-left: 4px solid #b8926a;
    background: #faf5ef;
    padding: 0.8em 1em;
    margin-bottom: 1em;
    border-radius: 0 4px 4px 0;
    font-size: 0.95em;
  }
  .callout.tip { border-left-color: #6a9e6a; background: #f0f7f0; }
  .callout.warn { border-left-color: #c4944a; background: #fdf8ee; }
</style>
</head>
<body>
<article>
  <h1>Title</h1>
  <p class="subtitle">A brief one-liner</p>

  <h2>Section</h2>
  <p>Content here.</p>
</article>
</body>
</html>
```

## Examples

### Simple explanation

User: "Explain how NFS mount options work"

→ Research, then write `/tmp/pi-explain-nfs-mount-options.html` with sections for each option category, a table of common options, and collapsible details for advanced flags. Open with `xdg-open`.

### Codebase walkthrough

User: "How does the backup system work?"

→ Read relevant files (`servers/hub/backup/`), trace the logic, then write `/tmp/pi-explain-backup-system.html` with a flow diagram (using HTML/CSS boxes + arrows or a simple SVG), section per component, and key config snippets.

### Comparison

User: "Summarize the differences between Podman Quadlets vs Docker Compose"

→ Write `/tmp/pi-explain-quadlets-vs-compose.html` with side-by-side comparison tables, pros/cons, and collapsible examples for each approach.

### Quick concept

User: "Explain brioche's includeDirectory"

→ A simpler page — just a clear explanation with a couple of code examples. Don't over-design for short topics.
