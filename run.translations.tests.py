import os
import subprocess
import shutil
from datetime import datetime
import webbrowser


def check_node_installed():
    try:
        subprocess.run(["node", "--version"], check=True,
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        print("Node.js is installed.")
    except subprocess.CalledProcessError:
        print("Node.js could not be found.")
        webbrowser.open("https://nodejs.org/en/download/package-manager")
        exit(1)


def main():
    check_node_installed()

    # Get the root directory
    script_dir = os.path.dirname(os.path.abspath(__file__))
    root_dir = os.path.abspath(os.path.join(script_dir, ".."))

    # Change to the tests directory
    tests_dir = os.path.join(root_dir, "client", "common", "tests")
    os.chdir(tests_dir)

    # Run npm install
    subprocess.run(["npm", "install"], check=True)

    # Run npm test:locales
    subprocess.run(["npm", "run", "test:locales"], check=False)

    # Generate the output file name
    now = datetime.now()
    output_file = os.path.join(root_dir, "TestsResults", f"TestResult__{
                               now.strftime('%Y%m%d_%H%M%S')}.html")

    # Copy the test results to the output file
    shutil.copyfile(os.path.join(tests_dir, "reports",
                    "tests-results.html"), output_file)

    print("Results saved to:", output_file)

    # Open the output file in the default web browser
    webbrowser.open(output_file)

    # Pause the script
    input("Press Enter to continue...")


if __name__ == "__main__":
    main()
