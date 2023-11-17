import os
import subprocess
import sys
import getopt


def help():
    # Display Help
    print("Run spellcheck tests.")
    print()
    print("Syntax: available params [-h|s")
    print("options:")
    print("h     Print this Help.")
    print("s     Force save.")
    print()


force = False

# Get the options
opts, args = getopt.getopt(sys.argv[1:], "hf")
for opt, arg in opts:
    if opt == "-h":
        help()
        sys.exit()
    elif opt == "-f":
        force = arg if arg else True
    else:
        print("Error: Invalid '-" + opt + "' option")
        sys.exit()

sd = os.path.dirname(os.path.abspath(__file__))
dir = os.path.abspath(os.path.join(sd, ".."))
clientDir = os.path.abspath(os.path.join(dir, "client"))
projFile = os.path.abspath(os.path.join(clientDir, "common", "Tests",
                                        "Frontend.Translations.Tests", "Frontend.Translations.Tests.csproj"))
resultDir = os.path.abspath(os.path.join(dir, "TestsResults"))

print("Script directory:", sd)
print("Root directory:", dir)

print("FORCE SAFE:", force)  # --environment "SAVE=$save"

print(f"== Run {projFile} ==")
subprocess.run(["dotnet", "test", projFile, "--filter", "Name~SpellCheckTest",
               "-l:html", "--results-directory", resultDir, "--environment", f"BASE_DIR={clientDir}", "--environment", f"SAVE={force}"])
