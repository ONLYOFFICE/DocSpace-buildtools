import os
from github import Github
import requests
import shutil

rd = os.path.dirname(os.path.abspath(__file__))
dir = os.path.abspath(os.path.join(rd, ".."))
publicDir = os.path.join(dir, "client/public")
g = Github()
repo = g.get_repo("ONLYOFFICE/ASC.Web.Campaigns")
repoFolder = "src/campaigns"

def download(c, out):
    r = requests.get(c.download_url)
    output_path = f'{out}/{c.path}'
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    with open(output_path, 'wb') as f:
        f.write(r.content)


def download_folder(repo, folder, out, recursive):
    contents = repo.get_contents(folder)
    for c in contents:
        if c.download_url is None:
            if recursive:
                download_folder(repo, c.path, out, recursive)
            continue
        download(c, out)

def move_folder():
    srcPath = publicDir + "/src"
    campaignsPath = srcPath + "/campaigns"
    newPath = publicDir + "/campaigns"
    shutil.move(campaignsPath, newPath)
    shutil.rmtree(srcPath)

download_folder(repo, repoFolder, publicDir, True)
move_folder()
print("It's OK")