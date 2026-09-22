#!/usr/bin/python3

import os
from github import Auth, Github, GithubException
from git import Repo
from datetime import datetime, timedelta, timezone

rd = os.path.dirname(os.path.abspath(__file__))
root_dir = os.path.abspath(os.path.join(rd, ".."))

CLIENT = "client"
SERVER = "server"
BUILDTOOLS = "buildtools"
UI_KIT = "ui-kit"
REPO_CLIENT_URL = f"https://github.com/ONLYOFFICE/DocSpace-client"
REPO_SERVER_URL = f"https://github.com/ONLYOFFICE/DocSpace-server"
REPO_BUILDTOOLS_URL = f"https://github.com/ONLYOFFICE/DocSpace-buildtools"
# The ui-kit is consumed as a prebuilt tarball, so unlike the repositories above
# it is not checked out anywhere in this image and is read over the GitHub API.
UI_KIT_REPO = "ONLYOFFICE/docspace-ui-kit-react"
REPO_UI_KIT_URL = f"https://github.com/{UI_KIT_REPO}"
# Both are set by the Dockerfile stage that clones the sources, so the changelog
# follows the same branch as the build. git_clone there falls back the same way.
GIT_BRANCH = os.environ.get("GIT_BRANCH", "master")
FALLBACK_BRANCH = os.environ.get("FALLBACK_BRANCH", "develop")
LIMIT_DAYS = 30
MESSAGE_SEPARATOR = '__MESSAGE_SEPARATOR__'
SEP = '§'

# https://git-scm.com/docs/pretty-formats
format = f"%H{SEP}%as{SEP}%an{SEP}%s %b{MESSAGE_SEPARATOR}"

data = {}


def repoRow(url, branch, commit):
    name = url.rstrip("/").rsplit("/", 1)[-1]
    return f"| [{name}]({url})  | [{branch}]({url}/tree/{branch})  | [{commit}]({url}/commit/{commit}) |{os.linesep}"


def addCommit(url, type, hash, date, name, text):
    if date not in data:
        data[date] = {}

    if name not in data[date]:
        data[date][name] = []

    data[date][name].append(f"- [{type}]: {text} [`{hash[0:7]}`]({url}/commit/{hash})")


def fetchCommits(url, type):
    path = os.path.join(root_dir, type)
    #print(path, os.path.exists(path))
    if os.path.exists(path) == False:
        print("Error folder does not exists", path)
        return ""
    
    repo = Repo(path)

    info = repoRow(url, repo.active_branch.name, repo.head.commit)

    commits_str = repo.git.log(f"--pretty=format: {format}", "--no-merges", f"--since={LIMIT_DAYS}.days")
    #print(commits_str)

    commits = commits_str.strip().split(MESSAGE_SEPARATOR)
    #print(commits)

    for item in commits:
        elements = item.replace('\n', '').split(SEP)

        if len(elements) != 4:
            continue

        hash = elements[0].strip()
        date = datetime.strptime(elements[1].strip(), "%Y-%m-%d")
        name = elements[2].strip()
        text = elements[3].strip().capitalize()

        addCommit(url, type, hash, date, name, text)
    
    return info


def fetchCommitsFromApi(url, type, repo_name):
    # A missing or rate-limited GitHub must not fail the build: the changelog
    # loses this repository's section, everything else is still generated.
    try:
        token = os.environ.get("GITHUB_TOKEN")
        github = Github(auth=Auth.Token(token)) if token else Github()
        repo = github.get_repo(repo_name)

        try:
            branch = repo.get_branch(GIT_BRANCH)
        except GithubException:
            branch = repo.get_branch(FALLBACK_BRANCH)

        info = repoRow(url, branch.name, branch.commit.sha)

        since = datetime.now(timezone.utc) - timedelta(days=LIMIT_DAYS)

        for item in repo.get_commits(sha=branch.name, since=since):
            # The local repositories are read with --no-merges; match that.
            if len(item.parents) > 1:
                continue

            commit = item.commit
            hash = item.sha
            date = datetime.strptime(commit.author.date.strftime("%Y-%m-%d"), "%Y-%m-%d")
            name = commit.author.name
            text = " ".join(commit.message.split()).capitalize()

            addCommit(url, type, hash, date, name, text)

        return info
    except Exception as error:
        print(f"Error could not read {repo_name} over the GitHub API:", error)
        return ""

result = f"## Changelog{os.linesep}"

result += f"| Repo | Branch | Last Commit |{os.linesep}"
result += f"| :- | :- | :- |{os.linesep}"

result += fetchCommits(REPO_CLIENT_URL, CLIENT)
result += fetchCommits(REPO_SERVER_URL, SERVER)
result += fetchCommits(REPO_BUILDTOOLS_URL, BUILDTOOLS)
result += fetchCommitsFromApi(REPO_UI_KIT_URL, UI_KIT, UI_KIT_REPO)

# Create debuginfo.md content
for date in sorted(data, reverse=True):     
    niceDate = date.strftime("%d %B %Y")
    result += f"### {niceDate}{os.linesep}"
    for name in sorted(data[date]):
        result += f"#### {name}{os.linesep}"
        for commit in data[date][name]:
            result += f"{commit}{os.linesep}"

print(result)

pathMD = os.path.join(root_dir, CLIENT, "public/debuginfo.md")
# Open text file in write mode
text_file = open(pathMD, "w")

# Write content to file
n = text_file.write(result)

if n == len(result):
    print("Success! String written to text file.")
else:
    print("Failure! String not written to text file.")

# Close file
text_file.close()
