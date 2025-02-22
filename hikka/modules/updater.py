# ©️ Dan Gazizullin, 2021-2023
# This file is a part of Hikka Userbot
# 🌐 https://github.com/hikariatama/Hikka
# You can redistribute it and/or modify it under the terms of the GNU AGPLv3
# 🔑 https://www.gnu.org/licenses/agpl-3.0.html

import asyncio
import contextlib
import logging
import os
import subprocess
import sys
import time
import typing

import git
from git import GitCommandError, Repo
from hikkatl.extensions.html import CUSTOM_EMOJIS
from hikkatl.tl.functions.messages import (
    GetDialogFiltersRequest,
    UpdateDialogFilterRequest,
)
from hikkatl.tl.types import DialogFilter, Message

from .. import loader, main, utils, version
from .._internal import restart
from ..inline.types import InlineCall

logger = logging.getLogger(__name__)


@loader.tds
class UpdaterMod(loader.Module):
    """Updates itself"""

    strings = {"name": "Updater"}

    def __init__(self):
        self.config = loader.ModuleConfig(
            loader.ConfigValue(
                "GIT_ORIGIN_URL",
                "https://github.com/i9opkas/Heroku_Vamhost",
                lambda: self.strings("origin_cfg_doc"),
                validator=loader.validators.Link(),
            )
        )

    async def download_common(self):
        try:
            repo_path = os.path.dirname(utils.get_base_dir())
            repo = Repo(repo_path)

            # Выполняем команду обновления через git checkout + pull
            subprocess.run(
                ["git", "checkout", "origin/master"],
                cwd=repo_path,
                check=True,
            )
            subprocess.run(
                ["git", "pull", "origin", "master"],
                cwd=repo_path,
                check=True,
            )

            # Проверяем изменения в requirements.txt
            new_commit = repo.head.commit
            for d in new_commit.diff("HEAD~1"):
                if d.b_path == "requirements.txt":
                    return True
            return False
        except (git.exc.InvalidGitRepositoryError, subprocess.CalledProcessError) as e:
            logger.error(f"Git update error: {e}")
            return False

    @staticmethod
    def req_common():
        """Установка новых зависимостей, если они появились"""
        logger.debug("Installing new requirements...")
        try:
            subprocess.run(
                [
                    sys.executable,
                    "-m",
                    "pip",
                    "install",
                    "-r",
                    os.path.join(
                        os.path.dirname(utils.get_base_dir()),
                        "requirements.txt",
                    ),
                    "--user",
                ],
                check=True,
            )
        except subprocess.CalledProcessError:
            logger.exception("Req install failed")

    async def inline_update(
        self,
        msg_obj: typing.Union[InlineCall, Message],
        hard: bool = False,
    ):
        """Основной процесс обновления"""
        if hard:
            os.system(f"cd {utils.get_base_dir()} && cd .. && git reset --hard HEAD")

        try:
            if "LAVHOST" in os.environ:
                msg_obj = await utils.answer(
                    msg_obj,
                    self.strings("lavhost_update").format("lavHost"),
                )
                await self.process_restart_message(msg_obj)
                os.system("lavhost update")
                return

            with contextlib.suppress(Exception):
                msg_obj = await utils.answer(msg_obj, self.strings("downloading"))

            req_update = await self.download_common()

            with contextlib.suppress(Exception):
                msg_obj = await utils.answer(msg_obj, self.strings("installing"))

            if req_update:
                self.req_common()

            await self.restart_common(msg_obj)
        except GitCommandError:
            if not hard:
                await self.inline_update(msg_obj, True)
                return

            logger.critical("Got update loop. Update manually via .terminal")
