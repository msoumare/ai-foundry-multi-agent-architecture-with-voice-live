# GitHub Publishing Checklist (Free and Public)

Use this checklist before making the repository public.

## 1. Licensing and Legal

- Add an open-source license (MIT is common for reference architectures).
- Confirm no proprietary text, credentials, or internal URLs remain in files.
- Add a disclaimer if this is a reference implementation and not production support software.

## 2. Repository Hygiene

- Ensure `.gitignore` excludes:
  - `.terraform/`
  - `*.tfstate`
  - `*.tfstate.*`
  - secret files (`*.env`, key files, local creds)
- Remove generated artifacts and local test outputs.
- Ensure Terraform backend values in examples are placeholders, not real tenant data.

## 3. Documentation Baseline

- Keep root `README.md` focused on:
  - architecture intent
  - module map
  - quick start
  - security model
- Include this white paper draft:
  - `docs/white-paper-ai-foundry-hub-spoke.md`
- Add diagrams (PNG/SVG) in a future `docs/diagrams/` folder for publishing platforms that do not render Mermaid.

## 4. Security Guardrails

- Verify managed identities are used where possible.
- Verify role assignments are least privilege.
- Confirm private endpoint coverage for data and AI services.
- Add `SECURITY.md` with a vulnerability reporting process.

## 5. Community Files (Recommended)

- Add `CONTRIBUTING.md` with coding and PR guidance.
- Add `CODE_OF_CONDUCT.md` (Contributor Covenant is common).
- Add issue and PR templates in `.github/`.

## 6. Release Strategy

- Tag first public release as `v0.1.0` or `v1.0.0`.
- Create a short release note summarizing:
  - architecture scope
  - known limitations
  - roadmap items

## 7. Commands to Publish

If not already connected to GitHub:

```bash
git init
git add .
git commit -m "Initial public release: AI Foundry hub-and-spoke infrastructure"
git branch -M main
git remote add origin https://github.com/<your-org>/<your-repo>.git
git push -u origin main
```

If remote already exists:

```bash
git add .
git commit -m "Add white paper and publishing docs"
git push
```

## 8. Suggested GitHub Repository Metadata

- About: "Terraform-based Azure AI Foundry hub-and-spoke reference architecture for multi-agent systems"
- Topics:
  - `azure`
  - `terraform`
  - `ai-foundry`
  - `multi-agent`
  - `fastapi`
  - `aks`
  - `hub-and-spoke`

## 9. Post-Publish Validation

- Confirm public clone works from a clean machine.
- Confirm docs render correctly in GitHub preview.
- Confirm no secret scanning alerts are triggered.
- Confirm roadmap issues are visible for contributors.
