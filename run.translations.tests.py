import os
import subprocess

sd = os.path.dirname(os.path.abspath(__file__))
dir = os.path.abspath(os.path.join(sd, ".."))
clientDir = os.path.abspath(os.path.join(dir, "client"))
projFile = os.path.abspath(os.path.join(clientDir, "common", "Tests",
                                        "Frontend.Translations.Tests", "Frontend.Translations.Tests.csproj"))
resultDir = os.path.abspath(os.path.join(dir, "TestsResults"))

print("Script directory:", sd)
print("Root directory:", dir)

print(f"== Run {projFile} ==")
subprocess.run(["dotnet", "test", projFile, "--filter", "TestCategory=Locales",
               "-l:html", "--results-directory", resultDir, "--environment", f"BASE_DIR={clientDir}"])
