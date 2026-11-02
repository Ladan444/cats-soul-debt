"""Черновики текстов через Ollama (Gemma и др.) — дешёвая генерация пачками, проверка — на Claude или авторе.

Для чего: варианты описаний предметов, слухов, реплик, названий; пересказ длинных текстов; вычитка. НЕ для кода
проекта и не для решений по канону — результат всегда черновик, его сверяют с Литература/CANON.md.

  python Tools/local_llm.py "Придумай 10 названий для амулетов из речного камня" --out scratch.md
  python Tools/local_llm.py --file задания.txt --context Литература/CANON.md --out черновики.md
  python Tools/local_llm.py "..." --n 3 --temp 1.0            # три независимых варианта
  python Tools/local_llm.py --list                            # какие модели есть в Ollama

--file: задания через строку «---» (каждое — отдельный запрос). --context: файлы, которые подмешиваются в системный
промпт (канон, черновики жителей). Ответы пишутся в --out (Markdown) и печатаются кратко. Нужен запущенный Ollama
(http://localhost:11434). Модели с «-cloud» / «:cloud» считаются на серверах ollama.com, а не на этом ПК.
"""

import argparse
import json
import sys
import time
import urllib.request
from pathlib import Path

HOST = "http://localhost:11434"
DEFAULT_MODEL = "gemma4:31b-cloud"
SYSTEM = (
    "Ты помогаешь писать тексты для HD-2D игры «Долг Кошачьей Души» (пиксель-арт, мрачная сказка). "
    "Все персонажи — антропоморфные звери, людей в мире нет. Пиши по-русски, живо и коротко, без канцелярита "
    "и без эмодзи. Не выдумывай факты лора, которых нет в контексте: если нужно — помечай [ПРЕДЛОЖЕНИЕ]."
)


def call(model: str, system: str, prompt: str, temp: float, ctx: int) -> str:
    body = json.dumps({
        "model": model, "stream": False, "think": False,
        "messages": [{"role": "system", "content": system}, {"role": "user", "content": prompt}],
        "options": {"temperature": temp, "num_ctx": ctx},
    }).encode("utf-8")
    req = urllib.request.Request(HOST + "/api/chat", data=body, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=600) as r:
        return json.loads(r.read().decode("utf-8"))["message"]["content"].strip()


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("prompt", nargs="?", help="задание (или --file)")
    ap.add_argument("--file", help="файл с заданиями, разделитель — строка ---")
    ap.add_argument("--context", nargs="*", default=[], help="файлы-контекст (канон и т. п.)")
    ap.add_argument("--model", default=DEFAULT_MODEL)
    ap.add_argument("--n", type=int, default=1, help="вариантов на задание")
    ap.add_argument("--temp", type=float, default=0.8)
    ap.add_argument("--ctx", type=int, default=32768, help="окно контекста, токенов")
    ap.add_argument("--out", help="куда записать ответы (Markdown)")
    ap.add_argument("--list", action="store_true", help="показать модели Ollama")
    a = ap.parse_args()

    if a.list:
        with urllib.request.urlopen(HOST + "/api/tags", timeout=10) as r:
            for m in json.loads(r.read().decode("utf-8"))["models"]:
                print(m["name"], "(облако ollama.com)" if m.get("remote_host") else "(локально)")
        return

    tasks = []
    if a.file:
        tasks += [t.strip() for t in Path(a.file).read_text(encoding="utf-8").split("\n---\n") if t.strip()]
    if a.prompt:
        tasks.append(a.prompt)
    if not tasks:
        ap.error("нужно задание или --file")

    system = SYSTEM
    for f in a.context:
        system += f"\n\n=== {Path(f).name} ===\n" + Path(f).read_text(encoding="utf-8")

    out = [f"# Черновики ({a.model}, {time.strftime('%Y-%m-%d %H:%M')})\n"]
    for i, task in enumerate(tasks, 1):
        out.append(f"\n## Задание {i}\n\n> " + task.replace("\n", "\n> ") + "\n")
        for k in range(a.n):
            t0 = time.time()
            try:
                text = call(a.model, system, task, a.temp, a.ctx)
            except Exception as e:  # сеть, нет модели, Ollama не запущен
                text = f"(ошибка: {e})"
            out.append((f"\n### Вариант {k + 1}\n\n" if a.n > 1 else "\n") + text + "\n")
            print(f"задание {i}/{len(tasks)}, вариант {k + 1}: {len(text)} символов, {time.time() - t0:.0f} с",
                  file=sys.stderr)
    result = "".join(out)
    if a.out:
        Path(a.out).write_text(result, encoding="utf-8")
        print("записано:", a.out, file=sys.stderr)
    else:
        print(result)


if __name__ == "__main__":
    main()
