import os
import re
import subprocess
from typing import List, Optional

# File extensions to exclude (localization, config files, etc.)
EXCLUDED_FILES = {".json", ".p7s", ".cjs", ".po", ".license", ".xml", ".resx"}

# Regex patterns
COMMENT_REGEX = re.compile(r"(?://|#|<!--|/\*|\*).+")  # Matches comments in various languages
NON_ASCII_REGEX = re.compile(r"[^\x00-\x7F]")  # Matches non-ASCII characters


def get_base_branch() -> str:
    """
    Retrieves the base branch for the pull request.
    Defaults to 'master' if running outside a CI environment.
    """
    return os.getenv("GITHUB_BASE_REF", "master")


def get_changed_files(base_branch: str) -> List[str]:
    """
    Fetches the list of changed files in the PR.
    Filters out files with extensions in EXCLUDED_FILES.
    """
    print(f"Checking diff against: {base_branch}")

    try:
        subprocess.run(["git", "fetch", "origin", base_branch], check=True)

        result = subprocess.run(
            ["git", "diff", "--name-only", f"origin/{base_branch}"],
            capture_output=True,
            text=True,
            check=True
        )

        changed_files = result.stdout.splitlines()

        # Exclude files with certain extensions
        included_files = [f for f in changed_files if not f.endswith(tuple(EXCLUDED_FILES))]

        if not included_files:
            print("No files to check (all excluded).")
            return []

        return included_files

    except subprocess.CalledProcessError as e:
        print(f"Error fetching changed files: {e}")
        return []


def get_diff(included_files: List[str], base_branch: str) -> Optional[str]:
    """
    Retrieves the Git diff of the included files.
    """
    if not included_files:
        return None

    try:
        result = subprocess.run(
            ["git", "diff", "--unified=0", f"origin/{base_branch}", "--"] + included_files,
            capture_output=True,
            text=True,
            check=True
        )
        return result.stdout if result.stdout else None

    except subprocess.CalledProcessError as e:
        print(f"Error running git diff: {e}")
        return None


def extract_comments(diff_output: str) -> List[str]:
    """
    Extracts comments from the diff output.
    """
    return [
        line[1:].strip()
        for line in diff_output.split("\n")
        if line.startswith("+") and not line.startswith("+++") and COMMENT_REGEX.search(line)
    ]


def detect_non_ascii_comments(comments: List[str]) -> List[str]:
    """
    Identifies comments that contain non-ASCII characters.
    """
    return [comment for comment in comments if NON_ASCII_REGEX.search(comment)]


def main():
    base_branch = get_base_branch()
    changed_files = get_changed_files(base_branch)

    diff_output = get_diff(changed_files, base_branch)
    if not diff_output:
        print("No changes to check.")
        return

    comments = extract_comments(diff_output)
    if not comments:
        print("No comments found in changes.")
        return

    non_ascii_comments = detect_non_ascii_comments(comments)
    if non_ascii_comments:
        print("Found comments with non-ASCII characters in the following files:")
        for comment in non_ascii_comments:
            print(f"- {comment}")
        exit(1)

    print("All comments contain only ASCII characters.")


if __name__ == "__main__":
    main()
