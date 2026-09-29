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
        if info.get("expected") == "1":
            print("[start-after-migration] Migration succeeded, starting services...", file=sys.stderr)
            subprocess.run(["supervisorctl", "start", "all"], stdout=sys.stderr)
            print("[start-after-migration] All services started.", file=sys.stderr)
        else:
            print(f"[start-after-migration] Migration failed (expected={info.get('expected')}), services will not start.", file=sys.stderr)
    sys.stdout.write("RESULT 2\nOK")
    sys.stdout.flush()
