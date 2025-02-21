# ©️ Dan Gazizullin, 2021-2023
# This file is a part of Hikka Userbot
# 🌐 https://github.com/hikariatama/Hikka
# You can redistribute it and/or modify it under the terms of the GNU AGPLv3
# 🔑 https://www.gnu.org/licenses/agpl-3.0.html

import asyncio
import contextlib
import logging
import os
import time
import typing
import datetime
import git
from git import GitCommandError, Repo

from hikkatl.extensions.html import CUSTOM_EMOJIS
from hikkatl.tl.types import Message
from .. import loader, main, utils, version
from .._internal import restart
from ..inline.types import InlineCall

logger = logging.getLogger(__name__)

@loader.tds
class UpdaterMod(loader.Module):
    """Self-update module for Hikka"""

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
        asyncio.create_task(self.schedule_restart())

    async def schedule_restart(self):
        while True:
            now = datetime.datetime.utcnow() + datetime.timedelta(hours=3)
            next_run = now.replace(hour=0, minute=0, second=0, microsecond=0)
            if now >= next_run:
                next_run += datetime.timedelta(days=1)

            wait_time = (next_run - now).total_seconds()
            await asyncio.sleep(wait_time)

            logger.info("Performing scheduled restart...")
            await self.restart_common(None)

    @loader.command()
    async def restart(self, message: Message):
        args = utils.get_args_raw(message)
        secure_boot = any(trigger in args for trigger in {"--secure-boot", "-sb"})

        try:
            if (
                "-f" in args
                or not self.inline.init_complete
                or not await self.inline.form(
                    message=message,
                    text=self.strings(
                        "secure_boot_confirm" if secure_boot else "restart_confirm"
                    ),
                    reply_markup=[
                        {
                            "text": self.strings("btn_restart"),
                            "callback": self.inline_restart,
                            "args": (secure_boot,),
                        },
                        {"text": self.strings("cancel"), "action": "close"},
                    ],
                )
            ):
                raise
        except Exception:
            await self.restart_common(message, secure_boot)

    async def inline_restart(self, call: InlineCall, secure_boot: bool = False):
        await self.restart_common(call, secure_boot=secure_boot)

    async def restart_common(
        self,
        msg_obj: typing.Union[InlineCall, Message, None],
        secure_boot: bool = False,
    ):
        if secure_boot:
            self._db.set(loader.__name__, "secure_boot", True)

        self.set("restart_ts", time.time())
        await self._db.remote_force_save()

        if "LAVHOST" in os.environ:
            os.system("lavhost restart")
            return

        with contextlib.suppress(Exception):
            await main.hikka.web.stop()

        handler = logging.getLogger().handlers[0]
        handler.setLevel(logging.CRITICAL)

        if isinstance(msg_obj, Message):
            for client in self.allclients:
                if client is not msg_obj.client:
                    await client.disconnect()

            await msg_obj.client.disconnect()
        else:
            logger.warning("msg_obj is not a Message instance. Skipping client disconnect.")

        restart()

    async def download_common(self):
        try:
            repo = Repo(os.path.dirname(utils.get_base_dir()))
            origin = repo.remote("origin")
            r = origin.pull()
            new_commit = repo.head.commit
            for info in r:
                if info.old_commit:
                    for d in new_commit.diff(info.old_commit):
                        if d.b_path == "requirements.txt":
                            return True
            return False
        except git.exc.InvalidGitRepositoryError:
            repo = Repo.init(os.path.dirname(utils.get_base_dir()))
            origin = repo.create_remote("origin", self.config["GIT_ORIGIN_URL"])
            origin.fetch()
            repo.create_head("master", origin.refs.master)
            repo.heads.master.set_tracking_branch(origin.refs.master)
            repo.heads.master.checkout(True)
            return False

    @loader.command()
    async def update(self, message: Message):
        try:
            args = utils.get_args_raw(message)
            current = utils.get_git_hash()
            upcoming = next(
                git.Repo().iter_commits(f"origin/{version.branch}", max_count=1)
            ).hexsha
            if (
                "-f" in args
                or not self.inline.init_complete
                or not await self.inline.form(
                    message=message,
                    text=(
                        self.strings("update_confirm").format(
                            current, current[:8], upcoming, upcoming[:8]
                        )
                        if upcoming != current
                        else self.strings("no_update")
                    ),
                    reply_markup=[
                        {
                            "text": self.strings("btn_update"),
                            "callback": self.inline_update,
                        },
                        {"text": self.strings("cancel"), "action": "close"},
                    ],
                )
            ):
                raise
        except Exception:
            await self.inline_update(message)

    async def inline_update(self, msg_obj: typing.Union[InlineCall, Message], hard: bool = False):
        if hard:
            os.system(f"cd {utils.get_base_dir()} && cd .. && git reset --hard HEAD")

        try:
            if "LAVHOST" in os.environ:
                msg_obj = await utils.answer(
                    msg_obj,
                    self.strings("lavhost_update"),
                )
                os.system("lavhost update")
                return

            req_update = await self.download_common()

            if req_update:
                self.req_common()

            await self.restart_common(msg_obj)
        except GitCommandError:
            if not hard:
                await self.inline_update(msg_obj, True)
                return

            logger.critical("Update loop detected. Manual update required via .terminal")

    async def client_ready(self):
        if self.get("selfupdatemsg") is not None:
            try:
                await self.update_complete()
            except Exception:
                logger.exception("Failed to complete update!")

        if self.get("do_not_create", False):
            return

        self.set("do_not_create", True)

    async def update_complete(self):
        logger.debug("Self update successful! Editing message")
        start = self.get("restart_ts")
        try:
            took = round(time.time() - start)
        except Exception:
            took = "n/a"

        msg = self.strings("success").format(utils.ascii_face(), took)
        ms = self.get("selfupdatemsg")

        if ":" in str(ms):
            chat_id, message_id = ms.split(":")
            chat_id, message_id = int(chat_id), int(message_id)
            await self._client.edit_message(chat_id, message_id, msg)
            return

        await self.inline.bot.edit_message_text(
            inline_message_id=ms,
            text=self.inline.sanitise_text(msg),
)
