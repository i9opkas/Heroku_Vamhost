"""Represents current userbot version"""
# ©️ Dan Gazizullin, 2021-2023 (test1)
# This file is a part of Hikka Userbot
# 🌐 https://github.com/hikariatama/Hikka
# You can redistribute it and/or modify it under the terms of the GNU AGPLv3
# 🔑 https://www.gnu.org/licenses/agpl-3.0.html

__version__ = (1, 6, 8, 1)  # Виправлена крапка на кому

import os

try:
    import git

    repo_path = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    repo = git.Repo(path=repo_path, search_parent_directories=True)

    if repo.bare:
        branch = "unknown"
    else:
        branch = repo.active_branch.name

except (ImportError, AttributeError, ValueError):
    branch = "master"
