"""Gera os tokens de design para o app (Dart) e o site (CSS) a partir de tokens.json.

Uso (na raiz do repositório):  python scripts/generate_tokens.py [--check]
Com --check, não escreve nada e falha se os arquivos gerados estiverem desatualizados.
"""

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "packages" / "design-tokens" / "tokens.json"
DART_OUT = ROOT / "apps" / "mobile" / "lib" / "app" / "theme" / "tokens.g.dart"
CSS_OUT = ROOT / "apps" / "web" / "src" / "styles" / "tokens.css"
HEADER = "GERADO por scripts/generate_tokens.py a partir de packages/design-tokens/tokens.json. Não edite."


def _camel(name: str) -> str:
    parts = name.split("-")
    head = parts[0]
    if head[0].isdigit():  # "2xl" não é um identificador Dart válido
        head = "x" + head
    return head + "".join(p[:1].upper() + p[1:] for p in parts[1:])


def _dart(tokens: dict) -> str:
    lines = [f"// {HEADER}", "// ignore_for_file: constant_identifier_names", "",
             "import 'dart:ui';", ""]

    lines.append("abstract final class EvoColors {")
    for name, hex_value in tokens["color"].items():
        lines.append(f"  static const {_camel(name)} = Color(0xFF{hex_value.lstrip('#').upper()});")
    lines.append("}")

    for cls, key in (("EvoSpace", "space"), ("EvoRadius", "radius"), ("EvoFontSize", "font-size")):
        lines += ["", f"abstract final class {cls} {{"]
        lines += [f"  static const double {_camel(n)} = {v};" for n, v in tokens[key].items()]
        lines.append("}")

    lines += ["", "abstract final class EvoMotion {"]
    lines += [f"  static const {_camel(n)} = Duration(milliseconds: {v});"
              for n, v in tokens["motion"].items()]
    lines.append("}")
    lines += ["", f"const double evoTouchTargetMin = {tokens['touch-target-min']};", ""]
    return "\n".join(lines)


def _css(tokens: dict) -> str:
    lines = [f"/* {HEADER} */", "", "@theme {"]
    lines += [f"  --color-{n}: {v};" for n, v in tokens["color"].items()]
    lines += [f"  --spacing-{n}: {v / 16}rem;" for n, v in tokens["space"].items()]
    lines += [f"  --radius-{n}: {v}px;" for n, v in tokens["radius"].items()]
    lines += [f"  --text-{n}: {v / 16}rem;" for n, v in tokens["font-size"].items()]
    lines += [f"  --duration-{n}: {v}ms;" for n, v in tokens["motion"].items()]
    lines += ["}", ""]
    return "\n".join(lines)


def main() -> int:
    tokens = json.loads(SOURCE.read_text(encoding="utf-8"))
    outputs = {DART_OUT: _dart(tokens), CSS_OUT: _css(tokens)}
    check = "--check" in sys.argv
    stale = []
    for path, content in outputs.items():
        current = path.read_text(encoding="utf-8") if path.exists() else None
        if current == content:
            continue
        if check:
            stale.append(path)
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content, encoding="utf-8", newline="\n")
            print(f"gerado: {path.relative_to(ROOT)}")
    if stale:
        print("Tokens desatualizados:", *(str(p.relative_to(ROOT)) for p in stale), sep="\n  ")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
