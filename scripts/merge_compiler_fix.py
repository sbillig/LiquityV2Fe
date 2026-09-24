"""Replay pinned compiler merges, including the reviewed PR #1567 import conflict."""
from pathlib import Path
import subprocess


def merge_fix(compiler: Path, fix: dict):
    result = subprocess.run(['git', 'merge', '--no-ff', '--no-edit', fix['branch']], cwd=compiler)
    if result.returncode == 0:
        return
    if fix.get('merge_resolution') != 'payable_return_imports':
        raise RuntimeError(f"Compiler merge failed: {fix['branch']}")
    path = 'crates/mir/src/verify/package.rs'
    unmerged = subprocess.check_output(
        ['git', 'diff', '--name-only', '--diff-filter=U'], cwd=compiler, text=True).splitlines()
    assert unmerged == [path], f'Unexpected compiler conflicts: {unmerged}'
    source = compiler / path
    content = source.read_text()
    conflict = (
        '<<<<<<< HEAD\n'
        '        RuntimeFunctionOwner, RuntimeLinkage, RuntimeObject, RuntimePackage, RuntimeProgramView,\n'
        '=======\n'
        '        RuntimeFunctionOwner, RuntimeObject, RuntimePackage, RuntimeProgramView, RuntimeReturnPlan,\n'
        f">>>>>>> {fix['branch']}\n"
    )
    assert content.count(conflict) == 1 and content.count('<<<<<<<') == 1, 'Unexpected import conflict'
    content = content.replace(conflict,
        '        RuntimeFunctionOwner, RuntimeLinkage, RuntimeObject, RuntimePackage, RuntimeProgramView,\n'
        '        RuntimeReturnPlan,\n')
    source.write_text(content)
    subprocess.run(['git', 'add', path], cwd=compiler, check=True)
    subprocess.run(['git', 'commit', '--no-edit'], cwd=compiler, check=True)
