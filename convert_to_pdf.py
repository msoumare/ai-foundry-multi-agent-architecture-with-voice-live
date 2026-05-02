#!/usr/bin/env python3
"""
Convert white paper Markdown to PDF for LinkedIn publishing
"""

import subprocess
import sys
import os
from pathlib import Path

def install_package(package_name):
    """Install a Python package using pip"""
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", package_name])

def convert_markdown_to_pdf():
    """Convert white paper markdown to PDF"""
    from pathlib import Path
    script_dir = Path(__file__).parent
    md_file = script_dir / "docs" / "white-paper-ai-foundry-multi-agent-systems-hub-api-with-agent-framework-and-spokes-with-agent-service.md"
    pdf_file = script_dir / "docs" / "white-paper-ai-foundry-multi-agent-systems-hub-api-with-agent-framework-and-spokes-with-agent-service.pdf"
    
    if not md_file.exists():
        print(f"Error: Markdown file not found at {md_file}")
        return False
    
    print(f"Reading markdown from: {md_file}")
    
    try:
        # Try using pypandoc if pandoc is available
        import pypandoc
        print("Converting markdown to PDF using pandoc...")
        output = pypandoc.convert_file(
            str(md_file),
            'pdf',
            outputfile=str(pdf_file),
            extra_args=['--pdf-engine=xelatex']
        )
        print(f"✓ PDF created successfully: {pdf_file}")
        return True
    except Exception as e:
        print(f"Pandoc conversion failed: {e}")
        print("\nTrying alternative approach with markdown2 and weasyprint...")
        
        try:
            # Fallback: use markdown2 + weasyprint
            import markdown2
            from weasyprint import HTML, CSS
            from pathlib import Path
            
            # Read markdown
            with open(md_file, 'r', encoding='utf-8') as f:
                md_content = f.read()
            
            # Convert markdown to HTML
            html_content = markdown2.markdown(md_content, extras=['tables', 'fenced-code-blocks'])
            
            # Wrap in proper HTML document
            full_html = f"""<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <title>AI Foundry Hub and Spoke Design Pattern for Multi-Agent Systems</title>
    <style>
        body {{
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial, sans-serif;
            line-height: 1.6;
            color: #333;
            margin: 40px;
            max-width: 900px;
        }}
        h1 {{
            color: #0078d4;
            border-bottom: 3px solid #0078d4;
            padding-bottom: 10px;
        }}
        h2 {{
            color: #106ebe;
            margin-top: 30px;
        }}
        h3 {{
            color: #1e90ff;
        }}
        code {{
            background-color: #f4f4f4;
            padding: 2px 6px;
            border-radius: 3px;
            font-family: 'Courier New', monospace;
        }}
        pre {{
            background-color: #f4f4f4;
            padding: 12px;
            border-radius: 5px;
            overflow-x: auto;
            border-left: 4px solid #0078d4;
        }}
        pre code {{
            background-color: transparent;
            padding: 0;
        }}
        blockquote {{
            border-left: 4px solid #0078d4;
            margin-left: 0;
            padding-left: 15px;
            color: #666;
        }}
        table {{
            border-collapse: collapse;
            width: 100%;
            margin: 20px 0;
        }}
        th, td {{
            border: 1px solid #ddd;
            padding: 12px;
            text-align: left;
        }}
        th {{
            background-color: #f0f0f0;
            font-weight: bold;
        }}
        .mermaid {{
            text-align: center;
            margin: 20px 0;
            padding: 20px;
            background-color: #f9f9f9;
            border: 1px solid #ddd;
            border-radius: 5px;
        }}
    </style>
</head>
<body>
{html_content}
<div style="margin-top: 50px; padding-top: 20px; border-top: 2px solid #ddd; font-size: 0.9em; color: #666;">
    <p><strong>Document Information:</strong></p>
    <ul>
        <li>Title: AI Foundry Hub and Spoke Design Pattern for Multi-Agent Systems</li>
        <li>Version: 0.1 (Draft)</li>
        <li>Generated: April 18, 2026</li>
        <li>Repository: <code>ai-agent-hub-spoke/infrastructure</code></li>
    </ul>
</div>
</body>
</html>"""
            
            # Generate PDF
            HTML(string=full_html).write_pdf(str(pdf_file))
            print(f"✓ PDF created successfully: {pdf_file}")
            return True
            
        except ImportError as ie:
            print(f"Required library missing: {ie}")
            print("\nInstalling required packages...")
            try:
                install_package("markdown2")
                install_package("weasyprint")
                print("Packages installed. Retrying conversion...")
                return convert_markdown_to_pdf()
            except Exception as install_err:
                print(f"Failed to install packages: {install_err}")
                return False
        except Exception as conversion_err:
            print(f"Conversion failed: {conversion_err}")
            return False

if __name__ == "__main__":
    success = convert_markdown_to_pdf()
    sys.exit(0 if success else 1)
