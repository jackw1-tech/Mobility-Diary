import ast
from pathlib import Path


MOBILITY_ROOT = Path(__file__).resolve().parents[1]


def _python_files(*parts: str) -> list[Path]:
    root = MOBILITY_ROOT.joinpath(*parts)
    if root.is_file():
        return [root]
    return [
        path
        for path in root.rglob("*.py")
        if "__pycache__" not in path.parts and "migrations" not in path.parts
    ]


def _imports(path: Path):
    tree = ast.parse(path.read_text())
    for node in ast.walk(tree):
        if isinstance(node, ast.ImportFrom):
            yield node


def test_api_modules_do_not_import_private_task_or_api_helpers():
    api_files = _python_files("api.py") + _python_files("ingestion", "api.py")

    violations = []
    for path in api_files:
        for node in _imports(path):
            module = node.module or ""
            imports_private_name = any(alias.name.startswith("_") for alias in node.names)
            imports_task_or_api = module.endswith("tasks") or module.endswith("api")
            if imports_private_name and imports_task_or_api:
                violations.append((path, module, [alias.name for alias in node.names]))

    assert violations == []


def test_services_and_selectors_do_not_import_api_modules():
    checked_files = (
        _python_files("services")
        + _python_files("selectors")
        + _python_files("ingestion", "services.py")
        + _python_files("ingestion", "selectors.py")
    )

    violations = []
    for path in checked_files:
        for node in _imports(path):
            module = node.module or ""
            if module.endswith("api"):
                violations.append((path, module))

    assert violations == []
