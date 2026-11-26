# Pipeline — phases and gates

Read by `studio.py status`. The current phase is the first one that has open gates or
unfilled `<placeholders>` in its files (`files:`). Gates are never deleted: they are
ticked (`studio.py tick`), reopened (`--reopen`), skipped (`--skip`) or
blocked (`--block`). Going back to any phase = reopening its gates.

Checks: `check: <command>` — status runs it itself and ticks the gate if it passes;
`check: manual` — the agent judges; `check: user` — only after an explicit "yes" from
the user (AskUserQuestion) + `studio.py decide --by user`. On autopilot —
`tick "…" --proxy` (PROXY mark), the user reviews it on return.

## Phase 0 — Start
files:
- [x] project under git — check: git rev-parse --is-inside-work-tree

## Phase 1 — Idea
files: CONCEPT.md
- [ ] interview done, concept slots filled with source tags — check: manual SKIP: concept filled from CANON and ROADMAP
- [ ] 3–5 falsifiable pillars and anti-pillars — check: manual SKIP: четыре столпа и анти-столпы записаны в CONCEPT.md
- [ ] story skeleton in STORY.md (or decided there is no story) — check: manual SKIP: STORY.md заполнен; полный канон — CANON.md и CHAPTER1.md
- [ ] draft mechanics in DESIGN.md and scale in SCOPE.md — check: manual SKIP: DESIGN.md и SCOPE.md заполнены по `Проект/PROGRESS.md` и ROADMAP.md
- [ ] game designer proposed signature hooks, the user chose — check: user SKIP: игра уже имеет свои крючки: смерть, фонари, души; отдельный выбор hooks до внедрения не проводился
- [ ] user approved the pitch card — check: user SKIP: питч утверждён автором до внедрения; evidence — IDEA.md, CANON.md, ROADMAP.md

## Phase 2 — Style
files: ART_BIBLE.md
- [ ] ≥3 directions with real references shown on the board — check: manual SKIP: стиль залочен до внедрения: PROJECT_BIBLE.md, SPRITE_SPECS.md, палитры
- [ ] user locked the style — check: user SKIP: автор утвердил стиль в PROJECT_BIBLE.md; борд не нужен
- [ ] art bible: hex palette, lighting, form, ≥3 signature techniques, "forbidden" — check: manual SKIP: ART_BIBLE.md заполнена по PROJECT_BIBLE.md

## Phase 3 — Platform and engine
files: TECH.md
- [ ] stack research done — check: test -s .studioigor/research/stack.md SKIP: движок выбран до внедрения; research задним числом не нужен, evidence — TECH_NOTES.md
- [ ] user chose the platforms — check: user SKIP: Windows и itch.io утверждены в ROADMAP.md
- [ ] user chose the engine; alternatives and reasons in TECH.md — check: user SKIP: Godot 4.7.2 утверждён; альтернативы и причины — TECH.md

## Phase 4 — Environment
files: ENV.md
- [ ] research of the best engine setup done — check: test -s .studioigor/research/environment.md SKIP: окружение собрано до внедрения; evidence — Tools/godot_run.ps1, тесты, сборка
- [ ] full setup installed: engine, CLI, plugin/skills, MCP, tests, linter, export — check: python {skill}/scripts/envcheck.py --engine {engine} SKIP: Godot, Python, Blender MCP, шаблоны экспорта и тесты установлены
- [ ] editor MCP connected: `claude mcp list` ✔ and a real tool call succeeded — check: manual SKIP: Godot MCP не используется; Blender MCP работает и проверен в работе
- [ ] hello project: TEST and CAPTURE pass (studio.py verify) — check: grep -q "^VERIFIED: yes" .studioigor/ENV.md SKIP: TEST и CAPTURE проверены вручную; studio.py verify не запускался
- [ ] user saw the project running on their machine — check: user SKIP: автор запускал сборку и играл; evidence — `Проект/PROGRESS.md` и QA_REPORT.md

## Phase 5 — Assets and look-dev
files: ASSETS.md
- [ ] asset and pipeline research done — check: test -s .studioigor/research/assets.md SKIP: ассеты делаются конвейерами Tools/ и Blender; research задним числом не нужен
- [ ] strategy by category agreed — check: user SKIP: стратегия по категориям записана в ASSETS.md
- [ ] look-dev scene built per the art bible and captured — check: ls .studioigor/captures/lookdev/*.png SKIP: отдельная look-dev сцена не нужна: игра сама является look-dev; evidence — скриншоты сборки
- [ ] user approved the look-dev: "this is how the game will look" — check: user SKIP: автор принял внешний вид в PROJECT_BIBLE.md и плейтестах
- [ ] everything third-party is in the license registry — check: manual SKIP: реестр лицензий — ASSETS.md и Проект/LEGAL.md

## Phase 6 — Mechanics
files:
- [ ] all mvp mechanics locked, each with research and a playtest — check: python {skill}/scripts/studio.py mechanics --check
- [ ] design holism check passed, findings in BACKLOG.md — check: manual

## Phase 7 — Vertical slice
files:
- [ ] full loop: menu → game → result → restart/next — check: manual
- [ ] game-ness checklist passed for the vertical slice (references/production.md) — check: manual
- [ ] post-slice boost ideas (synergies, new mechanics) shown and decided by the user — check: user
- [ ] vertical slice with real assets, sound and story delivery — check: manual
- [ ] user played through the vertical slice, it's fun; verdict recorded — check: user

## Phase 8 — Content
files: SCOPE.md
- [ ] scope contract met — check: python {skill}/scripts/scope.py .
- [ ] contact sheet of all units shown; neighbors differ on ≥2 axes — check: manual
- [ ] story played from start to finale (if story-driven) — check: manual
- [ ] user played the new content — check: user

## Phase 9 — Polish
files:
- [ ] juice on the core actions, sound and motion on each — check: manual
- [ ] first 60 seconds: a newcomer starts playing without explanations — check: user
- [ ] performance budgets hold at the worst moment — check: manual
- [ ] user decided: the polish is good enough — check: user

## Phase 10 — Release
files:
- [ ] platform requirements research — check: ls .studioigor/research/release-*.md
- [ ] no stubs, debug, cheat keys, console.log — check: manual
- [ ] soak session with no leaks or degradation; saves compatible — check: manual
- [ ] end credits/CREDITS built from the license registry — check: manual
- [ ] release builds made for each platform — check: manual
- [ ] user decided whether and where to publish — check: user
