
#!/usr/bin/python3

import os
import subprocess


rd = os.path.dirname(os.path.abspath(__file__))
dir = os.path.abspath(os.path.join(rd, ".."))
dockerDir = os.path.join(dir, "buildtools", "install", "docker")

print("Run local dns server")
os.environ["ROOT_DIR"] = dir
subprocess.run(["docker", "compose", "-f",
    os.path.join(dockerDir, "dnsmasq.yml"), "up", "-d"])