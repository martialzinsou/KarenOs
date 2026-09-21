# -*- coding: utf-8 -*-
"""Régénère les SVG UML de docs/WIKIPEDIA.md via l'API Kroki (rendu Mermaid)."""
import re, json, time, os, sys, urllib.request, urllib.error

HERE = os.path.dirname(os.path.abspath(__file__))
DOC = os.path.join(HERE, "..", "..", "WIKIPEDIA.md")
OUT = HERE

NAMES = [
    "karenos-composants-deploiement",
    "karenos-cas-utilisation",
    "karenos-classes",
    "karenos-sequence-inference",
    "karenos-etats-moteur",
    "karenos-sequence-chargement",
    "karenos-etats-agent",
    "karenos-activite-agent",
]


def render(code, tries=5):
    payload = json.dumps({
        "diagram_source": code,
        "diagram_type": "mermaid",
        "output_format": "svg",
    }).encode()
    for i in range(tries):
        req = urllib.request.Request(
            "https://kroki.io",
            data=payload,
            method="POST",
            headers={"Content-Type": "application/json", "User-Agent": "opencode-karenos/1.0"},
        )
        try:
            with urllib.request.urlopen(req, timeout=90) as r:
                return True, r.read()
        except urllib.error.HTTPError as e:
            if e.code in (500, 503) and i < tries - 1:
                time.sleep(2.5 * (i + 1))
                continue
            return False, (str(e.code) + " " + e.read().decode(errors="replace"))
        except Exception as e:
            if i < tries - 1:
                time.sleep(2.5 * (i + 1))
                continue
            return False, str(e)


def main():
    src = open(os.path.abspath(DOC), encoding="utf-8").read()
    blocks = re.findall(r"```mermaid\n(.*?)```", src, re.S)
    if len(blocks) != len(NAMES):
        sys.exit(f"ATTENTION : {len(blocks)} blocs mermaid pour {len(NAMES)} noms.")
    ok = 0
    for name, code in zip(NAMES, blocks):
        s, data = render(code)
        if not s:
            print(f"ERR {name}: {data[:150]}")
            continue
        with open(os.path.join(OUT, name + ".svg"), "wb") as f:
            f.write(data)
        ok += 1
        print(f"OK  {name}.svg  {len(data)} octets")
    print(f"\n{ok}/{len(blocks)} diagrammes régénérés")


if __name__ == "__main__":
    main()