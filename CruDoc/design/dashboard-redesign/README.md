# CruDoc dashboard redesign — handoff

Everything Claude Code needs to build the "Calm Clinical" dashboard.

| Path | What it is |
|---|---|
| `DESIGN_SPEC.md` | Source of truth: rules, tokens (Flutter `Color` values), type, shape, layout, components, behaviour |
| `PROMPTS.md` | Copy-paste prompts for Claude Code, phase by phase |
| `screens/` | Target screenshots: day, evening, visual system |
| `reference/` | The same designs as HTML, for exact measurements (open in a browser) |
| `fonts/` | Geist TTFs (SIL Open Font License, see `fonts/OFL.txt`) |
| `claude-rules/crudoc-ui.md` | Design rules for Claude Code; copy to `.claude/rules/crudoc-ui.md` |

## Setup
1. Copy this folder into the repo as `design/dashboard-redesign/`.
2. Copy `claude-rules/crudoc-ui.md` to `.claude/rules/crudoc-ui.md`. It loads automatically whenever Claude Code works on files under `lib/`.
3. Commit, so every Claude Code session and teammate sees the same spec.
4. Open Claude Code in your IDE, switch to Plan mode, and send the kickoff prompt from `PROMPTS.md`.
