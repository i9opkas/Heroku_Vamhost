# ©️ Dan Gazizullin, 2021-2023
# This file is a part of Hikka Userbot
# 🌐 https://github.com/hikariatama/Hikka
# You can redistribute it and/or modify it under the terms of the GNU AGPLv3
# 🔑 https://www.gnu.org/licenses/agpl-3.0.html

import contextlib
import itertools
import os
import subprocess
import sys
import tempfile
import time
import typing
from types import ModuleType

import hikkatl
from hikkatl.errors.rpcerrorlist import MessageIdInvalidError
from hikkatl.sessions import StringSession
from hikkatl.tl.types import Message
from meval import meval

from .. import loader, main, utils
from ..log import HikkaException

class Brainfuck:
    def __init__(self, memory_size: int = 30000):
        if memory_size < 0:
            raise ValueError("memory size cannot be negative")

        self._data = [0] * memory_size
        self.out = ""
        self.error = None

    @property
    def data(self):
        return self._data

    def run(self, code: str) -> str:
        self.out = ""
        had_error = self._eval(code)

        if had_error:
            return ""

        self._interpret(code)
        return self.out

    def _report_error(
        self,
        message: str,
        line: typing.Optional[int] = None,
        column: typing.Optional[int] = None,
    ):
        self.error = (
            message + f" at line {line}, column {column}"
            if line is not None and column is not None
            else ""
        )

    def _eval(self, source: str):
        line = col = 0

        stk = []

        loop_open = False

        for c in source:
            if c == "[":
                if loop_open:
                    self._report_error("unexpected token '['", line, col)
                    return True

                loop_open = True
                stk.append("[")
            elif c == "]":
                loop_open = False
                if len(stk) == 0:
                    self._report_error("unexpected token ']'", line, col)
                    return True

                stk.pop()
            elif c == "\n":
                line += 1
                col = -1

            col += 1

        if len(stk) != 0:
            self._report_error("unmatched brackets")
            return True

        return False

    def _interpret(self, source: str):
        line = col = ptr = current = 0

        while current < len(source):
            if source[current] == ">":
                if ptr == (len(self.data) - 1):
                    self._report_error("pointer out of range", line, col)
                    return True

                ptr += 1
            elif source[current] == "<":
                if ptr == 0:
                    self._report_error("pointer out of range", line, col)
                    return True

                ptr -= 1
            elif source[current] == "+":
                if self.data[ptr] >= 2**32:
                    self._report_error("cell overflow")
                    return True

                self.data[ptr] += 1

            elif source[current] == "-":
                if self.data[ptr] == 0:
                    self._report_error("cell underflow")
                    return True

                self.data[ptr] -= 1
            elif source[current] == ".":
                self.out += chr(self.data[ptr])
            elif source[current] == "[":
                if self.data[ptr] == 0:
                    while source[current] != "]":
                        current += 1
            elif source[current] == "]":
                if self.data[ptr] != 0:
                    while source[current] != "[":
                        current -= 1
            elif source[current] == "\n":
                line += 1
                col = -1

            col += 1
            current += 1

        return False

