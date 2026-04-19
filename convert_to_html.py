#!/usr/bin/env python3
"""
Convert white paper Markdown to HTML for printing to PDF
"""

import re
import sys
from pathlib import Path

def markdown_to_html(md_content):
    """Convert basic markdown to HTML"""
    html = md_content
    
    # Convert code blocks
    html = re.sub(
        r'```(\w+)?\n(.*?)```',
        r'<pre><code>\2</code></pre>',
        html,
        flags=re.DOTALL
    )
    
    # Convert inline code
    html = re.sub(r'`([^`]+)`', r'<code>\1</code>', html)
    
    # Convert headers
    html = re.sub(r'^### (.*?)$', r'<h3>\1</h3>', html, flags=re.MULTILINE)
    html = re.sub(r'^## (.*?)$', r'<h2>\1</h2>', html, flags=re.MULTILINE)
    html = re.sub(r'^# (.*?)$', r'<h1>\1</h1>', html, flags=re.MULTILINE)
    
    # Convert bold
    html = re.sub(r'\*\*(.*?)\*\*', r'<strong>\1</strong>', html)
    
    # Convert italic
    html = re.sub(r'\*(.*?)\*', r'<em>\1</em>', html)
    
    # Convert lists
    html = re.sub(r'^\- (.*?)$', r'<li>\1</li>', html, flags=re.MULTILINE)
    html = re.sub(r'(<li>.*?</li>)', r'<ul>\1</ul>', html, flags=re.DOTALL)
    html = html.replace('</ul>\n<ul>', '\n')
    
    # Convert numbered lists
    html = re.sub(r'^\d+\. (.*?)$', r'<li>\1</li>', html, flags=re.MULTILINE)
    
    # Convert JSON blocks - make them look nice
    html = re.sub(
        r'<pre><code>(\{.*?\})</code></pre>',
        r'<pre><code class="language-json">\1</code></pre>',
        html,
        flags=re.DOTALL
    )
    
    # Convert line breaks
    html = html.replace('\n\n', '</p><p>')
    html = '<p>' + html + '</p>'
    
    # Handle mermaid diagrams
    html = re.sub(
        r'```mermaid\n(.*?)```',
        r'<div class="mermaid-placeholder"><strong>Diagram:</strong><pre>\1</pre></div>',
        html,
        flags=re.DOTALL
    )
    
    return html

