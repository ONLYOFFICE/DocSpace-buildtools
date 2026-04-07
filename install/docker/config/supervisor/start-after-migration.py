import sys
import subprocess

while True:
    sys.stdout.write("READY\n")
    sys.stdout.flush()
    if not (header := sys.stdin.readline()):
        break
    payload = sys.stdin.read(int(dict(t.split(":") for t in header.split() if ":" in t).get("len", 0)))
    info = dict(t.split(":") for t in payload.split() if ":" in t)
    if info.get("processname") == "ASC.Migration.Runner":
        if info.get("exitcode") == "0":
            subprocess.run(["supervisorctl", "start", "all"], stdout=sys.stderr)
        else:
            print(f"Migration failed (exit code {info.get('exitcode')}), services will not start.", file=sys.stderr)
    sys.stdout.write("RESULT 2\nOK")
    sys.stdout.flush()
