# CruDoc: Appointments, Inventory and Revenue handoff

1. Unzip this folder into your project as `design/clinic-redesign/`.
2. In Claude Code, paste the kickoff prompt below. `PROMPT.md` holds the full spec: how the agent should run, and every screen's layout and behaviour.

Queue is not included; its design is still changing.

## Contents
- `PROMPT.md`: the full instructions for the agent
- `screens/`: the target look, one PNG per state (1440 px wide)
- `html/`: the design source files, used for exact sizes, colours and copy. Everything in them is demo data.

## Kickoff prompt

```
Read design/clinic-redesign/PROMPT.md and carry it out end to end. It redesigns Appointments (Day, Week, Month and overlapping visits), Inventory (list and grid views with an item side panel) and Revenue. Don't touch Queue.

How to work:
- Parallel first. Run the recon with 3 Explore subagents at the same time, write the plan, then launch the 4 builder subagents in ONE message so they run in parallel. Each builder edits only the files it owns in the plan.
- No checking until the very end. Nobody runs flutter analyze, tests, build_runner, pub get, the app or git during recon or building, and nobody stops to fix analyzer errors along the way.
- At the very end, you alone integrate, run build_runner if the project uses it, run flutter analyze and the tests, compare the goldens with the PNGs in screens/, fix everything, commit once per feature and write the report.

If git has uncommitted changes, stop and tell me before starting.
```
