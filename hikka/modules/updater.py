# ©️ Dan Gazizullin, 2021-2023 
# This file is a part of Hikka Userbot (test3.1)
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
    """Manages updates and scheduled restarts for Hikka Userbot"""
    
    strings = {"name": "Updater"}

    def __init__(self):
        self.config = loader.ModuleConfig(
            loader.ConfigValue(
                "GIT_ORIGIN_URL",
                "https://github.com/i9opkas/Heroku_Vamhost",
                "URL of the git repository to fetch updates from",
                validator=loader.validators.Link(),
            ),
            loader.ConfigValue(
                "AUTO_RESTART",
                True,
                "Enable automatic restart when uptime reaches 24 hours",
                validator=loader.validators.Boolean(),
            )
        )
        self._restart_task: typing.Optional[asyncio.Task] = None

    @loader.command()
    async def restart(self, message: Message):
        args = utils.get_args_raw(message)
        secure_boot = any(trigger in args for trigger in {"--secure-boot", "-sb"})
        if (
            "-f" not in args
            and self.inline.init_complete
            and await self.inline.form(
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
            return
        
        await self.restart_common(message, secure_boot)

    async def inline_restart(self, call: InlineCall, secure_boot: bool = False):
        await self.restart_common(call, secure_boot)

    async def process_restart_message(self, msg_obj: typing.Union[InlineCall, Message]):
        self.set(
            "selfupdatemsg",
            (
                msg_obj.inline_message_id
                if hasattr(msg_obj, "inline_message_id")
                else f"{utils.get_chat_id(msg_obj)}:{msg_obj.id}"
            ),
        )

    async def restart_common(
        self,
        msg_obj: typing.Union[InlineCall, Message],
        secure_boot: bool = False,
    ):
        if secure_boot:
            self._db.set(loader.__name__, "secure_boot", True)

        message = (
            self.inline._units[msg_obj.form["uid"]]["message"]
            if hasattr(msg_obj, "form") and isinstance(msg_obj.form, dict)
            and "uid" in msg_obj.form and msg_obj.form["uid"] in self.inline._units
            and "message" in self.inline._units[msg_obj.form["uid"]]
            else msg_obj
        )

        msg_obj = await utils.answer(
            msg_obj,
            self.strings("restarting_caption").format(
                utils.get_platform_emoji()
                if self._client.hikka_me.premium and CUSTOM_EMOJIS and isinstance(msg_obj, Message)
                else "Heroku"
            ),
        )

        await self.process_restart_message(msg_obj)
        self.set("restart_ts", time.time())
        await self._db.remote_force_save()

        with contextlib.suppress(Exception):
            await main.hikka.web.stop()

        logging.getLogger().handlers[0].setLevel(logging.CRITICAL)

        for client in self.allclients:
            if client is not message.client:
                await client.disconnect()

        await message.client.disconnect()
        restart()

    async def download_common(self) -> bool:
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
            repo.create_head("V1.6.8.2", origin.refs.master)
            repo.heads.master.set_tracking_branch(origin.refs.master)
            repo.heads.master.checkout(True)
            return False

    @staticmethod
    def req_common():
        try:
            subprocess.run(
                [
                    sys.executable,
                    "-m",
                    "pip",
                    "install",
                    "-r",
                    os.path.join(os.path.dirname(utils.get_base_dir()), "requirements.txt"),
                    "--user",
                ],
                check=True,
            )
        except subprocess.CalledProcessError:
            logger.exception("Failed to install requirements")

    @loader.command()
    async def update(self, message: Message):
        args = utils.get_args_raw(message)
        current = utils.get_git_hash()
        upcoming = next(git.Repo().iter_commits(f"origin/{version.branch}", max_count=1)).hexsha
        if (
            "-f" not in args
            and self.inline.init_complete
            and await self.inline.form(
                message=message,
                text=(
                    self.strings("update_confirm").format(current, current[:8], upcoming, upcoming[:8])
                    if upcoming != current
                    else self.strings("no_update")
                ),
                reply_markup=[
                    {"text": self.strings("btn_update"), "callback": self.inline_update},
                    {"text": self.strings("cancel"), "action": "close"},
                ],
            )
        ):
            return
        
        await self.inline_update(message)

    async def inline_update(
        self,
        msg_obj: typing.Union[InlineCall, Message],
        hard: bool = False,
    ):
        if hard:
            os.system(f"cd {utils.get_base_dir()} && cd .. && git reset --hard HEAD")

        try:
            msg_obj = await utils.answer(msg_obj, self.strings("downloading"))
            req_update = await self.download_common()

            msg_obj = await utils.answer(msg_obj, self.strings("installing"))
            if req_update:
                self.req_common()

            await self.restart_common(msg_obj)
        except GitCommandError:
            if not hard:
                await self.inline_update(msg_obj, True)
                return
            logger.critical("Update loop detected. Please update manually via .terminal")

    @loader.command()
    async def source(self, message: Message):
        await utils.answer(
            message,
            self.strings("source").format(self.config["GIT_ORIGIN_URL"]),
        )

    async def client_ready(self):
        if self.get("selfupdatemsg") is not None:
            try:
                await self.update_complete()
            except Exception:
                logger.exception("Failed to complete update")

        if not self.get("do_not_create", False):
            try:
                await self._add_folder()
            except Exception:
                logger.exception("Failed to create Heroku folder")
            self.set("do_not_create", True)

        if self.config["AUTO_RESTART"]:
            self._restart_task = asyncio.ensure_future(self._monitor_uptime())

    async def _monitor_uptime(self):
        while True:
            await asyncio.sleep(120)  
            current_uptime = utils.uptime()
            if current_uptime >= 86400:  
                logger.info("Uptime reached 24 hours, initiating automatic restart")
                try:
                    await self.restart_common(None)
                except Exception:
                    logger.exception("Automatic restart failed")
                    break
            logger.debug(f"Current uptime: {current_uptime // 3600} hours")

    async def _add_folder(self):
        folders = await self._client(GetDialogFiltersRequest())
        if any(getattr(folder, "title", None) == "hikka" for folder in folders):
            return

        folder_id = max((folder.id for folder in folders if hasattr(folder, "id")), default=1) + 1

        try:
            await self._client(
                UpdateDialogFilterRequest(
                    folder_id,
                    DialogFilter(
                        folder_id,
                        title="hikka",
                        pinned_peers=(
                            [await self._client.get_input_entity(self._client.loader.inline.bot_id)]
                            if self._client.loader.inline.init_complete
                            else []
                        ),
                        include_peers=[
                            await self._client.get_input_entity(dialog.entity)
                            async for dialog in self._client.iter_dialogs(None, ignore_migrated=True)
                            if dialog.name in {
                                "heroku-logs",
                                "heroku-onload",
                                "heroku-assets",
                                "heroku-backups",
                                "heroku-acc-switcher",
                                "silent-tags",
                            }
                            and dialog.is_channel
                            and (
                                dialog.entity.participants_count == 1
                                or dialog.entity.participants_count == 2
                                and dialog.name in {"hikka-logs", "silent-tags"}
                            )
                            or (
                                self._client.loader.inline.init_complete
                                and dialog.entity.id == self._client.loader.inline.bot_id
                            )
                            or dialog.entity.id in [1554874075, 1697279580, 1679998924, 2410964167]
                        ],
                        emoticon="🐱",
                        exclude_peers=[],
                        contacts=False,
                        non_contacts=False,
                        groups=False,
                        broadcasts=False,
                        bots=False,
                        exclude_muted=False,
                        exclude_read=False,
                        exclude_archived=False,
                    ),
                )
            )
        except Exception:
            logger.critical("Failed to create Heroku folder due to Telegram limits or floodwait")

    async def update_complete(self):
        start = self.get("restart_ts")
        took = round(time.time() - start) if start else "n/a"
        msg = self.strings("success").format(utils.ascii_face(), took)
        ms = self.get("selfupdatemsg")

        if ":" in str(ms):
            chat_id, message_id = map(int, ms.split(":"))
            await self._client.edit_message(chat_id, message_id, msg)
        else:
            await self.inline.bot.edit_message_text(
                inline_message_id=ms,
                text=self.inline.sanitise_text(msg),
            )

    async def full_restart_complete(self, secure_boot: bool = False):
        start = self.get("restart_ts")
        took = round(time.time() - start) if start else "n/a"
        self.set("restart_ts", None)
        ms = self.get("selfupdatemsg")
        if ms is None:
            return

        msg = self.strings(
            "secure_boot_complete" if secure_boot else "full_success"
        ).format(utils.ascii_face(), took)
        self.set("selfupdatemsg", None)

        if ":" in str(ms):
            chat_id, message_id = map(int, ms.split(":"))
            await self._client.edit_message(chat_id, message_id, msg)
            await asyncio.sleep(60)
            await self._client.delete_messages(chat_id, message_id)
        else:
            await self.inline.bot.edit_message_text(
                inline_message_id=ms,
                text=self.inline.sanitise_text(msg),
        )
