#!/usr/bin/python3

import os
from git import Repo
from datetime import datetime

rd = os.path.dirname(os.path.abspath(__file__))
root_dir = os.path.abspath(os.path.join(rd, ".."))

CLIENT = "client"
SERVER = "server"
BUILDTOOLS = "buildtools"
REPO_CLIENT_URL = f"https://github.com/ONLYOFFICE/DocSpace-client"
REPO_SERVER_URL = f"https://github.com/ONLYOFFICE/DocSpace-server"
REPO_BUILDTOOLS_URL = f"https://github.com/ONLYOFFICE/DocSpace-buildtools"
LIMIT_DAYS = 30
MESSAGE_SEPARATOR = '__MESSAGE_SEPARATOR__'
SEP = '§'

# https://git-scm.com/docs/pretty-formats
format = f"%H{SEP}%as{SEP}%an{SEP}%s %b{MESSAGE_SEPARATOR}"

data = {}


def fetchCommits(url, type):
    path = os.path.join(root_dir, type)
    #print(path, os.path.exists(path))
    if os.path.exists(path) == False:
        print("Error folder does not exists", path)
        return
    
    repo = Repo(path)

    info = f"|<a href='{url}' target='_blank'>{type.upper()}</a>|<a href='{url}/tree/{repo.active_branch.name}' target='_blank'>{repo.active_branch.name}</a> |<a href='{url}/commit/{repo.head.commit}' target='_blank'>{repo.head.commit}</a>|{os.linesep}"

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

        if date not in data:
            data[date] = {}

        if name not in data[date]:
            data[date][name] = []

        data[date][name].append(f"- [{type}]: {text} <a href='{url}/{hash}' target='_blank'>`{hash[0:7]}`</a>")
    
    return info

result = f"## Changelog{os.linesep}"

result += f"| Repo | Branch | Last Commit |{os.linesep}"
result += f"| :--- | :---   | :---        |{os.linesep}"

result += fetchCommits(REPO_CLIENT_URL, CLIENT)
result += fetchCommits(REPO_SERVER_URL, SERVER)
result += fetchCommits(REPO_BUILDTOOLS_URL, BUILDTOOLS)

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