"""Prompts versionados em arquivo (A-03).

Formato de /prompts/<area>/<nome>.md:

    ---
    name: extraction.product_page
    version: 0.1.0
    task: extraction
    description: Extração de atributos de página de produto
    ---
    ## system
    Texto do system prompt.

    ## user
    Texto com variáveis {{nome_da_variavel}}.

prompt_version = "<name>@<version>#<sha256 do arquivo, 8 primeiros>". O hash expõe
edições feitas sem incremento de versão.
"""
from __future__ import annotations

import hashlib
import re
from dataclasses import dataclass
from pathlib import Path

from .errors import PromptError
from .types import Task

_VAR = re.compile(r"\{\{\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*\}\}")
_SECTION = re.compile(r"^##\s+(system|user)\s*$", re.MULTILINE)


@dataclass(frozen=True)
class PromptTemplate:
    name: str
    version: str
    task: Task
    description: str
    system: str
    user: str
    sha256: str

    @property
    def prompt_version(self) -> str:
        return f"{self.name}@{self.version}#{self.sha256[:8]}"

    @property
    def variables(self) -> set[str]:
        return set(_VAR.findall(self.system)) | set(_VAR.findall(self.user))

    def render(self, variables: dict[str, object]) -> tuple[str, str]:
        missing = self.variables - variables.keys()
        if missing:
            raise PromptError(f"{self.name}: variáveis ausentes {sorted(missing)}")

        def sub(text: str) -> str:
            return _VAR.sub(lambda m: str(variables[m.group(1)]), text)

        return sub(self.system), sub(self.user)


def parse_prompt(text: str, *, source: str) -> PromptTemplate:
    if not text.startswith("---\n"):
        raise PromptError(f"{source}: front matter ausente")
    try:
        header, body = text[4:].split("\n---\n", 1)
    except ValueError:
        raise PromptError(f"{source}: front matter não fechado") from None
    meta: dict[str, str] = {}
    for line in header.splitlines():
        if line.strip():
            key, _, value = line.partition(":")
            meta[key.strip()] = value.strip()
    for required in ("name", "version", "task"):
        if not meta.get(required):
            raise PromptError(f"{source}: campo '{required}' ausente no front matter")
    try:
        task = Task(meta["task"])
    except ValueError:
        raise PromptError(f"{source}: task inválida '{meta['task']}'") from None

    parts = _SECTION.split(body)
    sections = {parts[i]: parts[i + 1].strip() for i in range(1, len(parts) - 1, 2)}
    if "user" not in sections:
        raise PromptError(f"{source}: seção '## user' ausente")
    return PromptTemplate(
        name=meta["name"], version=meta["version"], task=task, description=meta.get("description", ""),
        system=sections.get("system", ""), user=sections["user"],
        sha256=hashlib.sha256(text.encode("utf-8")).hexdigest(),
    )


class PromptRegistry:
    """Resolve "area.nome" para /prompts/area/nome.md."""

    def __init__(self, prompts_dir: Path) -> None:
        self._dir = prompts_dir
        self._cache: dict[str, PromptTemplate] = {}

    def get(self, name: str) -> PromptTemplate:
        if name in self._cache:
            return self._cache[name]
        area, _, stem = name.partition(".")
        if not area or not stem:
            raise PromptError(f"Nome de prompt inválido: '{name}' (esperado 'area.nome')")
        path = self._dir / area / f"{stem}.md"
        if not path.exists():
            raise PromptError(f"Prompt não encontrado: {path}")
        template = parse_prompt(path.read_text(encoding="utf-8"), source=str(path))
        if template.name != name:
            raise PromptError(f"{path}: name '{template.name}' difere do caminho '{name}'")
        self._cache[name] = template
        return template
