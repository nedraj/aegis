# Diagram Sources

This folder contains the **source files** for all Mermaid diagrams used in the project documentation.

## Why This Folder Exists

- Mermaid diagrams render nicely on GitHub.
- For PDFs, printed docs, or presentations, you may want static images.
- Having the source here makes diagrams maintainable and version-controlled.

## How to Generate Images

1. Go to [https://mermaid.live](https://mermaid.live)
2. Paste the content of any `.mmd` file
3. Click **Download** → choose PNG or SVG

Alternative (command line):

```bash
# Using mermaid-cli (if installed)
mmdc -i architecture-flow.mmd -o architecture-flow.png
```

## Current Diagrams

| File                        | Used In                  | Description                          |
|----------------------------|--------------------------|--------------------------------------|
| `architecture-flow.mmd`    | README.md                | High-level bundle + deployment flow  |
| `operator-journey.mmd`     | docs/RUNBOOK.md          | Full operator workflow from laptop to air-gap proof |

## Recommendation

When you modify a diagram, update the `.mmd` file here **and** the copy inside the Markdown file.

For important releases, generate fresh PNG/SVG versions and place them in `docs/images/`.