def convert_to_html():
    """Convert white paper markdown to HTML"""
    script_dir = Path(__file__).parent
    md_file = script_dir / "docs" / "white-paper-ai-foundry-hub-spoke.md"
    html_file = script_dir / "docs" / "white-paper-ai-foundry-hub-spoke.html"
    
    if not md_file.exists():
        print(f"Error: Markdown file not found at {md_file}")
        return False
    
    print(f"Reading markdown from: {md_file}")
    
    # Read markdown
    with open(md_file, 'r', encoding='utf-8') as f:
        md_content = f.read()
    
    # Convert to HTML
    body_html = markdown_to_html(md_content)
    
    # Create full HTML document
    full_html = f"""<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>AI Foundry Hub and Spoke Design Pattern for Multi-Agent Systems</title>
    <style>
        :root {{
            --primary-color: #0078d4;
            --secondary-color: #106ebe;
            --tertiary-color: #1e90ff;
            --text-color: #333;
            --bg-color: #ffffff;
            --border-color: #ddd;
        }}
        
        * {{
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }}
        
        html {{
            scroll-behavior: smooth;
        }}
        
        body {{
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Roboto', 'Oxygen',
                'Ubuntu', 'Cantarell', 'Fira Sans', 'Droid Sans', 'Helvetica Neue',
                sans-serif;
            line-height: 1.7;
            color: var(--text-color);
            background-color: var(--bg-color);
        }}
        
        @media print {{
            body {{
                margin: 0;
                padding: 20px;
            }}
            h1, h2 {{
                page-break-after: avoid;
            }}
            p {{
                page-break-inside: avoid;
            }}
        }}
        
        .container {{
            max-width: 900px;
            margin: 0 auto;
            padding: 40px 20px;
        }}
        
        h1 {{
            color: var(--primary-color);
            border-bottom: 3px solid var(--primary-color);
            padding-bottom: 15px;
            margin: 40px 0 20px 0;
            font-size: 2.5em;
            line-height: 1.2;
        }}
        
        h2 {{
            color: var(--secondary-color);
            margin: 35px 0 15px 0;
            font-size: 1.8em;
            border-left: 4px solid var(--secondary-color);
            padding-left: 15px;
        }}
        
        h3 {{
            color: var(--tertiary-color);
            margin: 25px 0 12px 0;
            font-size: 1.3em;
        }}
        
        p {{
            margin: 15px 0;
            text-align: justify;
        }}
        
        ul, ol {{
            margin: 15px 0 15px 30px;
        }}
        
        li {{
            margin: 8px 0;
        }}
        
        code {{
            background-color: #f4f4f4;
            padding: 2px 6px;
            border-radius: 3px;
            font-family: 'Courier New', 'Monaco', monospace;
            font-size: 0.95em;
            color: #c7254e;
        }}
        
        pre {{
            background-color: #f8f8f8;
            padding: 15px;
            border-radius: 5px;
            overflow-x: auto;
            border-left: 4px solid var(--primary-color);
            margin: 15px 0;
            font-size: 0.9em;
        }}
        
        pre code {{
            background-color: transparent;
            padding: 0;
            color: #333;
        }}
        
        .mermaid-placeholder {{
            background-color: #f9f9f9;
            border: 2px dashed var(--primary-color);
            padding: 20px;
            margin: 20px 0;
            border-radius: 5px;
            text-align: center;
        }}
        
        .mermaid-placeholder pre {{
            background-color: white;
            border-left: none;
            padding: 10px;
            margin: 10px 0 0 0;
            overflow-x: auto;
        }}
        
        strong {{
            font-weight: 600;
            color: var(--secondary-color);
        }}
        
        em {{
            font-style: italic;
            color: #555;
        }}
        
        table {{
            border-collapse: collapse;
            width: 100%;
            margin: 20px 0;
        }}
        
        th, td {{
            border: 1px solid var(--border-color);
            padding: 12px;
            text-align: left;
        }}
        
        th {{
            background-color: var(--primary-color);
            color: white;
            font-weight: 600;
        }}
        
        tr:nth-child(even) {{
            background-color: #f9f9f9;
        }}
        
        blockquote {{
            border-left: 4px solid var(--primary-color);
            margin-left: 0;
            padding-left: 20px;
            color: #666;
            font-style: italic;
        }}
        
        a {{
            color: var(--primary-color);
            text-decoration: none;
        }}
        
        a:hover {{
            text-decoration: underline;
        }}
        
        .footer {{
            margin-top: 50px;
            padding-top: 20px;
            border-top: 2px solid var(--border-color);
            font-size: 0.9em;
            color: #666;
        }}
        
        .footer ul {{
            margin: 10px 0 0 20px;
            list-style-type: none;
        }}
        
        .footer li {{
            margin: 5px 0;
        }}
        
        .print-instruction {{
            background-color: #e7f3ff;
            border: 1px solid var(--primary-color);
            padding: 15px;
            border-radius: 5px;
            margin: 20px 0;
            color: #004085;
        }}
        
        .print-instruction strong {{
            color: var(--primary-color);
        }}
    </style>
</head>
<body>
    <div class="container">
        <div class="print-instruction">
            <strong>📄 Printing Instructions:</strong> Use your browser's Print function (Ctrl+P or Cmd+P) and select 
            "Save as PDF" to create a PDF version. Set margins to 0.5" and select "Background graphics" for best results.
        </div>
        
        {body_html}
        
        <div class="footer">
            <p><strong>Document Information:</strong></p>
            <ul>
                <li><strong>Title:</strong> AI Foundry Hub and Spoke Design Pattern for Multi-Agent Systems</li>
                <li><strong>Version:</strong> 0.1 (Draft)</li>
                <li><strong>Generated:</strong> April 18, 2026</li>
                <li><strong>Repository:</strong> <code>ai-agent-hub-spoke/infrastructure</code></li>
                <li><strong>License:</strong> MIT (coming in public release)</li>
            </ul>
        </div>
    </div>
</body>
</html>"""
    
    # Write HTML file
    with open(html_file, 'w', encoding='utf-8') as f:
        f.write(full_html)
    
    print(f"✓ HTML file created successfully: {html_file}")
    print(f"\nHow to create PDF for LinkedIn:")
    print(f"1. Open the HTML file in your browser")
    print(f"2. Press Ctrl+P (or Cmd+P on Mac)")
    print(f"3. Select 'Save as PDF'")
    print(f"4. Set margins to 0.5 inches")
    print(f"5. Enable 'Background graphics'")
    print(f"6. Save as 'white-paper-ai-foundry-hub-spoke.pdf'")
    
    return True

if __name__ == "__main__":
    success = convert_to_html()
    sys.exit(0 if success else 1)