@loader.tds
class Evaluator(loader.Module):
    """Evaluates code in various languages"""

    strings = {
        "name": "Evaluator",
        "compiling": "<b>Compiling...</b>",
        "no_compiler": "<emoji document_id={}>❌</emoji> <b>{} is not installed or unavailable</b>",
        "eval": "💾 Код вернул:\n<pre><code class=\"language-{}\">{}</code></pre>\n⏳ Выполнен за {} секунд",
        "err": "💾 Код вернул:\n<emoji document_id=5440381017384822513>🚫</emoji> Ошибка:\n<pre><code class=\"language-{}\">{}</code></pre>\n⏳ Выполнен за {} секунд",
    }

    blocked_commands = [
        "kill", "exit", "nc", "netcat", "ncat", "socat", "perl", "ruby", "php",
        "msfvenom", "metasploit", "weevely", "empire", "pupy", "sliver", "havoc",
        "meterpreter", "evil-winrm", "ligolo", "chisel", "frp", "fast-reverse-proxy",
        "shell", "socket", "reverse", "session", "rm", "os.system", "subprocess",
        "exec", "eval"
    ]

    @loader.command(alias="eval")
    async def e(self, message: Message):
        code = utils.get_args_raw(message)
        start_time = time.perf_counter()

        if any(blocked_cmd in code.lower() for blocked_cmd in self.blocked_commands):
            stop_time = time.perf_counter()
            await utils.answer(
                message,
                f"<blockquote>💻 Код:\n<pre><code class=\"language-python\">{utils.escape_html(code)}</code></pre>\n💾 Код вернул:\n🚫 Команда заблокирована из соображений безопасности\n⏳ Выполнен за {round(stop_time - start_time, 5)} секунд</blockquote>"
            )
            return

        try:
            result = await meval(
                code,
                globals(),
                **await self.getattrs(message),
            )
        except Exception:
            item = HikkaException.from_exc_info(*sys.exc_info())
            stop_time = time.perf_counter()
            error_text = self.censor("\n".join(item.full_stack.splitlines()[:-1]) + "\n\n🚫 " + item.full_stack.splitlines()[-1])
            await utils.answer(
                message,
                f"<blockquote>💻 Код:\n<pre><code class=\"language-python\">{utils.escape_html(code)}</code></pre>\n{self.strings('err').format('python', error_text, round(stop_time - start_time, 5))}</blockquote>"
            )
            return

        if callable(getattr(result, "stringify", None)):
            with contextlib.suppress(Exception):
                result = str(result.stringify())

        stop_time = time.perf_counter()
        with contextlib.suppress(MessageIdInvalidError):
            result_text = self.strings('eval').format(
                'python',
                utils.escape_html(self.censor(str(result))),
                round(stop_time - start_time, 5)
            )
            await utils.answer(
                message,
                f"<blockquote>💻 Код:\n<pre><code class=\"language-python\">{utils.escape_html(code)}</code></pre>\n{result_text}</blockquote>"
            )

    @loader.command()
    async def ecpp(self, message: Message, c: bool = False):
        try:
            subprocess.check_output(
                ["gcc" if c else "g++", "--version"],
                stderr=subprocess.STDOUT,
            )
        except Exception:
            await utils.answer(
                message,
                f"<blockquote>{self.strings('no_compiler').format('4986046904228905931' if c else '4985844035743646190', 'C (gcc)' if c else 'C++ (g++)')}</blockquote>",
            )
            return

        code = utils.get_args_raw(message)
        start_time = time.perf_counter()

        if any(blocked_cmd in code.lower() for blocked_cmd in self.blocked_commands):
            stop_time = time.perf_counter()
            await utils.answer(
                message,
                f"<blockquote>💻 Код:\n<pre><code class=\"language-{('c' if c else 'cpp')}\">{utils.escape_html(code)}</code></pre>\n💾 Код вернул:\n🚫 Команда заблокирована из соображений безопасности\n⏳ Выполнен за {round(stop_time - start_time, 5)} секунд</blockquote>"
            )
            return

        message = await utils.answer(message, f"<blockquote>{self.strings('compiling')}</blockquote>")
        error = False
        with tempfile.TemporaryDirectory() as tmpdir:
            file = os.path.join(tmpdir, "code.cpp")
            with open(file, "w") as f:
                f.write(code)

            try:
                result = subprocess.check_output(
                    ["gcc" if c else "g++", "-o", "code", "code.cpp"],
                    cwd=tmpdir,
                    stderr=subprocess.STDOUT,
                ).decode()
            except subprocess.CalledProcessError as e:
                result = e.output.decode()
                error = True

            if not result:
                try:
                    result = subprocess.check_output(
                        ["./code"],
                        cwd=tmpdir,
                        stderr=subprocess.STDOUT,
                    ).decode()
                except subprocess.CalledProcessError as e:
                    result = e.output.decode()
                    error = True

        stop_time = time.perf_counter()
        with contextlib.suppress(MessageIdInvalidError):
            await utils.answer(
                message,
                f"<blockquote>💻 Код:\n<pre><code class=\"language-{('c' if c else 'cpp')}\">{utils.escape_html(code)}</code></pre>\n{self.strings('err' if error else 'eval').format('error' if error else 'output', utils.escape_html(result), round(stop_time - start_time, 5))}</blockquote>"
            )

    @loader.command()
    async def ec(self, message: Message):
        await self.ecpp(message, c=True)

    @loader.command()
    async def enode(self, message: Message):
        try:
            subprocess.check_output(
                ["node", "--version"],
                stderr=subprocess.STDOUT,
            )
        except Exception:
            await utils.answer(
                message,
                f"<blockquote>{self.strings('no_compiler').format('4985643941807260310', 'Node.js')}</blockquote>",
            )
            return

        code = utils.get_args_raw(message)
        start_time = time.perf_counter()

        if any(blocked_cmd in code.lower() for blocked_cmd in self.blocked_commands):
            stop_time = time.perf_counter()
            await utils.answer(
                message,
                f"<blockquote>💻 Код:\n<pre><code class=\"language-javascript\">{utils.escape_html(code)}</code></pre>\n💾 Код вернул:\n🚫 Команда заблокирована из соображений безопасности\n⏳ Выполнен за {round(stop_time - start_time, 5)} секунд</blockquote>"
            )
            return

        error = False
        with tempfile.TemporaryDirectory() as tmpdir:
            file = os.path.join(tmpdir, "code.js")
            with open(file, "w") as f:
                f.write(code)

            try:
                result = subprocess.check_output(
                    ["node", "code.js"],
                    cwd=tmpdir,
                    stderr=subprocess.STDOUT,
                ).decode()
            except subprocess.CalledProcessError as e:
                result = e.output.decode()
                error = True

        stop_time = time.perf_counter()
        with contextlib.suppress(MessageIdInvalidError):
            await utils.answer(
                message,
                f"<blockquote>💻 Код:\n<pre><code class=\"language-javascript\">{utils.escape_html(code)}</code></pre>\n{self.strings('err' if error else 'eval').format('javascript', utils.escape_html(result), round(stop_time - start_time, 5))}</blockquote>"
            )

    @loader.command()
    async def ephp(self, message: Message):
        try:
            subprocess.check_output(
                ["php", "--version"],
                stderr=subprocess.STDOUT,
            )
        except Exception:
            await utils.answer(
                message,
                f"<blockquote>{self.strings('no_compiler').format('4985815079074136919', 'PHP')}</blockquote>",
            )
            return

        code = utils.get_args_raw(message)
        start_time = time.perf_counter()

        if any(blocked_cmd in code.lower() for blocked_cmd in self.blocked_commands):
            stop_time = time.perf_counter()
            await utils.answer(
                message,
                f"<blockquote>💻 Код:\n<pre><code class=\"language-php\">{utils.escape_html(code)}</code></pre>\n💾 Код вернул:\n🚫 Команда заблокирована из соображений безопасности\n⏳ Выполнен за {round(stop_time - start_time, 5)} секунд</blockquote>"
            )
            return

        error = False
        with tempfile.TemporaryDirectory() as tmpdir:
            file = os.path.join(tmpdir, "code.php")
            with open(file, "w") as f:
                f.write(f"<?php {code} ?>")

            try:
                result = subprocess.check_output(
                    ["php", "code.php"],
                    cwd=tmpdir,
                    stderr=subprocess.STDOUT,
                ).decode()
            except subprocess.CalledProcessError as e:
                result = e.output.decode()
                error = True

        stop_time = time.perf_counter()
        with contextlib.suppress(MessageIdInvalidError):
            await utils.answer(
                message,
                f"<blockquote>💻 Код:\n<pre><code class=\"language-php\">{utils.escape_html(code)}</code></pre>\n{self.strings('err' if error else 'eval').format('php', utils.escape_html(result), round(stop_time - start_time, 5))}</blockquote>"
            )

    @loader.command()
    async def eruby(self, message: Message):
        try:
            subprocess.check_output(
                ["ruby", "--version"],
                stderr=subprocess.STDOUT,
            )
        except Exception:
            await utils.answer(
                message,
                f"<blockquote>{self.strings('no_compiler').format('4985760855112024628', 'Ruby')}</blockquote>",
            )
            return

        code = utils.get_args_raw(message)
        start_time = time.perf_counter()

        if any(blocked_cmd in code.lower() for blocked_cmd in self.blocked_commands):
            stop_time = time.perf_counter()
            await utils.answer(
                message,
                f"<blockquote>💻 Код:\n<pre><code class=\"language-ruby\">{utils.escape_html(code)}</code></pre>\n💾 Код вернул:\n🚫 Команда заблокирована из соображений безопасности\n⏳ Выполнен за {round(stop_time - start_time, 5)} секунд</blockquote>"
            )
            return

        error = False
        with tempfile.TemporaryDirectory() as tmpdir:
            file = os.path.join(tmpdir, "code.rb")
            with open(file, "w") as f:
                f.write(code)

            try:
                result = subprocess.check_output(
                    ["ruby", "code.rb"],
                    cwd=tmpdir,
                    stderr=subprocess.STDOUT,
                ).decode()
            except subprocess.CalledProcessError as e:
                result = e.output.decode()
                error = True

        stop_time = time.perf_counter()
        with contextlib.suppress(MessageIdInvalidError):
            await utils.answer(
                message,
                f"<blockquote>💻 Код:\n<pre><code class=\"language-ruby\">{utils.escape_html(code)}</code></pre>\n{self.strings('err' if error else 'eval').format('ruby', utils.escape_html(result), round(stop_time - start_time, 5))}</blockquote>"
            )

    @loader.command()
    async def ebf(self, message: Message):
        code = utils.get_args_raw(message)
        start_time = time.perf_counter()

        if "-debug" in code:
            code = code.replace("-debug", "").strip()
            debug = True
        else:
            debug = False

        if any(blocked_cmd in code.lower() for blocked_cmd in self.blocked_commands):
            stop_time = time.perf_counter()
            await utils.answer(
                message,
                f"<blockquote>💻 Код:\n<pre><code class=\"language-brainfuck\">{utils.escape_html(code)}</code></pre>\n💾 Код вернул:\n🚫 Команда заблокирована из соображений безопасности\n⏳ Выполнен за {round(stop_time - start_time, 5)} секунд</blockquote>"
            )
            return

        error = False
        bf = Brainfuck()
        result = bf.run(code)
        if bf.error:
            result = bf.error
            error = True

        if not result:
            result = "<empty>"

        if debug:
            result += "\n\n" + " | ".join(map(str, filter(lambda x: x, bf.data)))

        stop_time = time.perf_counter()
        with contextlib.suppress(MessageIdInvalidError):
            await utils.answer(
                message,
                f"<blockquote>💻 Код:\n<pre><code class=\"language-brainfuck\">{utils.escape_html(code)}</code></pre>\n{self.strings('err' if error else 'eval').format('brainfuck', utils.escape_html(result), round(stop_time - start_time, 5))}</blockquote>"
            )

    def censor(self, ret: str) -> str:
        ret = ret.replace(str(self._client.hikka_me.phone), "<phone>")

        if redis := os.environ.get("REDIS_URL") or main.get_config_key("redis_uri"):
            ret = ret.replace(redis, f'redis://{"*" * 26}')

        if db := os.environ.get("DATABASE_URL") or main.get_config_key("db_uri"):
            ret = ret.replace(db, f'postgresql://{"*" * 26}')

        if btoken := self._db.get("hikka.inline", "bot_token", False):
            ret = ret.replace(
                btoken,
                f'{btoken.split(":")[0]}:{"*" * 26}',
            )

        if htoken := self.lookup("loader").get("token", False):
            ret = ret.replace(htoken, f'eugeo_{"*" * 26}')

        ret = ret.replace(
            StringSession.save(self._client.session),
            "StringSession(**************************)",
        )

        return ret

    async def getattrs(self, message: Message) -> dict:
        reply = await message.get_reply_message()
        return {
            "message": message,
            "client": self._client,
            "reply": reply,
            "r": reply,
            **self.get_sub(hikkatl.tl.types),
            **self.get_sub(hikkatl.tl.functions),
            "event": message,
            "chat": message.to_id,
            "hikkatl": hikkatl,
            "telethon": hikkatl,
            "utils": utils,
            "main": main,
            "loader": loader,
            "f": hikkatl.tl.functions,
            "c": self._client,
            "m": message,
            "lookup": self.lookup,
            "self": self,
            "db": self.db,
        }

    def get_sub(self, obj: typing.Any, _depth: int = 1) -> dict:
        """Get all callable capitalised objects in an object recursively, ignoring _*"""
        return {
            **dict(
                filter(
                    lambda x: x[0][0] != "_"
                    and x[0][0].upper() == x[0][0]
                    and callable(x[1]),
                    obj.__dict__.items(),
                )
            ),
            **dict(
                itertools.chain.from_iterable(
                    [
                        self.get_sub(y[1], _depth + 1).items()
                        for y in filter(
                            lambda x: x[0][0] != "_"
                            and isinstance(x[1], ModuleType)
                            and x[1] != obj
                            and x[1].__package__.rsplit(".", _depth)[0] == "hikkatl.tl",
                            obj.__dict__.items(),
                        )
                    ]
                )
            ),
                }
