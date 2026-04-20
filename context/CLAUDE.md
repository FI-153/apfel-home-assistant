# Context Directory

This directory contains everything Claude needs to provide good results on this repo.

- **knowledge/** — Domain knowledge, API references, architecture docs. Markdown files with research, API specs, reference code. Claude may scan the codebase and generate files here when asked.
- **planning/** — Agent-written plans, one `.md` per task. Committed to git and never deleted. See the Planning Workflow in the root `CLAUDE.md` for the annotation conventions (`/user`, `/new`, `- [ ]`, `- [x]`).
- **styling/** — Code formatting and style rules. See `formatting.md` for the authoritative style guide.
