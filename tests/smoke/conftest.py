import os

_results = []

def pytest_configure(config):
    config.addinivalue_line('markers', 'bootstrap: settings, wizard and auth — needed by every phase')
    config.addinivalue_line('markers', 'seed: creates data to be verified after a restart or an update')
    config.addinivalue_line('markers', 'verify: checks data created by the seed phase')
    config.addinivalue_line('markers', 'restore: restores a backup, which invalidates all passwords; run it last')

def pytest_runtest_logreport(report):
    # record the call phase, and setup when it already failed or skipped the test
    if report.when != 'call' and not (report.when == 'setup' and report.outcome != 'passed'):
        return
    note = ''
    if report.skipped and isinstance(report.longrepr, tuple):
        note = str(report.longrepr[2]).removeprefix('Skipped: ')
    elif report.failed:
        lines = report.longreprtext.strip().splitlines()
        # the first "E" line holds the exception, the last line only its location
        errors = [line[1:].strip() for line in lines if line.startswith('E ')]
        note = errors[0] if errors else (lines[-1] if lines else '')
    _results.append((report.nodeid.split('::', 1)[-1], report.outcome, report.duration, note))

TITLE_WIDTH = 34

def pad(text, width):
    """Pad with non-breaking spaces: Markdown collapses regular ones."""
    return text + '&nbsp;' * max(0, width - len(text))

def format_duration(seconds):
    minutes, rest = divmod(round(seconds), 60)
    return f"{minutes}m {rest}s" if minutes else f"{rest}s"

def pytest_sessionfinish(session):
    summary_path = os.environ.get('SMOKE_SUMMARY_FILE')
    if not summary_path or not _results:
        return
    failed = [item for item in _results if item[1] == 'failed']
    skipped = [item for item in _results if item[1] == 'skipped']
    passed = [item for item in _results if item[1] == 'passed']
    total = format_duration(sum(item[2] for item in _results))
    columns = [pad(total, 6),
               pad(f"✅ {len(passed)} passed", 11),
               pad(f"⏭️ {len(skipped)} skipped" if skipped else '', 12),
               f"❌ {len(failed)} failed" if failed else '']
    title = f"{pad(os.environ.get('SMOKE_SUMMARY_TITLE', 'Smoke test'), TITLE_WIDTH)} — {' '.join(columns)}".rstrip()
    # one line per run; opened only when a test failed
    lines = [f"<details{' open' if failed else ''}><summary><code>{title}</code></summary>", '']
    if failed:
        lines += ['| Failed test | Time | Note |', '|---|---|---|']
        for name, _, duration, note in failed:
            escaped = note.replace('|', '\\|')[:200]
            lines.append(f"| `{name}` | {format_duration(duration)} | {escaped} |")
        lines.append('')
    for name, outcome, duration, note in _results:
        if outcome == 'passed':
            lines.append(f"- ✅ `{name}` ({format_duration(duration)})")
        elif outcome == 'skipped':
            lines.append(f"- ⏭️ `{name}` — {note}")
    lines += ['', '</details>', '']
    with open(summary_path, 'a', encoding='utf-8') as summary:
        summary.write('\n'.join(lines) + '\n')
