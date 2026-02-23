"""Convert the markdown report to a styled PDF using only built-in libraries."""
import html
import re

INPUT = r"C:\Users\weega\.gemini\antigravity\brain\b812642f-3547-4849-8101-41737f6da25a\app_features_report.md"
OUTPUT = r"c:\Users\weega\Desktop\KitaHack-AR\New\see\SEE_App_Features_Report.html"

def md_to_html(md_text):
    """Simple markdown to HTML conversion."""
    lines = md_text.split('\n')
    html_lines = []
    in_table = False
    in_code = False
    in_list = False
    
    for line in lines:
        stripped = line.strip()
        
        # Code blocks
        if stripped.startswith('```'):
            if in_code:
                html_lines.append('</code></pre>')
                in_code = False
            else:
                lang = stripped[3:].strip()
                html_lines.append(f'<pre><code class="{lang}">')
                in_code = True
            continue
        
        if in_code:
            html_lines.append(html.escape(line))
            continue
        
        # Skip mermaid diagrams
        if stripped.startswith('graph ') or stripped.startswith('    A[') or stripped.startswith('    B[') or '-->' in stripped:
            continue
            
        # Empty line
        if not stripped:
            if in_table:
                html_lines.append('</table>')
                in_table = False
            if in_list:
                html_lines.append('</ul>')
                in_list = False
            html_lines.append('<br>')
            continue
        
        # Horizontal rule
        if stripped == '---':
            html_lines.append('<hr>')
            continue
        
        # Headers
        if stripped.startswith('# '):
            html_lines.append(f'<h1>{stripped[2:]}</h1>')
            continue
        elif stripped.startswith('## '):
            html_lines.append(f'<h2>{stripped[3:]}</h2>')
            continue
        elif stripped.startswith('### '):
            html_lines.append(f'<h3>{stripped[4:]}</h3>')
            continue
        
        # Blockquote
        if stripped.startswith('> '):
            html_lines.append(f'<blockquote>{stripped[2:]}</blockquote>')
            continue
        
        # Table
        if '|' in stripped and stripped.startswith('|'):
            cells = [c.strip() for c in stripped.split('|')[1:-1]]
            if all(set(c) <= set('- :') for c in cells):
                continue  # separator row
            if not in_table:
                html_lines.append('<table>')
                in_table = True
                html_lines.append('<tr>' + ''.join(f'<th>{c}</th>' for c in cells) + '</tr>')
            else:
                html_lines.append('<tr>' + ''.join(f'<td>{c}</td>' for c in cells) + '</tr>')
            continue
        
        # List items
        if stripped.startswith('- ') or stripped.startswith('* '):
            if not in_list:
                html_lines.append('<ul>')
                in_list = True
            content = stripped[2:]
            # Bold
            content = re.sub(r'\*\*(.+?)\*\*', r'<strong>\1</strong>', content)
            html_lines.append(f'<li>{content}</li>')
            continue
        
        if re.match(r'^\d+\. ', stripped):
            content = re.sub(r'^\d+\. ', '', stripped)
            content = re.sub(r'\*\*(.+?)\*\*', r'<strong>\1</strong>', content)
            if not in_list:
                html_lines.append('<ol>')
                in_list = True
            html_lines.append(f'<li>{content}</li>')
            continue
        
        # Regular paragraph with inline formatting
        text = stripped
        text = re.sub(r'\*\*(.+?)\*\*', r'<strong>\1</strong>', text)
        text = re.sub(r'`(.+?)`', r'<code class="inline">\1</code>', text)
        html_lines.append(f'<p>{text}</p>')
    
    if in_table:
        html_lines.append('</table>')
    if in_list:
        html_lines.append('</ul>')
    
    return '\n'.join(html_lines)


with open(INPUT, 'r', encoding='utf-8') as f:
    md_content = f.read()

body = md_to_html(md_content)

full_html = f"""<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>SEE App - Features & Techniques Report</title>
<style>
  body {{
    font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
    max-width: 900px;
    margin: 40px auto;
    padding: 20px 40px;
    color: #333;
    line-height: 1.6;
    background: #fff;
  }}
  h1 {{
    color: #1a73e8;
    border-bottom: 3px solid #1a73e8;
    padding-bottom: 10px;
    font-size: 28px;
  }}
  h2 {{
    color: #1a73e8;
    margin-top: 30px;
    font-size: 22px;
  }}
  h3 {{
    color: #333;
    margin-top: 25px;
    font-size: 18px;
  }}
  table {{
    width: 100%;
    border-collapse: collapse;
    margin: 15px 0;
    font-size: 14px;
  }}
  th {{
    background: #1a73e8;
    color: white;
    padding: 10px 15px;
    text-align: left;
  }}
  td {{
    padding: 10px 15px;
    border-bottom: 1px solid #e0e0e0;
  }}
  tr:nth-child(even) td {{
    background: #f8f9fa;
  }}
  blockquote {{
    background: #e8f0fe;
    border-left: 4px solid #1a73e8;
    padding: 12px 20px;
    margin: 15px 0;
    border-radius: 0 8px 8px 0;
    font-style: italic;
  }}
  pre {{
    background: #f5f5f5;
    padding: 15px;
    border-radius: 8px;
    overflow-x: auto;
    font-size: 13px;
  }}
  code.inline {{
    background: #f0f0f0;
    padding: 2px 6px;
    border-radius: 4px;
    font-size: 13px;
  }}
  hr {{
    border: none;
    border-top: 2px solid #e0e0e0;
    margin: 30px 0;
  }}
  ul, ol {{
    padding-left: 25px;
  }}
  li {{
    margin: 5px 0;
  }}
  @media print {{
    body {{ margin: 0; padding: 20px; }}
    h2 {{ page-break-before: auto; }}
    table {{ page-break-inside: avoid; }}
  }}
</style>
</head>
<body>
{body}
</body>
</html>"""

with open(OUTPUT, 'w', encoding='utf-8') as f:
    f.write(full_html)

print(f"✅ HTML report saved to: {OUTPUT}")
print("📄 To convert to PDF: Open the HTML file in your browser, then press Ctrl+P → Save as PDF")
