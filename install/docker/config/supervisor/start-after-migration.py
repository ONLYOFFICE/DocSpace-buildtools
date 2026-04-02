import sys
import subprocess

while True:
    sys.stdout.write("READY\n")
    sys.stdout.flush()
    header = sys.stdin.readline()
    length = int(dict(t.split(":") for t in header.split() if ":" in t).get("len", 0))
    sys.stdin.read(length)
    subprocess.run(["supervisorctl", "start", "all"], stdout=sys.stderr)
    sys.stdout.write("RESULT 2\nOK")
    sys.stdout.flush()
