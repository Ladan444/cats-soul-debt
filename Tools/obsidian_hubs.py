"""Хабы для графа Obsidian: каждый документ проекта связан с картой, а не висит «сиротой» на краю графа.

Пересобирает два файла-оглавления по содержимому папок (запускать после добавления новых документов):
  Литература/Документы.md — все документы Литературы по группам + ссылка на вики ([[Главная]]) и проект;
  Проект/Проект.md        — документы направлений (дорожная карта, бюджет, команда, маркетинг…).

  python Tools/obsidian_hubs.py
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LIT = ROOT / "Литература"
PROJ = ROOT / "Проект"

# Группы для оглавления Литературы: имя файла (без .md) → группа; остальное — «Прочее».
GROUPS = {
    "Лор и сюжет": ["CANON", "CHAPTER1", "STORY_HANDOVER", "NPC_DRAFTS", "FULL_LORE", "LORE_DOCUMENT", "IDEA"],
    "Спецификации": ["PROJECT_BIBLE", "COMBAT_SPEC", "UI_SPEC", "VILLAGE_SPEC", "BALANCE"],
    "Промпты для арта": ["SPRITE_SPECS", "ICON_PROMPTS", "TEXTURE_PROMPTS", "NPC_PROMPTS"],
    "Техника": ["TECH_NOTES"],
}
SKIP_DIRS = {"Вики"}           # у вики свой хаб — Главная
HUB_NAMES = {"Документы", "Проект"}


def note(path: Path) -> str:
    return path.stem


def lit_hub() -> str:
    top = sorted(p for p in LIT.glob("*.md") if note(p) not in HUB_NAMES)
    used, lines = set(), ["# Документы проекта", "",
                          "Оглавление для графа Obsidian (собирает `python Tools/obsidian_hubs.py`, вручную не править).", "",
                          "Вики лора: [[Главная]] · Направления проекта: [[Проект]]", ""]
    for group, names in GROUPS.items():
        present = [n for n in names if (LIT / f"{n}.md").exists()]
        if present:
            lines += [f"## {group}", ""] + [f"- [[{n}]]" for n in present] + [""]
            used |= set(present)
    rest = [note(p) for p in top if note(p) not in used]
    if rest:
        lines += ["## Прочее", ""] + [f"- [[{n}]]" for n in rest] + [""]
    for sub in sorted(d for d in LIT.iterdir() if d.is_dir() and d.name not in SKIP_DIRS):
        notes = sorted(sub.rglob("*.md"))
        if notes:
            lines += [f"## {sub.name}", ""] + [f"- [[{note(p)}]]" for p in notes] + [""]
    return "\n".join(lines)


def proj_hub() -> str:
    notes = sorted(p for p in PROJ.rglob("*.md") if note(p) not in HUB_NAMES)
    return "\n".join(["# Проект", "", "Направления вне кода: стратегия, команда, маркетинг. Все документы: [[Документы]].", ""]
                     + [f"- [[{note(p)}]]" for p in notes] + [""])


def main() -> None:
    (LIT / "Документы.md").write_text(lit_hub(), encoding="utf-8")
    if PROJ.exists():
        (PROJ / "Проект.md").write_text(proj_hub(), encoding="utf-8")
    print("хабы обновлены")


if __name__ == "__main__":
    main()
