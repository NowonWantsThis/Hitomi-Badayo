#!/usr/bin/env python3
"""Compatibility runner for legacy-style scripts and hooks.

The host process writes a JSON request and reads the sentinel-prefixed result.
Legacy print output is captured and returned to the native activity log.

The ratelimit 2.2.1 compatibility section is MIT-licensed; see
LICENSES/ratelimit-MIT.txt in the source distribution.
"""

import argparse
import base64
import builtins
import concurrent.futures
import contextlib
import datetime as datetime_module
import email.utils
import functools
import hashlib
import html
import http.cookiejar
from html.parser import HTMLParser
import inspect
import io
import json
import math
import mimetypes
import os
import pathlib
import random
import re
import shlex
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time
import traceback
import types
import urllib.error
import urllib.parse
import urllib.request
import uuid as uuid_module
import zipfile


RESULT_PREFIX = "HITOMI_NATIVE_RESULT:"
REGISTERED_DOWNLOADERS = []
HOOK_EVENTS = ("task_about_to_start", "task_about_to_download", "task_finished", "format")
REGISTERED_HOOKS = {event: {} for event in HOOK_EVENTS}
REGISTERED_THEMES = {}
CURRENT_THEME = "default"
TOKENS = {}
ADD_TOKENS = [
    "width", "height", "fps", "vcodec", "acodec", "audio_channels",
    "language", "vbr", "abr", "tbr", "channel_id", "uploader_id",
]
ACTIVE_LIVES = {}
REGISTERED_ACTIONS = {}
PENDING_REMOVALS = []
HUGE = 999999999
DEFAULT_MAXIMUM = 2000
TAG_TIMER = {}


def emit(payload):
    raw = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    print(RESULT_PREFIX + base64.b64encode(raw).decode("ascii"), flush=True)


def string_value(value):
    if value is None:
        return None
    if isinstance(value, bytes):
        return value.decode("utf-8", "replace")
    if hasattr(value, "geturl"):
        return value.geturl()
    return str(value)


def clean_title(value, mode="soft", allow_dot=False, n=None):
    if value is None:
        return None
    if isinstance(mode, (int, float)) and not isinstance(mode, bool) and n is None:
        n = int(mode)
        mode = "soft"
    del mode, allow_dot
    value = string_value(value) or "download"
    value = re.sub(r"[\x00-\x1f\x7f]", " ", value)
    value = re.sub(r"[/:*?\"<>|]", "_", value)
    value = re.sub(r"\s+", " ", value).strip(" .") or "download"
    if isinstance(n, int) and n > 0:
        value = value[:n].rstrip()
    return value


def clean_url(value):
    return html.unescape((string_value(value) or "").strip())


def get_ext(value, default=None):
    path = urllib.parse.urlsplit(string_value(value) or "").path
    ext = pathlib.PurePosixPath(path).suffix.lower().lstrip(".")
    if ext == "jpeg":
        ext = "jpg"
    if ext:
        return "." + ext
    return default or ""


def remove_dup(values):
    result = []
    seen = set()
    for value in values:
        try:
            key = value
            if key in seen:
                continue
            seen.add(key)
        except TypeError:
            key = repr(value)
            if key in seen:
                continue
            seen.add(key)
        result.append(value)
    return result


def print_(*args, **kwargs):
    print(*args, **kwargs)


def get_print(cw=None):
    candidate = getattr(cw, "print_", None) if cw is not None else None
    return candidate if callable(candidate) else print_


def try_n(count=4, sleep=0.0):
    def decorator(function):
        @functools.wraps(function)
        def wrapped(*args, **kwargs):
            last_error = None
            for attempt in range(max(1, int(count))):
                try:
                    return function(*args, **kwargs)
                except Exception as error:
                    last_error = error
                    if sleep and attempt + 1 < count:
                        time.sleep(float(sleep))
            raise last_error
        return wrapped
    return decorator


class limits:
    """Serialize calls and keep the original utility helper's minimum spacing."""

    _t = 0

    def __init__(self, delay):
        self._lock = threading.RLock()
        self._delay = delay

    def __call__(self, function):
        @functools.wraps(function)
        def wrapped(*args, **kwargs):
            with self._lock:
                elapsed = time.time() - self._t
                if elapsed < self._delay:
                    time.sleep(self._delay - elapsed)
                self._t = time.time()
            return function(*args, **kwargs)
        return wrapped


class RateLimitException(Exception):
    def __init__(self, message, period_remaining):
        super().__init__(message)
        self.period_remaining = period_remaining


class RateLimitDecorator:
    """Recovered ratelimit 2.2.1 fixed-window decorator contract."""

    def __init__(self, calls=15, period=900, clock=time.monotonic, raise_on_limit=True):
        self.clamped_calls = max(1, min(sys.maxsize, math.floor(calls)))
        self.period = period
        self.clock = clock
        self.raise_on_limit = raise_on_limit
        self.last_reset = clock()
        self.num_calls = 0
        self.lock = threading.RLock()

    def __call__(self, function):
        @functools.wraps(function)
        def wrapped(*args, **kwargs):
            with self.lock:
                period_remaining = self.__period_remaining()
                if period_remaining <= 0:
                    self.num_calls = 0
                    self.last_reset = self.clock()
                self.num_calls += 1
                if self.num_calls > self.clamped_calls:
                    if self.raise_on_limit:
                        raise RateLimitException("too many calls", period_remaining)
                    return None
            return function(*args, **kwargs)
        return wrapped

    def __period_remaining(self):
        elapsed = self.clock() - self.last_reset
        return self.period - elapsed


def sleep_and_retry(function):
    @functools.wraps(function)
    def wrapped(*args, **kwargs):
        while True:
            try:
                return function(*args, **kwargs)
            except RateLimitException as error:
                time.sleep(error.period_remaining)
    return wrapped


class ReeNotFound(Exception):
    pass


def ree_find(pattern, string, flags=0, default=None, err=None):
    values = re.findall(pattern, string, flags)
    if values:
        return values[0]
    if err:
        raise ReeNotFound(err)
    return default


def check_alive(_cw=None):
    if _cw is not None and getattr(_cw, "alive", True) is False:
        raise StopReading("Task was stopped")
    return True


def get_max_range(cw=None, maximum=None, default=None):
    if maximum is None and default is not None:
        maximum = default
    if isinstance(cw, (int, float, str)):
        try:
            return max(0, int(cw))
        except (TypeError, ValueError):
            pass
    if maximum is None:
        maximum = DEFAULT_MAXIMUM

    type_name = getattr(cw, "type", None) if cw is not None else None
    downloader_class = Downloader.get(type_name) if isinstance(type_name, str) else None
    if downloader_class is not None and getattr(downloader_class, "NO_LIMIT", False):
        maximum = HUGE

    range_value = getattr(cw, "range", None) if cw is not None else None
    if callable(range_value):
        range_value = None
    if range_value is not None:
        return Range(range_value).max()
    return maximum


def parse_time_str(value):
    value = (string_value(value) or "").strip().lower().replace(" ", "")
    if not value:
        raise ValueError("Could not parse an empty time string")
    if not any(character.isalpha() for character in value):
        parts = list(map(float, value.split(":")))
        if len(parts) > 4:
            raise ValueError('too many ":" in time string')
        seconds = 0
        for index, part in enumerate(parts):
            if len(parts) == 4 and index == 1:
                seconds = seconds * 24 + part
            else:
                seconds = seconds * 60 + part
        return seconds

    total_seconds = 0
    for number, unit in re.findall(r"(\d+(?:\.\d+)?)([smhdw])", value):
        multiplier = {"s": 1, "m": 60, "h": 3600, "d": 86400, "w": 604800}[unit]
        total_seconds += float(number) * multiplier
    if total_seconds == 0:
        raise ValueError("Could not parse time string: {!r}".format(value))
    return total_seconds


def get_restart(cw):
    match = None
    parent = getattr(cw, "pc", None)
    for item in (cw, parent):
        if item is None:
            continue
        comment = getattr(item, "comment", None)
        comment = comment() if callable(comment) else comment
        match = re.search(r"restart:([^\s]+)", string_value(comment) or "", re.I)
        if match:
            break

    value = match.group(1) if match else None
    tags = list(getattr(cw, "tags", None) or [])
    if value is None and tags:
        timers = [float(TAG_TIMER.get(tag, 0) or 0) for tag in tags]
        timers = [timer for timer in timers if timer > 0]
        if timers:
            value = str(min(timers))
    return parse_time_str(value) if value else None


def query_url(url):
    return urllib.parse.parse_qs(urllib.parse.urlparse(clean_url(url)).query)


def generate_csrf_token():
    return random.getrandbits(128).to_bytes(16, "big").hex()


def atoi(value):
    value = string_value(value) or ""
    return int(value) if value.isdigit() else value


def format_filename(title, id=None, ext=".", dirFormat=None, header=None,
                    artist=None, date=None, d=None, live=False):
    del date, live
    title = clean_title(title, allow_dot=True) or "download"
    ext = string_value(ext)
    if ext is None:
        raise ValueError("no ext")
    if ext == ".":
        ext = ""
    elif ext and not ext.startswith("."):
        ext = "." + ext
    values = dict(d or {})
    values.update({
        "title": title,
        "id": "" if id in (None, "") else clean_title(str(id), allow_dot=True),
        "artist": "" if artist in (None, "") else clean_title(artist, allow_dot=True),
    })
    if header:
        values["title"] = "[{}] {}".format(clean_title(header), values["title"])
    template = string_value(dirFormat) or "title"
    names = "|".join(re.escape(key) for key in sorted(values, key=len, reverse=True))
    token_pattern = re.compile(
        r"\{(?P<brace>" + names + r")\}|"
        r"\[(?P<bracket>" + names + r")\]|"
        r"\((?P<paren>" + names + r")\)|"
        r"\b(?P<plain>" + names + r")\b"
    )

    def replace_token(match):
        key = next(value for value in match.groupdict().values() if value is not None)
        value = string_value(values.get(key)) or ""
        if match.group("bracket") is not None:
            return "[{}]".format(value) if value else ""
        if match.group("paren") is not None:
            return "({})".format(value) if value else ""
        return value

    template = token_pattern.sub(replace_token, template)
    template = re.sub(r"\s+", " ", template).strip(" .") or title
    return clean_title(template, allow_dot=True) + ext


def compatstr(value):
    if isinstance(value, str):
        return value
    if isinstance(value, bool):
        return str(value)
    if isinstance(value, bytes):
        return value.decode("utf-8")
    if hasattr(value, "toUtf8"):
        return value.toUtf8().decode("utf-8")
    return "" if value is None else str(value)


def original_uuid():
    return uuid_module.uuid4().hex


def get_resolution(res_text=None):
    if res_text is None:
        return 720
    value = compatstr(res_text).strip()
    if value.lower().endswith("p"):
        return int(value[:-1])
    return {"2K": 1440, "4K": 2160, "8K": 4320}[value.upper()]


def get_abr(abr_text=None):
    if abr_text is None:
        return 192
    return int(compatstr(abr_text).lower().replace("k", ""))


def fix_dup(filename, filenames):
    lowered = filename.lower()
    if lowered not in filenames:
        if hasattr(filenames, "__setitem__"):
            filenames[lowered] = 1
        else:
            filenames.add(lowered)
        return filename
    if not hasattr(filenames, "__setitem__"):
        stem, ext = os.path.splitext(os.path.basename(filename))
        count = 2
        while "{} ({}){}".format(stem, count, ext).lower() in filenames:
            count += 1
        result = "{} ({}){}".format(stem, count, ext)
        filenames.add(result.lower())
        return result
    filenames[lowered] += 1
    stem, ext = os.path.splitext(os.path.basename(filename))
    return fix_dup("{} ({}){}".format(stem, filenames[lowered], ext), filenames)


def original_join(values, max=2):
    values = [compatstr(value) for value in values]
    result = ", ".join(values[:max])
    if len(values) > max:
        result = ", ".join(values[:max - 1]) + ", Etc"
    return result or "N\uff0fA"


def fix_protocol(url):
    url = compatstr(url)
    if not re.search(r"^https?://", url, re.I):
        url = "https://" + url
    return re.sub(r"^https?://", "https://", url, count=1, flags=re.I)


def original_domain(url, n=0):
    try:
        value = urllib.parse.urlparse(fix_protocol(url)).netloc
    except Exception as error:
        print(error)
        return ""
    return ".".join(value.split(".")[-n:]) if n else value


def display_url(url):
    if not url:
        return url
    return re.sub(r"\d{1,3}(?:\.\d{1,3}){3}", "xxx.xxx.xxx.xxx", compatstr(url))


def update_url_query(url, query):
    if not query:
        return url
    parsed = urllib.parse.urlparse(url)
    values = urllib.parse.parse_qs(parsed.query)
    values.update(query)
    return urllib.parse.urlunparse(parsed._replace(query=urllib.parse.urlencode(values, doseq=True)))


def cut_pair(value, pairs=None, detect_quote=True):
    pairs = list(pairs or ["{", "}"])
    counts = {item: 0 for item in pairs}
    start = None
    quoted = False
    index = 0
    while index < len(value):
        if detect_quote and value[index] == '"':
            if not quoted or index == 0 or value[index - 1] != "\\":
                quoted = not quoted
        if quoted:
            index += 1
            continue
        changed = None
        for item in pairs:
            if value[index:index + len(item)] == item:
                counts[item] += 1
                changed = item
                if start is None:
                    start = index
        if changed and len(set(counts.values())) == 1:
            return value[start:index + len(changed)]
        index += 1
    raise Exception("pairs not matched")


class lazy:
    def __init__(self, fget):
        self.fget = fget
        self.func_name = fget.__name__

    def __get__(self, obj, _cls):
        if obj is None:
            return None
        value = self.fget(obj)
        if value is not None:
            setattr(obj, self.func_name, value)
        return value


def lock(function):
    mutex = threading.RLock()

    @functools.wraps(function)
    def wrapped(*args, **kwargs):
        with mutex:
            return function(*args, **kwargs)
    return wrapped


def _parse_original_range(value, size):
    parts = [part.strip() for part in compatstr(value).split("~")]
    if len(parts) == 1:
        parts.append(parts[0])
    if len(parts) != 2 or not any(parts):
        raise ValueError("Not matching range")
    start = int(parts[0]) if parts[0] else 0
    end = int(parts[1]) if parts[1] else size
    if start < 0:
        start = start % size + 1
    if end < 0:
        end = end % size + 1
    start, end = sorted((start, end))
    return range(start, end + 1)


class Range:
    HUGE = 999999999

    def __init__(self, ranges, size=HUGE):
        self._rs = [_parse_original_range(value, size) for value in compatstr(ranges).split(",")]

    def __contains__(self, value):
        return any(value in item for item in self._rs)

    def __repr__(self):
        return "Range({})".format(", ".join(map(str, self._rs)))

    def max(self):
        return max(item.stop for item in self._rs) - 1


def filter_range(values, range_):
    if range_ is None:
        return values
    selected = Range(range_, size=len(values))
    return [value for index, value in enumerate(values, 1) if index in selected]


def check_alive_iter(cw, values):
    for value in values:
        check_alive(cw)
        yield value


class SkipCounter:
    DEFAULT_DELAY = 1 / 60
    MAX_SPACING = 0.1
    _c = 0
    _c_skip = 0
    _t_last = 0
    _c_last = 0

    def __init__(self, delay=None, n=None, max_spacing=None):
        self._delay = delay or self.DEFAULT_DELAY
        self._n = n
        self._max_spacing = max_spacing or self.MAX_SPACING

    def next(self):
        self._c += 1
        if self._c == self._n:
            return True
        now = time.time()
        if now - self._t_last < self._delay and (
            not self._n or self._c - self._c_last < self._n * self._max_spacing
        ):
            self._c_skip += 1
            return False
        self._t_last = now
        self._c_last = self._c
        return True


def original_log(value):
    print(value)


def original_capitalize(value):
    if value is None:
        return None
    return " ".join(word[:1].upper() + word[1:] for word in compatstr(value).split(" "))


def original_natural_sort(values):
    def key(value):
        text = os.fspath(value) if isinstance(value, os.PathLike) else compatstr(value)
        return [int(part) if part.isdecimal() else part.casefold()
                for part in re.split(r"(\d+)", text)]
    return sorted(values, key=key)


def original_esc(value):
    payload = b"#esc#" + compatstr(value).encode("utf-8") + b"#/esc#"
    return base64.b64encode(payload).decode("utf-8").replace("=", "")


def original_open(file, mode="r", buffering=-1, encoding=None, errors=None,
                  newline=None, closefd=True, opener=None):
    return builtins.open(
        os.fspath(file) if isinstance(file, os.PathLike) else file,
        mode=mode,
        buffering=buffering,
        encoding=encoding,
        errors=errors,
        newline=newline,
        closefd=closefd,
        opener=opener,
    )


def original_dir(type_name, title, cw=None):
    retry = getattr(cw, "dir_retry", None) if cw is not None else None
    if retry:
        return os.path.abspath(os.fspath(retry))
    if not title:
        raise Exception("no title")
    root = None
    if cw is not None:
        root = getattr(cw, "dir", None) or getattr(cw, "outputPath", None)
    root = root or os.environ.get("HITOMI_NATIVE_OUTPUT_DIR")
    if not root:
        root = os.path.join(tempfile.gettempdir(), "HitomiBadayo", clean_title(type_name or "plugin"))
    root = os.path.abspath(os.fspath(root))
    if os.path.isfile(root):
        root = os.path.dirname(root)
    return os.path.join(root, clean_title(title))


def original_process_olds(file_class, title, pattern, cw, *, types=None):
    ids = set()
    names = {}
    directory = original_dir(getattr(file_class, "type", None), title, cw)
    if os.path.isdir(directory) and cw is not None:
        for item in list(getattr(cw, "names_old", None) or []):
            name = os.path.basename(os.fspath(item))
            identifier = ree_find(pattern, name, default=None)
            if identifier is None:
                continue
            if types:
                type_name = "video" if get_ext(name).lower() == ".mp4" else "img"
                if type_name not in types:
                    continue
            try:
                identifier = int(identifier)
            except (TypeError, ValueError):
                continue
            ids.add(identifier)
            names.setdefault(identifier, []).append(name)
    files = []
    for identifier in sorted(ids, reverse=True):
        for name in original_natural_sort(
            os.path.join(directory, value) for value in names[identifier]
        ):
            files.append(file_class({
                "referer": name,
                "id": identifier,
                "name": os.path.basename(name),
            }))
    return {"ids": ids, "names": names, "imgs": files}


def original_fix_enumerate(filename, index, cw):
    if (getattr(cw, "single", False) or not getattr(cw, "p2f", False) or
            not HEADLESS_UI_SETTING.playlist_numerate.isChecked()):
        return filename
    header = "{:04d} - ".format(int(index) + 1)
    name, extension = os.path.splitext(filename)
    suffix = ""
    if name.endswith(")") and " (" in name:
        name, identifier = name.rsplit(" (", 1)
        suffix = " ({})".format(identifier[:-1])
    maximum = max(1, 240 - len(header + suffix + extension))
    return header + clean_title(name.strip(), allow_dot=True, n=maximum) + suffix + extension


def original_submit_remove(path, trash=False):
    path = os.path.abspath(os.fspath(path))
    protected = {os.path.abspath("/"), os.path.abspath("."), os.path.expanduser("~")}
    if path in protected or os.path.splitext(path)[1].lower() in (".ini", ".json"):
        original_log("not safe: {}".format(path))
        return None
    PENDING_REMOVALS.append((path, bool(trash)))
    return None


def original_pp_subtitle(video, filename, cw):
    print_function = get_print(cw)
    print_function("pp_subtitle: {}".format(filename))
    if not HEADLESS_UI_SETTING.subtitle.isChecked():
        return None
    subtitles = dict(getattr(video, "subs", None) or {})
    if not subtitles:
        return None
    language = HEADLESS_UI_SETTING.subtitleCombo.currentText() or "en"
    selected = language if language in subtitles else next(
        (name for name in subtitles if name.startswith(language)),
        next((name for name in subtitles if name.startswith(language.split("-", 1)[0])), None),
    )
    if selected is None:
        return None
    source = subtitles[selected]
    base = os.path.splitext(os.path.abspath(os.fspath(filename)))[0]
    vtt = base + ".vtt"
    srt = base + ".srt"
    downloader_download(
        source,
        outdir=os.path.dirname(vtt),
        fileName=os.path.basename(vtt),
        overwrite=True,
    )
    try:
        ffmpeg_convert(vtt, srt, remove=True, verbose=False)
        output = srt
    except Exception:
        output = vtt
    if cw is not None:
        if output not in cw.imgs:
            cw.imgs.append(output)
        cw.dones.add(os.path.abspath(output))
        cw.setSubtitle(True)
    return output


def update_live(data, cw=None):
    data = dict(data or {})
    if cw is not None:
        cw.live = True
        cw._live_info = data
        cw.metadata.update({
            "live": "true",
            "is_live": "true",
            "live_url": compatstr(data.get("url") or getattr(cw, "url", "")),
            "live_title": compatstr(data.get("title") or ""),
        })
    url = clean_url(data.get("url"))
    item = ACTIVE_LIVES.get(url)
    if item is None:
        return None
    info = getattr(item, "_info", None)
    if not isinstance(info, dict):
        info = {}
        item._info = info
    if data.get("title"):
        info["title"] = compatstr(data["title"])
    thumbnail = data.get("thumb")
    if thumbnail:
        if isinstance(thumbnail, str):
            thumbnail = thumbnail.encode("utf-8")
        info["thumb"] = base64.b64encode(bytes(thumbnail)).decode("ascii")
    return None


class Live:
    types = {}
    type = None
    fix_url = None
    DELAY_RETRY_FAILED_STREAM = 5

    def __init_subclass__(cls, **kwargs):
        super().__init_subclass__(**kwargs)
        if cls.type is None:
            raise Exception("no type")
        Live.register(cls)

    @classmethod
    def register(cls, live_class):
        type_name = getattr(live_class, "type", None)
        if not isinstance(type_name, str):
            raise TypeError("type is not str")
        if re.fullmatch(r"[\w.]+", type_name, re.UNICODE) is None:
            raise ValueError("Invalid type")
        if cls.types.get(type_name) is live_class:
            return None
        cls.types[type_name] = live_class
        return live_class


def get_imgs_already(type_name, title, page, cw):
    if cw is None:
        return []
    page_title = clean_title(getattr(page, "title", ""))
    if page_title in (getattr(cw, "dirs_fail", None) or []):
        return []
    root = getattr(cw, "dir", None) or getattr(cw, "outputPath", None)
    if not root:
        return []
    directory = os.path.join(os.fspath(root), clean_title(title), page_title)
    if getattr(page, "title", "").endswith("...") or not os.path.isdir(directory):
        return []
    files = [os.path.join(directory, name) for name in sorted(os.listdir(directory))]
    if files:
        get_print(cw)("Skip: {}".format(getattr(page, "title", page_title)))
    return [path for path in files if os.path.isfile(path)]


def original_format_title(template, type_name, id, title, artist, group, series, lang,
                          prefix="", capitalize=True):
    def capitalized(value):
        value = compatstr(value)
        return value.title() if capitalize else value

    try:
        padded_id = "{}{:07}".format(prefix, int(id))
    except Exception:
        padded_id = "{}{}".format(prefix, id)
    tokens = {
        "0:id": padded_id,
        "id": "{}{}".format(prefix, id),
        "lang": capitalized(lang),
        "artist": capitalized(artist),
        "group": capitalized(group),
        "title": compatstr(title),
        "series": capitalized(series),
        "type": capitalized(type_name),
    }
    value = compatstr(template).strip().replace("\\", "/")
    for token in sorted(tokens, key=len, reverse=True):
        replacement = clean_title(tokens[token], allow_dot=True) if tokens[token] else ""
        value = re.sub(r"\b{}\b".format(re.escape(token)), replacement, value, flags=re.I)
    value = value.replace('"', "")
    return clean_title(re.sub(r"\s+", " ", value).strip(), allow_dot=True)


def format_title_gal(gallery):
    title = getattr(gallery, "title", "")
    artists = list(getattr(gallery, "artists", None) or [])
    groups = list(getattr(gallery, "groups", None) or [])
    artist = original_join(artists)
    group = original_join(groups) if groups else "N\uff0fA"
    if not artists:
        artist = group
    series_values = list(getattr(gallery, "seriess", None) or [])
    return original_format_title(
        "[artist] title (id)", getattr(gallery, "type", ""), getattr(gallery, "id", ""),
        title, artist, group, series_values[0] if series_values else "N\uff0fA",
        getattr(gallery, "language", None) or "N\uff0fA",
    )


def fix_title(instance, title, artist):
    instance.dirFormat = (getattr(instance, "dirFormat", "")
                          .replace("0:id", "").replace("id", "")
                          .replace("()", "").replace("[]", "").strip())
    get_print(getattr(instance, "cw", None))("dirFormat: {}".format(instance.dirFormat))
    formatter = getattr(instance, "format_title", None)
    if callable(formatter):
        result = formatter("N/A", "id", title, artist, "N/A", "N/A", "Korean")
    else:
        result = original_format_title(instance.dirFormat, "N/A", "id", title, artist,
                                       "N/A", "N/A", "Korean")
    while "  " in result:
        result = result.replace("  ", " ")
    return result


def get_text(element, separator="\n", cw=None):
    try:
        if hasattr(element, "_text_value") and hasattr(element, "children"):
            def node_text(node):
                if getattr(node, "name", None) == "#text":
                    return getattr(node, "_text_value", "") or ""
                if getattr(node, "name", None) == "br":
                    return separator + (getattr(node, "text", "") or "")
                children = list(getattr(node, "children", []) or [])
                if getattr(node, "name", None) == "ruby":
                    readings = [child for child in children if getattr(child, "name", None) == "rt"]
                    body = "".join(node_text(child) for child in children
                                   if getattr(child, "name", None) != "rt")
                    reading = "".join(node_text(child) for child in readings)
                    return "{}\uff08{}\uff09".format(body, reading)
                return "".join(node_text(child) for child in children)
            return node_text(element).strip()
        source = str(element)
        source = re.sub(r"<br\s*/?>", separator, source, flags=re.I)

        def ruby(match):
            body = re.sub(r"<rt[^>]*>.*?</rt>", "", match.group(1), flags=re.I | re.S)
            reading = ree_find(r"<rt[^>]*>(.*?)</rt>", match.group(1), re.I | re.S, "")
            return "{}\uff08{}\uff09".format(Soup(body).get_text(), Soup(reading).get_text())

        source = re.sub(r"<ruby[^>]*>(.*?)</ruby>", ruby, source, flags=re.I | re.S)
        return Soup(source).get_text(separator).strip()
    except Exception as error:
        get_print(cw)(print_error(error))
        return ""


ORIGINAL_SITE_DEFAULTS = {
    "#live#": {"format": "[artist] date:%Y-%m-%d %H:%M; title"},
    "twitter": {"retweet": False, "format": "[date] id_ppage"},
    "torrent": {"seeding": False, "trackers": "", "etc": None},
    "insta": {"format": "[date] id_ppage"},
    "pixiv": {"format": "id_ppage"},
    "youtube": {"format": "[artist] title (id)", "channel_reverse": False},
    "twitch": {"strip_ads": True},
    "weibo": {"format": "[date] id"},
    "ehen": {},
}


def _formatted_token(value, token_format):
    if not token_format:
        return compatstr(value)
    token_format = token_format.strip('"')
    try:
        if isinstance(value, str) and token_format[1:].isdecimal():
            return value[:int(token_format)].strip()
        if isinstance(value, int) and token_format[:1] in "+-":
            return str(value + int(token_format))
        if not isinstance(value, int):
            raise ValueError("not int")
        if not token_format.startswith("0"):
            raise ValueError("not starts with 0")
        return str(value).zfill(int(token_format))
    except Exception:
        return compatstr(value)


def original_data_format(type_name, data, ext=None):
    values = dict(data or {})
    callback = REGISTERED_HOOKS.get("format", {}).get(type_name)
    if callback is not None:
        return callback(values, ext)
    template = ORIGINAL_SITE_DEFAULTS.get(type_name, {}).get("format")
    if not template:
        template = compatstr(values.pop("format", None) or "id_ppage")

    if "date" in values:
        date = values.pop("date")
        if not isinstance(date, datetime_module.datetime):
            date = datetime_module.datetime.fromtimestamp(float(date))
        pattern = re.compile(r"date(?::([^;]*);)?")
        template = pattern.sub(lambda match: date.strftime(
            (match.group(1) or "%y-%m-%d").strip('"') or "%y-%m-%d"
        ), template)

    for token in sorted(values, key=len, reverse=True):
        value = values[token]
        pattern = re.compile(r"{}(?::([^;]*);)?".format(re.escape(token)))
        template = pattern.sub(
            lambda match, value=value: _formatted_token(value, match.group(1)), template
        )

    parts = [clean_title(part, allow_dot=True) for part in template.split("/")]
    result = "/".join(part for part in parts if part)
    if ext:
        ext = compatstr(ext)
        if not ext.startswith("."):
            ext = "." + ext
        segments = result.split("/")
        segments[-1] = clean_title(segments[-1], allow_dot=True, n=max(1, 240 - len(ext))) + ext
        result = "/".join(segments)
    return result


class Nothing:
    pass


class InvalidError(Exception):
    def __init__(self, *args, fail=False):
        self.fail = fail
        super().__init__(*args)


InvalidError.__name__ = "Invalid"


class BrowserRequired(Exception):
    pass


class LoginRequired(Exception):
    def __init__(self, *args, method="cookies", url=None, cookie=True, w=None, h=None):
        if method == "browser" and getattr(sys.modules.get("constants"), "mybrowser", None) is None:
            raise BrowserRequired()
        self.method = method
        self.url = url
        self.cookie = cookie
        self.w = w
        self.h = h
        super().__init__(*args)


class OutdatedExtension(Exception):
    pass


class Disgusting(Exception):
    pass


class Retry(Exception):
    status = "wait"


class StopReading(Exception):
    pass


ORIGINAL_ERRORS = (
    InvalidError,
    LoginRequired,
    BrowserRequired,
    OutdatedExtension,
    Disgusting,
    Retry,
    StopReading,
)


def raise_invalid(type_name=None, cw=None, s="", e=None, fail=False):
    message = string_value(s) or "Invalid"
    if type_name:
        message = "{}: {}".format(type_name, message)
    if e is not None:
        message += ": {}".format(e)
    if cw is not None:
        cw.valid = False
        cw.error = message
    raise InvalidError(message, fail=fail)


class CompatResponse:
    def __init__(self, response, body):
        self._response = response
        self.content = body
        self.url = response.geturl()
        self.status_code = int(getattr(response, "status", response.getcode() or 200))
        self.headers = dict(response.headers.items())
        self.encoding = self._encoding_from_headers() or "utf-8"
        self.reason = string_value(getattr(response, "reason", None)) or ""
        self.history = []
        self.cookies = None
        self.raw = io.BytesIO(body)

    def _encoding_from_headers(self):
        content_type = self.headers.get("Content-Type", "")
        match = re.search(r"charset\s*=\s*([^;\s]+)", content_type, re.I)
        return match.group(1).strip("\"'") if match else None

    @property
    def text(self):
        try:
            return self.content.decode(self.encoding or "utf-8", "replace")
        except LookupError:
            return self.content.decode("utf-8", "replace")

    @property
    def ok(self):
        return 200 <= self.status_code < 400

    def json(self):
        return json.loads(self.text)

    def raise_for_status(self):
        if not self.ok:
            raise RuntimeError("HTTP {} for {}".format(self.status_code, self.url))

    def iter_content(self, chunk_size=65536):
        for offset in range(0, len(self.content), max(1, int(chunk_size))):
            yield self.content[offset:offset + chunk_size]

    def iter_lines(self, chunk_size=65536, decode_unicode=False, delimiter=None):
        del chunk_size
        value = self.text if decode_unicode else self.content
        separator = delimiter if delimiter is not None else ("\n" if decode_unicode else b"\n")
        for line in value.split(separator):
            yield line

    def close(self):
        try:
            self._response.close()
        except Exception:
            pass

    def __enter__(self):
        return self

    def __exit__(self, *_args):
        self.close()


class CompatCookieJar(http.cookiejar.CookieJar):
    def get_dict(self, domain=None, path=None):
        result = {}
        for cookie in self:
            if domain and cookie.domain != domain:
                continue
            if path and cookie.path != path:
                continue
            result[cookie.name] = cookie.value
        return result

    def set(self, name, value, domain="", path="/"):
        cookie = http.cookiejar.Cookie(
            version=0, name=string_value(name), value=string_value(value),
            port=None, port_specified=False, domain=domain, domain_specified=bool(domain),
            domain_initial_dot=domain.startswith("."), path=path, path_specified=True,
            secure=False, expires=None, discard=True, comment=None, comment_url=None,
            rest={}, rfc2109=False,
        )
        self.set_cookie(cookie)
        return cookie

    def update(self, values):
        if hasattr(values, "get_dict"):
            values = values.get_dict()
        for key, value in dict(values or {}).items():
            self.set(key, value)


class Session:
    def __init__(self, cw=None, accept_cookies=None, *_args, **_kwargs):
        self.cw = cw
        self.accept_cookies = accept_cookies
        self.headers = {}
        self.cookies = CompatCookieJar()
        self.proxies = {}
        self.params = {}
        self.auth = None
        self.verify = True
        self._opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(self.cookies))

    def request(self, method, url, params=None, data=None, json=None, headers=None,
                timeout=30, allow_redirects=True, verify=True, **_kwargs):
        del allow_redirects, verify
        url = clean_url(url)
        combined_params = dict(self.params)
        combined_params.update(params or {})
        if combined_params:
            query = urllib.parse.urlencode(combined_params, doseq=True)
            separator = "&" if urllib.parse.urlsplit(url).query else "?"
            url += separator + query
        body = data
        request_headers = dict(self.headers)
        request_headers.update(headers or {})
        if json is not None:
            body = globals()["json"].dumps(json).encode("utf-8")
            request_headers.setdefault("Content-Type", "application/json")
        elif isinstance(body, dict):
            body = urllib.parse.urlencode(body, doseq=True).encode("utf-8")
        elif isinstance(body, str):
            body = body.encode("utf-8")
        request = urllib.request.Request(url, data=body, headers=request_headers, method=method.upper())
        try:
            response = self._opener.open(request, timeout=float(timeout or 30))
            content = b"" if method.upper() == "HEAD" else response.read()
        except urllib.error.HTTPError as error:
            response = error
            content = error.read()
        return CompatResponse(response, content)

    def get(self, url, **kwargs):
        return self.request("GET", url, **kwargs)

    def post(self, url, **kwargs):
        return self.request("POST", url, **kwargs)

    def head(self, url, **kwargs):
        return self.request("HEAD", url, **kwargs)

    def put(self, url, **kwargs):
        return self.request("PUT", url, **kwargs)

    def patch(self, url, **kwargs):
        return self.request("PATCH", url, **kwargs)

    def delete(self, url, **kwargs):
        return self.request("DELETE", url, **kwargs)

    def options(self, url, **kwargs):
        return self.request("OPTIONS", url, **kwargs)

    def close(self):
        return None

    def mount(self, *_args, **_kwargs):
        return None

    def setInterval(self, *_args, **_kwargs):
        return None

    def purge(self, *_args, **_kwargs):
        self.cookies.clear()

    def dump(self):
        return {"headers": dict(self.headers), "cookies": self.cookies.get_dict()}

    @classmethod
    def load(cls, data, *args, **kwargs):
        session = cls(*args, **kwargs)
        session.headers.update(dict((data or {}).get("headers") or {}))
        session.cookies.update(dict((data or {}).get("cookies") or {}))
        return session


def _download_source_bytes(url, session, headers, timeout, chunk, n_threads, mode):
    parsed = urllib.parse.urlsplit(url)
    if parsed.scheme == "data":
        metadata, payload = url.split(",", 1)
        return base64.b64decode(payload) if ";base64" in metadata else urllib.parse.unquote_to_bytes(payload)
    if parsed.scheme == "file":
        with open(urllib.request.url2pathname(parsed.path), "rb") as handle:
            return handle.read()

    expected = None
    try:
        head = session.head(url, headers=headers, timeout=timeout)
        if head.ok:
            expected = int(head.headers.get("Content-Length") or 0) or None
    except Exception:
        expected = None

    workers = max(1, int(n_threads or 1))
    if workers <= 1 or not expected or expected <= max(1, int(chunk or 0)):
        response = session.get(url, headers=headers, timeout=timeout)
        response.raise_for_status()
        return response.content

    part_size = max(1, int(chunk or math.ceil(expected / workers)))
    ranges = [(start, min(start + part_size - 1, expected - 1))
              for start in range(0, expected, part_size)]

    def fetch(byte_range):
        start, end = byte_range
        request_headers = dict(headers)
        request_url = url
        if mode == "query":
            request_url = update_url_query(url, {"range": "{}-{}".format(start, end)})
        else:
            request_headers["Range"] = "bytes={}-{}".format(start, end)
        response = session.get(request_url, headers=request_headers, timeout=timeout)
        response.raise_for_status()
        return byte_range, response.status_code, response.content

    first_range, first_status, first_content = fetch(ranges[0])
    if first_status != 206 and mode == "header":
        return first_content
    contents = {first_range: first_content}
    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as executor:
        futures = [executor.submit(fetch, byte_range) for byte_range in ranges[1:]]
        for future in concurrent.futures.as_completed(futures):
            byte_range, status, content = future.result()
            if mode == "header" and status != 206:
                response = session.get(url, headers=headers, timeout=timeout)
                response.raise_for_status()
                return response.content
            contents[byte_range] = content
    result = b"".join(contents[byte_range] for byte_range in ranges)
    if len(result) != expected:
        raise RuntimeError("Parallel download size mismatch: {} != {}".format(len(result), expected))
    return result


def _write_download_result(payload, url, outdir, file_name, buffer, overwrite,
                           progress, size, custom_widget, sd):
    check_alive(custom_widget)
    if progress is not None:
        progress.maximum = len(payload)
        progress.value = 0
    if buffer is not None:
        try:
            buffer.seek(0)
            buffer.truncate(0)
        except Exception:
            pass
        for offset in range(0, len(payload), 65536):
            block = payload[offset:offset + 65536]
            buffer.write(block)
            if progress is not None:
                progress.value += len(block)
        try:
            buffer.seek(0)
        except Exception:
            pass
        result = buffer
    else:
        file_name = file_name or os.path.basename(urllib.parse.urlsplit(url).path) or "download"
        directory = os.path.abspath(os.fspath(outdir or tempfile.gettempdir()))
        os.makedirs(directory, exist_ok=True)
        result = os.path.join(directory, clean_title(file_name, allow_dot=True))
        if os.path.exists(result) and not overwrite:
            return result
        temporary = result + ".hitominative-part"
        with open(temporary, "wb") as handle:
            for offset in range(0, len(payload), 65536):
                check_alive(custom_widget)
                block = payload[offset:offset + 65536]
                handle.write(block)
                if progress is not None:
                    progress.value += len(block)
        os.replace(temporary, result)
    if size is not None and hasattr(size, "size"):
        size.size += len(payload)
    if sd is not None:
        sd["write"] = True
    return result


def downloader_download(url, outdir="", overwrite=False, chunk=65536, referer=None,
                        alert=True, timeout=30, max_try=4, sleep_time=0, aborter=None,
                        fileName=None, header=None, buffer=None, progress=None, size=None,
                        session=None, user_agent=None, customWidget=None, methods=None,
                        url_alter=None, cookies=None, print__=None, sd=None, **_kwargs):
    del alert, aborter, methods
    session = session or Session(customWidget)
    if cookies:
        session.cookies.update(cookies)
    headers = dict(header or {})
    if referer:
        headers.setdefault("Referer", referer)
    if user_agent:
        headers.setdefault("User-Agent", user_agent)
    if callable(url_alter):
        url = url_alter(url)
    if buffer is None and not isinstance(url, (str, bytes)) and callable(getattr(url, "open", None)):
        directory = os.path.abspath(os.fspath(outdir or tempfile.gettempdir()))
        os.makedirs(directory, exist_ok=True)
        name = fileName or getattr(url, "name", None) or "download"
        path = os.path.join(directory, clean_title(os.path.basename(os.fspath(name)), allow_dot=True))
        if os.path.exists(path) and not overwrite:
            return path
        opened = url.open(path, progress, size)
        thread = getattr(opened, "t", None)
        if thread is not None and callable(getattr(thread, "join", None)):
            thread.join()
        try:
            opened.close()
        except Exception as error:
            (print__ or print)("\n close fail : {}\n{}".format(path, print_error(error)))
        if sd is not None:
            sd["write"] = True
        return path
    url = clean_url(url)
    last_error = None
    attempts = max(1, int(max_try or 1))
    for attempt in range(attempts):
        try:
            payload = _download_source_bytes(url, session, headers, timeout, chunk, 1, "header")
            return _write_download_result(
                payload, url, outdir, fileName, buffer, overwrite,
                progress, size, customWidget, sd,
            )
        except Exception as error:
            last_error = error
            if print__:
                print__(error)
            if attempt + 1 < attempts and sleep_time:
                compatibility_sleep(sleep_time, customWidget)
    raise last_error


class DownloaderV3Task:
    def __init__(self, url, size, i, n, chunk, mode):
        self.url = url
        self.mode = mode
        self.i = i
        self.n = n
        start = chunk * i
        end = min(chunk * (i + 1) - 1, size - 1)
        self.size = end - start + 1
        if mode == "header":
            self.headers = {"Range": "bytes={}-{}".format(start, end)}
        elif mode == "query":
            self.headers = {}
            self.url = update_url_query(url, {"range": "{}-{}".format(start, end)})
        else:
            raise NotImplementedError(mode)


DOWNLOADER_V3_THREADS = []


def downloader_v3_update_progress(progress, size, content=None):
    if progress is None:
        return
    if size is not None and hasattr(size, "size"):
        progress.value = size.size
    else:
        progress.value += len(content or b"")


def downloader_v3_download(url, outdir="", fileName=None, session=None, n=None,
                           chunk=None, n_threads=None, size=None, customWidget=None,
                           progress=None, buffer=None, overwrite=False, referer=None,
                           header=None, verbose=False, timeout=None, try_=1, sd=None,
                           mode="header"):
    del n, verbose
    session = session or Session(customWidget)
    headers = dict(header or {})
    if referer:
        headers.setdefault("Referer", referer)
    last_error = None
    for attempt in range(max(1, int(try_ or 1))):
        try:
            payload = _download_source_bytes(
                clean_url(url), session, headers, timeout or 180,
                chunk or 1024 * 1024, n_threads or 2, mode,
            )
            return _write_download_result(
                payload, clean_url(url), outdir, fileName, buffer, overwrite,
                progress, size, customWidget, sd,
            )
        except Exception as error:
            last_error = error
            if attempt + 1 < max(1, int(try_ or 1)):
                continue
    raise last_error


TRANSLATIONS = {}
TRANSLATIONS_SPECIAL = {}
TRANSLATIONS_NORMAL = {}
TRANSLATION_SEPARATOR = "#^q^#"


def update_translation(values):
    language = string_value((values or {}).get("lang")) or "en"
    items = dict((values or {}).get("items") or {})
    TRANSLATIONS[language] = items
    TRANSLATIONS_SPECIAL[language] = {
        key: value for key, value in items.items()
        if key.startswith("#") and key.endswith("#")
    }
    TRANSLATIONS_NORMAL[language] = {
        key: value for key, value in items.items()
        if not (key.startswith("#") and key.endswith("#"))
    }


def tr_(value, lang=None):
    value = string_value(value) or ""
    configured_language = getattr(sys.modules.get("constants"), "curlang", "en")
    language = (string_value(lang) or string_value(configured_language) or "en").lower()
    if value.startswith("#") and value.endswith("#"):
        return TRANSLATIONS_SPECIAL.get(language, {}).get(value, value)
    for name, translated in TRANSLATIONS_NORMAL.get(language, {}).items():
        if name:
            value = value.replace(name, string_value(translated) or "")
    return value


def tr(value, lang=None, top=True):
    del top
    return tr_(value, lang) if isinstance(value, (str, bytes)) else value


def translate(value, dest="ko", src="auto"):
    del dest, src
    return string_value(value) or ""


def compatibility_sleep(seconds, cw=None):
    seconds = max(0.0, float(seconds or 0))
    if cw is None:
        time.sleep(seconds)
        return None
    whole = int(seconds)
    remainder = seconds - whole
    for _index in range(whole):
        check_alive(cw)
        time.sleep(1)
    if remainder:
        check_alive(cw)
        time.sleep(remainder)
    check_alive(cw)
    return None


def format_compatibility_traceback():
    message = traceback.format_exc()
    message = message.replace("kurtbestor.pythonanywhere", "{kurtpy}")
    message = re.sub(r"\.py[cdox]?(['\"])", r"\1", message)
    return re.sub(r"(PyQt|PySide)[0-9]+", "PyQt", message)


def print_error(_error):
    return format_compatibility_traceback()


SELECTOR_CANCEL = object()
SELECTOR_CALLBACKS = {}
SELECTOR_OPTIONS = {}
SELECTOR_DEFAULT = {}
PAGE_CALLBACKS = {}


def _registry_decorator(registry, type_name):
    def wrapper(function):
        registry[type_name] = function
        return function
    return wrapper


def selector_register(type_name):
    return _registry_decorator(SELECTOR_CALLBACKS, type_name)


def selector_options(type_name):
    return _registry_decorator(SELECTOR_OPTIONS, type_name)


def selector_default_option(type_name):
    return _registry_decorator(SELECTOR_DEFAULT, type_name)


def _pattern_matches_url(pattern, url):
    pattern = string_value(pattern) or ""
    if not pattern:
        return False
    try:
        if re.search(pattern, url, re.I):
            return True
    except re.error:
        pass
    parsed = urllib.parse.urlsplit(url)
    host = (parsed.hostname or "").lower()
    plain = pattern.lower().strip("^$")
    return plain in url.lower() or (plain and (host == plain or host.endswith("." + plain)))


def is_valid_url(value):
    url = clean_url(value)
    result = set()
    for downloader_class in REGISTERED_DOWNLOADERS:
        patterns = getattr(downloader_class, "URLS", None) or []
        if isinstance(patterns, (str, bytes)):
            patterns = [patterns]
        if any(_pattern_matches_url(pattern, url) for pattern in patterns):
            type_name = string_value(getattr(downloader_class, "type", None))
            if type_name:
                result.add(type_name)
    return result


def selector_process(value):
    selected = {}
    for type_name in list(is_valid_url(value)):
        callback = SELECTOR_CALLBACKS.get(type_name)
        if callback is None:
            continue
        result = callback()
        if result is SELECTOR_CANCEL:
            return None
        selected[type_name] = result
    return selected


def page_register(type_name):
    return _registry_decorator(PAGE_CALLBACKS, type_name)


def page_filter(pages, cw):
    selected = None if cw is None else getattr(cw, "range_p", None)
    if selected is None:
        return pages
    indexes = set(selected)
    return [page for index, page in enumerate(pages) if index in indexes]


def select_pages(_value, _type_name, parent=None):
    return None if parent is None else getattr(parent, "range_p", None)


class EmptySegment:
    pass


class SegmentKey:
    def __init__(self, method=None, uri=None, iv=None):
        self.method = string_value(method) or "AES-128"
        self.uri = clean_url(uri)
        self.iv = string_value(iv)


class Segment:
    _ignore_err = False
    _err = False
    oprinter = None

    def __init__(self, seg, base_url, session, headers=None):
        self.session = session
        self.headers = dict(headers or {})
        self.raw = seg
        self.base_url = clean_url(base_url)
        self._hitomi_native_source_index = getattr(seg, "_hitomi_native_source_index", None)
        if hasattr(seg, "uri"):
            self.url = urljoin_q(self.base_url, getattr(seg, "uri"))
            self.key = getattr(seg, "key", None)
        else:
            self.url = urljoin_q(self.base_url, seg)
            self.key = getattr(seg, "key", None)

    def copy(self):
        copied = Segment(self.raw, self.base_url, self.session, dict(self.headers))
        copied.url = self.url
        copied.key = self.key
        copied._ignore_err = bool(getattr(self, "_ignore_err", False))
        copied._err = bool(getattr(self, "_err", False))
        copied._hitomi_native_source_index = self._hitomi_native_source_index
        return copied

    def __str__(self):
        return self.url


class M3u8Stream:
    alive = True
    i = 0
    ts = None
    live = None
    live_timeout = None
    oprint = None
    mpegts = None

    def __init__(self, url, base_url=None, referer=None, deco=None, urls=None,
                 n_thread=None, referer_seg="auto", post_processing=None,
                 session=None, alter=None, test=True, info=None, live=False):
        self.url = clean_url(url)
        self.base_url = clean_url(base_url) if base_url else None
        self.referer = string_value(referer)
        self.deco = deco
        self.urls = list(urls or [])
        self.n_thread = n_thread
        self.referer_seg = referer_seg
        self.post_processing = post_processing
        self.session = session or Session()
        self.alter = alter
        self.test = test
        self.info = dict(info or {})
        self.live = bool(live)
        self.headers = {}
        self._hitomi_native_preferred_resolution = None

    @property
    def segs(self):
        return self.urls

    @property
    def downloading_segs(self):
        return 0

    def add_downloading_segs(self, _value):
        return None

    def add_visited(self, _value):
        return None

    def is_visited(self, _value):
        return False

    def update_live(self):
        return None

    def close(self):
        self.alive = False

    def read(self, *_args, **_kwargs):
        raise RuntimeError("M3u8_stream is downloaded by the native host")

    def __add__(self, _other):
        return self

    def __repr__(self):
        return "M3u8_stream({})".format(self.url)


M3u8Stream.__name__ = "M3u8_stream"


class DashStream(M3u8Stream):
    stream_type = "dash"


DashStream.__name__ = "Dash_stream"


def playlist2stream(url, referer=None, n_thread=None, session=None, kwargs=None,
                    res="auto", info=None):
    options = dict(kwargs or {})
    referer = options.pop("referer", referer)
    options.setdefault("n_thread", n_thread)
    options.setdefault("session", session)
    options.setdefault("test", True)
    options.setdefault("info", info or {})
    base_url = options.pop("base_url", None) or url
    stream = M3u8Stream(url, base_url=base_url, referer=referer, **options)
    if res not in (None, False, "", "auto"):
        if isinstance(res, (list, tuple)) and res:
            res = res[-1]
        stream._hitomi_native_preferred_resolution = string_value(res)
    return stream


def dash2stream(url, referer=None, representation=None, mime="video", session=None):
    del representation, mime
    return DashStream(url, base_url=url, referer=referer, session=session)


FFMPEG_DEFAULT_PIPE_OPTIONS = (
    "-c:v copy -c:a aac -f mpegts -copyts -max_reload 2147483647 "
    "-m3u8_hold_counters 2147483647 -seg_max_retry 2 -async 1 -vsync 1"
)
FFMPEG_THREADS = max(1, os.cpu_count() or 1)
FFMPEG_PROCESSES = set()
FFMPEG_EXECUTION_LOCK = threading.RLock()
FFMPEG_IMAGE_EXTENSIONS = {
    "apng", "avif", "bmp", "gif", "heic", "heif", "jpeg", "jpg",
    "png", "tif", "tiff", "webp",
}


class CompatFFmpegPopen(subprocess.Popen):
    def __init__(self, *args, **kwargs):
        kwargs.setdefault("stdin", subprocess.DEVNULL)
        super().__init__(*args, **kwargs)
        FFMPEG_PROCESSES.add(self)


def ffmpeg_kill(process, wait=True):
    if process is None:
        return None
    if isinstance(process, int):
        try:
            os.kill(process, signal.SIGTERM)
        except OSError:
            return None
        return None
    try:
        if process.poll() is None:
            process.terminate()
            if wait:
                try:
                    process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=3)
    finally:
        FFMPEG_PROCESSES.discard(process)
    return None


def ffmpeg_end():
    for process in list(FFMPEG_PROCESSES):
        try:
            ffmpeg_kill(process)
        except Exception:
            pass


def _ffmpeg_executable(kind="ffmpeg"):
    kind = (string_value(kind) or "ffmpeg").strip().lower()
    if kind not in ("ffmpeg", "ffprobe"):
        raise RuntimeError("Unsupported FFmpeg executable: {}".format(kind))
    environment_key = "HITOMI_NATIVE_FFPROBE" if kind == "ffprobe" else "HITOMI_NATIVE_FFMPEG"
    configured = os.environ.get(environment_key, "").strip()
    if not configured and kind == "ffprobe":
        ffmpeg_path = os.environ.get("HITOMI_NATIVE_FFMPEG", "").strip()
        if ffmpeg_path:
            sibling = os.path.join(os.path.dirname(os.path.abspath(ffmpeg_path)), "ffprobe")
            if os.path.isfile(sibling) and os.access(sibling, os.X_OK):
                configured = sibling
    candidates = [configured] if configured else []
    discovered = shutil.which(kind)
    if discovered:
        candidates.append(discovered)
    for candidate in candidates:
        path = os.path.abspath(os.path.expanduser(candidate))
        if os.path.isfile(path) and os.access(path, os.X_OK):
            return path
    raise RuntimeError(
        "{} is not installed. Open Settings > External Tools to install it or choose an executable."
        .format("FFprobe" if kind == "ffprobe" else "FFmpeg")
    )


def ffmpeg_load(bin="ffmpeg", cw=None, verbose=True, try_=1):
    del try_
    check_alive(cw)
    path = _ffmpeg_executable(bin)
    if verbose:
        get_print(cw)("{}: {}".format(bin, path))
    return path


def ffmpeg_ready(cw=None):
    check_alive(cw)
    try:
        _ffmpeg_executable("ffmpeg")
        _ffmpeg_executable("ffprobe")
        return True
    except Exception:
        return False


def _ffmpeg_arguments(command, kind):
    if isinstance(command, str):
        arguments = shlex.split(command, posix=True)
    else:
        arguments = [string_value(value) or "" for value in command]
    if arguments:
        first = os.path.basename(arguments[0]).lower()
        if first in ("ffmpeg", "ffmpeg.exe", "ffprobe", "ffprobe.exe"):
            arguments = arguments[1:]
    return [_ffmpeg_executable(kind)] + arguments


def ffmpeg_run(cmd, dir=None, cw=None, timeout=120, lock=True, bin="ffmpeg", verbose=True):
    check_alive(cw)
    command = _ffmpeg_arguments(cmd, bin)
    if verbose:
        get_print(cw)(" ".join(shlex.quote(value) for value in command))
    process = None
    output = b""
    code = -1
    guard = FFMPEG_EXECUTION_LOCK if lock else contextlib.nullcontext()
    with guard:
        try:
            process = CompatFFmpegPopen(
                command,
                cwd=dir or None,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
            )
            output, _unused = process.communicate(timeout=max(1.0, float(timeout or 120)))
            code = int(process.returncode or 0)
        except subprocess.TimeoutExpired:
            ffmpeg_kill(process)
            raise RuntimeError("{} timed out".format(bin))
        finally:
            if process is not None:
                FFMPEG_PROCESSES.discard(process)
    return output.decode("utf-8", "replace") if isinstance(output, bytes) else (output or ""), code


def _ffmpeg_tail(value):
    lines = [line.strip() for line in (string_value(value) or "").splitlines() if line.strip()]
    return " ".join(lines[-8:]) or "no diagnostic output"


def ffmpeg_check_code(code):
    if code == 0:
        return None
    if code == 4_294_967_268:
        raise OSError("No space left on device")
    raise RuntimeError("Failed to convert; exit code: {}".format(code))


def _ffmpeg_execute(arguments, cw=None, timeout=120, bin="ffmpeg", verbose=False, cwd=None):
    output, code = ffmpeg_run(
        arguments,
        dir=cwd,
        cw=cw,
        timeout=timeout,
        lock=True,
        bin=bin,
        verbose=verbose,
    )
    try:
        ffmpeg_check_code(code)
    except Exception as error:
        diagnostic = _ffmpeg_tail(output)
        if diagnostic != "no diagnostic output":
            error.args = ("{}: {}".format(error, diagnostic),)
        raise
    return output


def ffmpeg_rename(src, dst, delay=1, cw=None, n_try=120):
    src = os.path.abspath(os.fspath(src))
    dst = os.path.abspath(os.fspath(dst))
    if src == dst:
        return dst
    os.makedirs(os.path.dirname(dst) or ".", exist_ok=True)
    error = None
    for attempt in range(max(1, int(n_try or 1))):
        check_alive(cw)
        try:
            os.replace(src, dst)
            return dst
        except OSError as value:
            error = value
            if attempt + 1 < max(1, int(n_try or 1)):
                time.sleep(min(max(0.0, float(delay or 0)), 1.0))
    raise error


def _ffmpeg_materialize(value, suffix=".bin"):
    if isinstance(value, (str, bytes, os.PathLike)) and not isinstance(value, bytes):
        return os.path.abspath(os.fspath(value)), False
    if isinstance(value, io.BytesIO):
        data = value.getvalue()
    elif isinstance(value, (bytes, bytearray, memoryview)):
        data = bytes(value)
    elif hasattr(value, "getvalue"):
        data = value.getvalue()
    elif hasattr(value, "read"):
        position = None
        try:
            position = value.tell()
        except Exception:
            pass
        data = value.read()
        if position is not None:
            try:
                value.seek(position)
            except Exception:
                pass
    else:
        return os.path.abspath(os.fspath(value)), False
    handle = tempfile.NamedTemporaryFile(prefix="hitominative-ffmpeg-input-", suffix=suffix, delete=False)
    try:
        handle.write(data)
        handle.close()
    except Exception:
        handle.close()
        try:
            os.remove(handle.name)
        except OSError:
            pass
        raise
    return handle.name, True


def _ffmpeg_temporary_output(destination, suffix=None):
    destination = os.path.abspath(os.fspath(destination))
    os.makedirs(os.path.dirname(destination) or ".", exist_ok=True)
    suffix = suffix if suffix is not None else os.path.splitext(destination)[1]
    descriptor, path = tempfile.mkstemp(
        prefix=".hitominative-ffmpeg-",
        suffix=suffix or ".tmp",
        dir=os.path.dirname(destination) or None,
    )
    os.close(descriptor)
    os.remove(path)
    return path


def _ffmpeg_replace_output(temporary, destination):
    if not os.path.isfile(temporary) or os.path.getsize(temporary) <= 0:
        raise RuntimeError("FFmpeg did not create an output file")
    os.replace(temporary, os.path.abspath(os.fspath(destination)))


def _ffmpeg_option_tokens(option):
    if option in (None, False, ""):
        return []
    if isinstance(option, str):
        return shlex.split(option, posix=True)
    return [string_value(value) or "" for value in option]


def ffmpeg_merge(video, audio, cw=None, vcodec=None, acodec=None):
    video = os.path.abspath(os.fspath(video))
    if not os.path.isfile(video):
        raise RuntimeError("No video input file")
    audio_path, temporary_audio = _ffmpeg_materialize(audio, suffix=".weba")
    if not os.path.isfile(audio_path):
        raise RuntimeError("No audio input file")
    output = _ffmpeg_temporary_output(video, suffix=".mp4")
    common = [
        "-y", "-hide_banner", "-loglevel", "error",
        "-i", video, "-i", audio_path,
        "-map", "0:v:0?", "-map", "1:a:0?",
        "-shortest", "-threads", str(FFMPEG_THREADS),
    ]
    attempts = []
    first = common + ["-c:v", string_value(vcodec) or "copy", "-c:a", string_value(acodec) or "copy"]
    attempts.append(first + ["-movflags", "+faststart", output])
    if vcodec is None and acodec is None:
        attempts.append(common + [
            "-c:v", "libx264", "-preset", "ultrafast", "-c:a", "aac",
            "-movflags", "+faststart", output,
        ])
    diagnostic = ""
    try:
        last_error = None
        for arguments in attempts:
            try:
                diagnostic = _ffmpeg_execute(arguments, cw=cw)
                last_error = None
                break
            except Exception as error:
                last_error = error
                try:
                    os.remove(output)
                except OSError:
                    pass
        if last_error is not None:
            raise last_error
        _ffmpeg_replace_output(output, video)
        if not temporary_audio and os.path.abspath(audio_path) != video:
            try:
                os.remove(audio_path)
            except OSError:
                pass
        return ".mp4", diagnostic
    finally:
        if temporary_audio:
            try:
                os.remove(audio_path)
            except OSError:
                pass
        try:
            os.remove(output)
        except OSError:
            pass


def ffmpeg_convert(input, output, option="", cw=None, remove=True, verbose=True, rn=True):
    del rn
    source = os.path.abspath(os.fspath(input))
    destination = os.path.abspath(os.fspath(output))
    if not os.path.isfile(source):
        raise RuntimeError("No input file")
    temporary = _ffmpeg_temporary_output(destination)
    arguments = ["-y", "-hide_banner", "-loglevel", "error", "-i", source]
    arguments += _ffmpeg_option_tokens(option)
    arguments += ["-threads", str(FFMPEG_THREADS), temporary]
    try:
        diagnostic = _ffmpeg_execute(arguments, cw=cw, verbose=verbose)
        _ffmpeg_replace_output(temporary, destination)
        if remove and source != destination:
            try:
                os.remove(source)
            except OSError:
                pass
        return diagnostic
    finally:
        try:
            os.remove(temporary)
        except OSError:
            pass


def _ffmpeg_scale_filter(size=None, width=-1, height=-1):
    if width not in (None, -1, 0) or height not in (None, -1, 0):
        return "scale={}:{}:flags=lanczos".format(int(width or -1), int(height or -1))
    if isinstance(size, str) and size.strip().endswith("%"):
        try:
            percent = float(size.strip()[:-1])
        except ValueError:
            percent = 100.0
        if abs(percent - 100.0) > 0.001:
            factor = max(0.01, percent / 100.0)
            return "scale=iw*{0:.6f}:ih*{0:.6f}:flags=lanczos".format(factor)
    if isinstance(size, (list, tuple)) and len(size) >= 2:
        return "scale={}:{}:flags=lanczos".format(int(size[0]), int(size[1]))
    return ""


def _ffmpeg_gif_filter(quality=90, dither=True, dither_method="bayer", scale="", fps=None):
    maximum = max(2, min(256, int(round(float(quality or 90) * 2.56))))
    method = (string_value(dither_method) or "bayer").strip().lower() if dither else "none"
    if method not in ("bayer", "heckbert", "floyd_steinberg", "sierra2", "sierra2_4a", "none"):
        raise ValueError("Unexpected dither method: {}".format(method))
    filters = []
    if fps not in (None, -1, 0, ""):
        filters.append("fps={}".format(float(fps)))
    if scale:
        filters.append(scale)
    prefix = ",".join(filters)
    if prefix:
        prefix += ","
    return (
        "{}split[s0][s1];[s0]palettegen=max_colors={}[p];"
        "[s1][p]paletteuse=dither={}"
    ).format(prefix, maximum, method)


def ffmpeg_gif_video(input, output, quality=90, dither=True, dither_method="bayer",
                     cw=None, size="100%", remove=True, verbose=True, rn=True,
                     fps=-1, start=0, end=-1):
    del rn
    source = os.path.abspath(os.fspath(input))
    destination = os.path.abspath(os.fspath(output))
    if not os.path.isfile(source):
        raise RuntimeError("No input file")
    temporary = _ffmpeg_temporary_output(destination, suffix=".gif")
    arguments = ["-y", "-hide_banner", "-loglevel", "error"]
    if start not in (None, -1, 0, ""):
        arguments += ["-ss", str(float(start))]
    arguments += ["-i", source]
    if end not in (None, -1, ""):
        duration = float(end) - float(start or 0)
        if duration > 0:
            arguments += ["-t", str(duration)]
    scale = _ffmpeg_scale_filter(size=size)
    arguments += [
        "-filter_complex", _ffmpeg_gif_filter(quality, dither, dither_method, scale, fps),
        "-loop", "0", temporary,
    ]
    try:
        diagnostic = _ffmpeg_execute(arguments, cw=cw, verbose=verbose)
        _ffmpeg_replace_output(temporary, destination)
        if remove and source != destination:
            try:
                os.remove(source)
            except OSError:
                pass
        return diagnostic
    finally:
        try:
            os.remove(temporary)
        except OSError:
            pass


def _ffmpeg_concat_line(path):
    return "file '{}'".format(path.replace("'", "'\\''"))


def _ffmpeg_frame_delay(value, fallback_fps):
    try:
        number = float(value)
    except (TypeError, ValueError):
        number = 0.0
    if number > 10.0:
        return number / 1000.0
    if number > 0:
        return number
    return 1.0 / max(1.0, float(fallback_fps or 18))


def ffmpeg_gif(filename, out, duration=18, quality=90, dither=True,
               dither_method="bayer", cw=None, remove_palette=True,
               width=-1, height=-1):
    del remove_palette
    source = os.path.abspath(os.fspath(filename))
    destination = os.path.abspath(os.fspath(out))
    if not zipfile.is_zipfile(source):
        return ffmpeg_gif_video(
            source, destination, quality=quality, dither=dither,
            dither_method=dither_method, cw=cw, size="100%", remove=False,
            fps=duration,
        )
    work = tempfile.mkdtemp(prefix="hitominative-ugoira-")
    temporary = _ffmpeg_temporary_output(destination, suffix=".gif")
    try:
        frames = []
        total_size = 0
        with zipfile.ZipFile(source) as archive:
            members = [
                member for member in archive.infolist()
                if not member.is_dir()
                and pathlib.PurePosixPath(member.filename).suffix.lower().lstrip(".") in FFMPEG_IMAGE_EXTENSIONS
            ]
            if not members:
                raise RuntimeError("Ugoira archive contains no image frames")
            if len(members) > 100000:
                raise RuntimeError("Ugoira archive contains too many frames")
            for index, member in enumerate(members):
                total_size += int(member.file_size or 0)
                if total_size > 2 * 1024 * 1024 * 1024:
                    raise RuntimeError("Ugoira archive is too large")
                suffix = pathlib.PurePosixPath(member.filename).suffix.lower() or ".jpg"
                path = os.path.join(work, "{:06d}{}".format(index, suffix))
                with archive.open(member) as source_file, open(path, "wb") as output_file:
                    shutil.copyfileobj(source_file, output_file)
                frames.append(path)
        delays = list(duration) if isinstance(duration, (list, tuple)) else []
        fallback_fps = duration if isinstance(duration, (int, float)) else 18
        manifest = os.path.join(work, "frames.txt")
        lines = []
        for index, frame in enumerate(frames):
            lines.append(_ffmpeg_concat_line(frame))
            value = delays[index] if index < len(delays) else None
            lines.append("duration {:.6f}".format(_ffmpeg_frame_delay(value, fallback_fps)))
        lines.append(_ffmpeg_concat_line(frames[-1]))
        with open(manifest, "w", encoding="utf-8") as handle:
            handle.write("\n".join(lines) + "\n")
        scale = _ffmpeg_scale_filter(width=width, height=height)
        arguments = [
            "-y", "-hide_banner", "-loglevel", "error",
            "-f", "concat", "-safe", "0", "-i", manifest,
            "-filter_complex", _ffmpeg_gif_filter(quality, dither, dither_method, scale),
            "-fps_mode", "vfr", "-loop", "0", temporary,
        ]
        diagnostic = _ffmpeg_execute(arguments, cw=cw)
        _ffmpeg_replace_output(temporary, destination)
        try:
            timestamp = os.path.getmtime(source)
            os.utime(destination, (timestamp, timestamp))
        except OSError:
            pass
        return diagnostic
    finally:
        shutil.rmtree(work, ignore_errors=True)
        try:
            os.remove(temporary)
        except OSError:
            pass


def ffmpeg_gif_force(filename, out, duration=18, quality=90, dither=True,
                     dither_method="bayer", cw=None, remove_palette=True,
                     width=-1, height=-1, force=False):
    del force
    return ffmpeg_gif(
        filename, out, duration, quality, dither, dither_method,
        cw, remove_palette, width, height,
    )


def ffmpeg_join_force(files, out, cw=None):
    paths = [os.path.abspath(os.fspath(value)) for value in files]
    if not paths:
        get_print(cw)("no files")
        return None
    for path in paths:
        if not os.path.isfile(path):
            raise RuntimeError("Missing input file: {}".format(path))

    destination = os.path.abspath(os.fspath(out))
    directory = os.path.dirname(paths[0]) or "."
    details = ffmpeg_get_info(paths[0], cw=cw, verbose=False)
    width = int(details.get("width") or 0)
    height = int(details.get("height") or 0)
    duration = float(details.get("time") or 0)
    frames = int(details.get("frames") or 0)
    if width <= 0 or height <= 0 or duration <= 0 or frames <= 0:
        raise RuntimeError("Unable to determine the target video geometry and frame rate")
    target_fps = round(frames / duration)
    if target_fps <= 0:
        raise RuntimeError("Unable to determine the target frame rate")

    work = tempfile.mkdtemp(prefix="hitominative-ffmpeg-join-force-", dir=directory)
    converted = []
    manifest = os.path.join(work, "file_list.txt")
    temporary = os.path.join(work, "tmp{}_out.mp4".format(uuid_module.uuid4().hex))
    print_ = get_print(cw)
    try:
        for index, path in enumerate(paths):
            check_alive(cw)
            converted_path = os.path.join(work, "{}_c{}.mp4".format(uuid_module.uuid4().hex, index))
            try:
                _ffmpeg_execute([
                    "-y", "-hide_banner", "-loglevel", "error",
                    "-i", path,
                    "-vf", "scale={}:{}:flags=lanczos,fps={}".format(width, height, target_fps),
                    "-c:v", "libx264", "-preset", "fast", "-crf", "23",
                    "-c:a", "aac", "-b:a", "192k",
                    "-movflags", "+faststart", "-vsync", "cfr",
                    "-af", "aresample=async=1", "-shortest", converted_path,
                ], cw=cw, cwd=directory)
                converted.append(converted_path)
            except Exception as error:
                print_(print_error(error))

        if not converted:
            raise RuntimeError("No input file could be normalized for concatenation")
        with open(manifest, "w", encoding="utf-8") as handle:
            handle.write("\n".join(_ffmpeg_concat_line(path) for path in converted) + "\n")
        if cw is not None and hasattr(cw, "trash_can"):
            cw.trash_can.extend(converted + [manifest, temporary])
        _ffmpeg_execute([
            "-y", "-hide_banner", "-loglevel", "error",
            "-f", "concat", "-safe", "0", "-i", manifest, temporary,
        ], cw=cw, cwd=directory)
        _ffmpeg_replace_output(temporary, destination)
        return None
    finally:
        shutil.rmtree(work, ignore_errors=True)


def ffmpeg_join(files, out, cw=None):
    paths = [os.path.abspath(os.fspath(value)) for value in files]
    if not paths:
        get_print(cw)("no files")
        return None
    for path in paths:
        if not os.path.isfile(path):
            raise RuntimeError("Missing input file: {}".format(path))
    destination = os.path.abspath(os.fspath(out))
    work = tempfile.mkdtemp(prefix="hitominative-ffmpeg-join-")
    temporary = _ffmpeg_temporary_output(destination)
    try:
        manifest = os.path.join(work, "files.txt")
        with open(manifest, "w", encoding="utf-8") as handle:
            handle.write("\n".join(_ffmpeg_concat_line(path) for path in paths) + "\n")
        _ffmpeg_execute([
            "-y", "-hide_banner", "-loglevel", "error",
            "-f", "concat", "-safe", "0", "-i", manifest,
            "-c", "copy", temporary,
        ], cw=cw)
        _ffmpeg_replace_output(temporary, destination)
        return None
    finally:
        shutil.rmtree(work, ignore_errors=True)
        try:
            os.remove(temporary)
        except OSError:
            pass


def _ffmpeg_escape_metadata(value):
    value = string_value(value) or ""
    return value.replace("\\", "\\\\").replace("\n", "\\n").replace("=", "\\=").replace(";", "\\;").replace("#", "\\#")


def ffmpeg_add_cover(input, cover, info, format="jpg", cw=None):
    source = os.path.abspath(os.fspath(input))
    if not os.path.isfile(source):
        raise RuntimeError("No input file")
    cover_path, temporary_cover_input = _ffmpeg_materialize(cover, suffix="." + (string_value(format) or "jpg").lstrip("."))
    destination = _ffmpeg_temporary_output(source)
    normalized_cover = _ffmpeg_temporary_output(source, suffix=".jpg")
    metadata = dict(info or {})
    try:
        _ffmpeg_execute([
            "-y", "-hide_banner", "-loglevel", "error", "-i", cover_path,
            "-frames:v", "1", "-c:v", "mjpeg", normalized_cover,
        ], cw=cw)
        arguments = [
            "-y", "-hide_banner", "-loglevel", "error",
            "-i", source, "-i", normalized_cover,
            "-map", "0", "-map", "1:v:0", "-c", "copy",
            "-disposition:v", "attached_pic", "-id3v2_version", "3",
        ]
        artist = string_value(metadata.get("artist"))
        title = string_value(metadata.get("title"))
        if artist:
            arguments += ["-metadata", "artist={}".format(artist.replace('"', ""))]
        if title:
            arguments += ["-metadata", "album={}".format(title.replace('"', ""))]
        arguments.append(destination)
        _ffmpeg_execute(arguments, cw=cw)
        _ffmpeg_replace_output(destination, source)
        return None
    finally:
        if temporary_cover_input:
            try:
                os.remove(cover_path)
            except OSError:
                pass
        for path in (destination, normalized_cover):
            try:
                os.remove(path)
            except OSError:
                pass


class CompatFFmpegChapter:
    def __init__(self, title, start, end):
        self.title = string_value(title) or ""
        self.start = float(start or 0)
        self.end = float(end or self.start)


def ffmpeg_add_chapters(input, chapters, cw=None):
    chapters = list(chapters or [])
    if not chapters:
        return None
    source = os.path.abspath(os.fspath(input))
    if not os.path.isfile(source):
        raise RuntimeError("No input file")
    destination = _ffmpeg_temporary_output(source)
    descriptor, metadata_path = tempfile.mkstemp(prefix="hitominative-chapters-", suffix=".ffmeta")
    os.close(descriptor)
    try:
        lines = [";FFMETADATA1"]
        for value in chapters:
            chapter = value if isinstance(value, CompatFFmpegChapter) else CompatFFmpegChapter(
                value.get("title", ""), value.get("start", value.get("start_time", 0)),
                value.get("end", value.get("end_time", 0)),
            )
            start = max(0, int(round(chapter.start * 1000)))
            end = max(start, int(round(chapter.end * 1000)))
            lines += [
                "[CHAPTER]", "TIMEBASE=1/1000", "START={}".format(start),
                "END={}".format(end), "title={}".format(_ffmpeg_escape_metadata(chapter.title)),
            ]
        with open(metadata_path, "w", encoding="utf-8") as handle:
            handle.write("\n".join(lines) + "\n")
        _ffmpeg_execute([
            "-y", "-hide_banner", "-loglevel", "error",
            "-i", source, "-i", metadata_path,
            "-map", "0", "-map_metadata", "0", "-map_chapters", "1",
            "-codec", "copy", destination,
        ], cw=cw)
        _ffmpeg_replace_output(destination, source)
        return None
    finally:
        for path in (destination, metadata_path):
            try:
                os.remove(path)
            except OSError:
                pass


def ffmpeg_is_image(file):
    return pathlib.Path(os.fspath(file)).suffix.lower().lstrip(".") in FFMPEG_IMAGE_EXTENSIONS


def ffmpeg_s2secs(value):
    text = string_value(value) or "0"
    try:
        parts = [float(part) for part in text.strip().split(":")]
    except ValueError:
        return 0.0
    total = 0.0
    for part in parts:
        total = total * 60.0 + part
    return total


def ffmpeg_s2size(value):
    text = (string_value(value) or "0").strip()
    match = re.match(r"^([0-9]+(?:\.[0-9]+)?)\s*([kmgtpe]?i?b)?$", text, re.I)
    if not match:
        return 0
    number = float(match.group(1))
    unit = (match.group(2) or "b").lower()
    powers = {"b": 0, "kb": 1, "kib": 1, "mb": 2, "mib": 2, "gb": 3, "gib": 3,
              "tb": 4, "tib": 4, "pb": 5, "pib": 5, "eb": 6, "eib": 6}
    return int(number * (1024 ** powers.get(unit, 0)))


def _ffmpeg_duration(stream):
    for value in (stream.get("duration"), (stream.get("tags") or {}).get("DURATION"),
                  (stream.get("tags") or {}).get("duration")):
        if value not in (None, "", "N/A"):
            try:
                return float(value)
            except (TypeError, ValueError):
                parsed = ffmpeg_s2secs(value)
                if parsed:
                    return parsed
    try:
        duration_ts = float(stream.get("duration_ts"))
        numerator, denominator = (stream.get("time_base") or "0/1").split("/", 1)
        return duration_ts * float(numerator) / float(denominator)
    except (TypeError, ValueError, ZeroDivisionError):
        return 0.0


def ffmpeg_get_info(file, cw=None, lock=True, allow_transcode=True, verbose=True):
    del allow_transcode
    path = os.path.abspath(os.fspath(file))
    output, code = ffmpeg_run([
        "-v", "error", "-show_streams", "-show_format", "-print_format", "json", path,
    ], cw=cw, timeout=30, lock=lock, bin="ffprobe", verbose=verbose)
    if code != 0:
        raise RuntimeError("ffprobe failed ({}): {}".format(code, _ffmpeg_tail(output)))
    try:
        data = json.loads(output)
    except json.JSONDecodeError as error:
        raise RuntimeError("ffprobe returned invalid JSON: {}".format(error))
    width = 0
    height = 0
    duration = 0.0
    frames = 0
    for stream in data.get("streams") or []:
        width = max(width, int(stream.get("width") or 0))
        height = max(height, int(stream.get("height") or 0))
        duration = max(duration, _ffmpeg_duration(stream))
        raw_frames = stream.get("nb_frames") or stream.get("nb_read_frames") or 0
        try:
            frames = max(frames, int(raw_frames))
        except (TypeError, ValueError):
            pass
    try:
        duration = max(duration, float((data.get("format") or {}).get("duration") or 0))
    except (TypeError, ValueError):
        pass
    return {"width": width, "height": height, "time": duration, "frames": frames}


def ffmpeg_capture(file, out=None, t="20%", cw=None, lock=True, info=None,
                   verbose=False, ext=".png"):
    source = os.path.abspath(os.fspath(file))
    details = None
    if isinstance(t, str) and t.strip().endswith("%"):
        details = ffmpeg_get_info(source, cw=cw, lock=lock, verbose=verbose) if not ffmpeg_is_image(source) else {"time": 0}
        seek = float(t.strip()[:-1] or 0) * float(details.get("time") or 0) / 100.0
    else:
        seek = float(t or 0)
    if info is not None and details:
        info.update(details)
    destination = os.path.abspath(os.fspath(out)) if out else tempfile.mktemp(prefix="hitominative-capture-", suffix=ext)
    temporary = _ffmpeg_temporary_output(destination, suffix=ext)
    try:
        _ffmpeg_execute([
            "-y", "-hide_banner", "-loglevel", "error", "-ss", str(max(0.0, seek)),
            "-i", source, "-frames:v", "1", temporary,
        ], cw=cw, timeout=30, verbose=verbose)
        _ffmpeg_replace_output(temporary, destination)
        return destination
    finally:
        try:
            os.remove(temporary)
        except OSError:
            pass


def ffmpeg_capture_fast(file, out=None, t="20%", cw=None, lock=True, info=None, verbose=True):
    return ffmpeg_capture(file, out, t, cw, lock, info, verbose)


def _ffmpeg_progress_info(line):
    info = {"line": line}
    duration = re.search(r"Duration\s*:\s*([0-9:.]+)", line)
    current = re.search(r"time\s*=\s*([0-9:.]+)", line)
    size = re.search(r"size\s*=\s*([^ ]+)", line)
    if duration:
        info["duration"] = ffmpeg_s2secs(duration.group(1))
    if current:
        info["t"] = ffmpeg_s2secs(current.group(1))
    if size:
        info["size"] = ffmpeg_s2size(size.group(1))
    return info


def ffmpeg_pipe(url, filename, *, options=None, hook=None, cw=None, headers=None,
                format=None, callback=None, oprinter=None):
    check_alive(cw)
    destination = os.path.abspath(os.fspath(filename))
    os.makedirs(os.path.dirname(destination) or ".", exist_ok=True)
    default_tokens = _ffmpeg_option_tokens(FFMPEG_DEFAULT_PIPE_OPTIONS)
    if options is None:
        option_tokens = default_tokens
    else:
        option_text = string_value(options) or ""
        if "{default}" in option_text:
            option_text = option_text.replace("{default}", FFMPEG_DEFAULT_PIPE_OPTIONS)
        option_tokens = _ffmpeg_option_tokens(option_text)
    arguments = ["-y", "-hide_banner"]
    if format:
        arguments += ["-f", string_value(format)]
    header_values = normalized_headers(headers)
    if header_values:
        arguments += ["-headers", "".join("{}: {}\r\n".format(key, value) for key, value in header_values.items())]
    arguments += ["-i", clean_url(url)] + option_tokens + [destination]
    command = [_ffmpeg_executable("ffmpeg")] + arguments
    process = CompatFFmpegPopen(command, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True, bufsize=1)
    code = -1
    try:
        for line in process.stderr or []:
            line = line.rstrip("\r\n")
            if oprinter is not None and hasattr(oprinter, "print_"):
                oprinter.print_(line)
            if callable(hook):
                hook(_ffmpeg_progress_info(line))
            if cw is not None and getattr(cw, "alive", True) is False:
                ffmpeg_kill(process)
                break
        code = process.wait()
    finally:
        FFMPEG_PROCESSES.discard(process)
    if callable(callback):
        callback(code)
    return code


def ffmpeg_print_res(process, cw=None):
    del cw
    if process is not None and process.poll() is None:
        return None
    FFMPEG_PROCESSES.discard(process)
    return getattr(process, "returncode", None)


class CompatFFmpegStream:
    size_prev = 0
    _live = True
    _more = None
    oprinter = None
    stream_type = "m3u8"
    live = True
    post_processing = None
    deco = None
    alter = None
    referer_seg = "auto"

    def __init__(self, url, *, options=None, cw=None, headers=None, format=None,
                 callback=None, fragments=None):
        self._url = clean_url(url)
        self._options = options
        self._cw = cw
        self._headers = normalized_headers(headers)
        self.headers = dict(self._headers)
        self._format = format
        self._callback = callback
        self._fragments = fragments
        self.base_url = self._url
        self.session = Session(cw)
        self.session.headers.update(self._headers)
        self.referer = next((value for key, value in self._headers.items()
                             if key.lower() == "referer"), None)
        self.user_agent = next((value for key, value in self._headers.items()
                                if key.lower() == "user-agent"), None)
        self.info = {
            "python_stream_source": "ffmpeg.Stream",
            "live": "true",
            "is_live": "true",
        }
        self.urls = []
        self.others = []
        self._hitomi_native_preferred_resolution = None
        self._filename = None
        self._progress = None
        self._size = None
        self.t = None
        self.returncode = None
        self.error = None
        self._no_space = False

    @property
    def url(self):
        return self._url

    def _hook(self, info):
        line = string_value(info.get("line")) or ""
        if "No space left on device" in line:
            self._no_space = True
        progress = self._progress
        if progress is not None:
            duration = info.get("duration") or 0
            current = info.get("t") or 0
            if duration and hasattr(progress, "maximum"):
                progress.maximum = duration
            if current and hasattr(progress, "value"):
                progress.value = current
        if callable(self._callback):
            self._callback(info)

    def _download_fragments(self):
        fragments = self._fragments({}) if callable(self._fragments) else self._fragments
        with open(self._filename, "wb") as output:
            for fragment in list(fragments or []):
                check_alive(self._cw)
                url = clean_url(fragment.get("url") if isinstance(fragment, dict) else fragment)
                request = urllib.request.Request(url, headers=self._headers)
                with urllib.request.urlopen(request, timeout=60) as response:
                    shutil.copyfileobj(response, output)
        self.returncode = 0

    def _run(self):
        try:
            if self._fragments:
                self._download_fragments()
            else:
                self.returncode = ffmpeg_pipe(
                    self._url, self._filename, hook=self._hook, options=self._options,
                    cw=self._cw, headers=self._headers, format=self._format,
                )
            if self.returncode not in (None, 0):
                raise RuntimeError("ffmpeg pipe failed ({})".format(self.returncode))
        except Exception as error:
            self.error = error

    def open(self, filename, progress=None, size=None):
        self._filename = os.path.abspath(os.fspath(filename))
        self._progress = progress
        self._size = size
        self.t = threading.Thread(target=self._run, daemon=True, name="ffmpeg.Stream pipe")
        self.t.start()
        return self

    def close(self):
        if self.t is not None:
            self.t.join()
        if self.error is not None:
            raise self.error
        if self._no_space:
            raise OSError("No space left on device")

        temporary_outputs = []
        try:
            if self._more:
                ffmpeg_join([self._filename, self._more], self._filename, self._cw)
            if self.others:
                name, extension = os.path.splitext(self._filename)
                for index, other in enumerate(self.others):
                    output = "{}_p{}{}".format(name, index, extension)
                    get_print(self._cw)("others: {}".format(output))
                    temporary_outputs.append(output)
                    if self._cw is not None and hasattr(self._cw, "trash_can"):
                        self._cw.trash_can.append(output)
                    opened = other.open(output, self._progress, self._size)
                    if opened.t is not None:
                        opened.t.join()
                    opened.close()

                def combine():
                    ffmpeg_join([self._filename] + temporary_outputs, self._filename, self._cw)

                converter = getattr(self._cw, "convert", None) if self._cw is not None else None
                conversion = converter(self._filename) if callable(converter) else None
                if hasattr(conversion, "__enter__") and hasattr(conversion, "__exit__"):
                    with conversion:
                        combine()
                else:
                    combine()
        finally:
            cleanup = list(temporary_outputs)
            if self._more:
                cleanup.append(self._more)
            for path in cleanup:
                try:
                    os.remove(path)
                except OSError:
                    pass
        return None

    def __repr__(self):
        name = "Stream({})".format(self._url)
        if self.others:
            name += " (+{})".format(len(self.others))
        return name

    def __add__(self, other):
        self.others.append(other)
        return self


YTDL_DOWNLOAD = False
YTDL_OPTIONS = {
    "subtitlesformat": "vtt",
    "nocheckcertificate": True,
    "hls_use_mpegts": True,
    "overwrites": True,
    "nopart": True,
}
YTDL_LIVE_FROM_START = {
    "twitch": False,
    "youtube": False,
    "nico": False,
}
YTDL_METADATA_LIMIT = 64 * 1024 * 1024
YTDL_METADATA_TIMEOUT = 180


def _option_bool(value):
    if isinstance(value, str):
        return value.strip().lower() not in ("", "0", "false", "no", "off", "none")
    return bool(value)


def _option_list(value):
    if value is None:
        return []
    if isinstance(value, str):
        return [item.strip() for item in value.split(",") if item.strip()]
    if isinstance(value, (list, tuple, set)):
        return [string_value(item) for item in value if string_value(item)]
    return [string_value(value)]


def _ytdlp_executable():
    path = os.environ.get("HITOMI_NATIVE_YTDLP", "").strip()
    if not path:
        raise RuntimeError(
            "yt-dlp is not installed. Open Settings > External Tools to install it "
            "before running this Python extractor."
        )
    path = os.path.abspath(os.path.expanduser(path))
    if not os.path.isfile(path) or not os.access(path, os.X_OK):
        raise RuntimeError("Configured yt-dlp executable is unavailable: {}".format(path))
    return path


def _clean_cli_value(value):
    value = string_value(value) or ""
    return value.replace("\x00", "").replace("\r", " ").replace("\n", " ").strip()


def _extractor_args_value(value):
    if isinstance(value, str):
        return value.strip()
    parts = []
    for extractor_name, arguments in dict(value or {}).items():
        values = []
        for key, item in dict(arguments or {}).items():
            joined = ",".join(_option_list(item))
            values.append("{}={}".format(key, joined))
        if values:
            parts.append("{}:{}".format(extractor_name, ";".join(values)))
    return ";".join(parts)


@contextlib.contextmanager
def _ytdlp_cookie_path(session, source_url):
    cookies = []
    if session is not None:
        try:
            cookies = list(session.cookies)
        except (AttributeError, TypeError):
            cookies = []
    if not cookies:
        yield None
        return

    host = urllib.parse.urlsplit(source_url).hostname or "localhost"
    handle = tempfile.NamedTemporaryFile(
        mode="w", encoding="utf-8", prefix="hitominative-ytdlp-",
        suffix=".cookies.txt", delete=False
    )
    try:
        handle.write("# Netscape HTTP Cookie File\n")
        for cookie in cookies:
            domain = _clean_cli_value(getattr(cookie, "domain", None)) or host
            path = _clean_cli_value(getattr(cookie, "path", None)) or "/"
            include_subdomains = "TRUE" if domain.startswith(".") else "FALSE"
            secure = "TRUE" if bool(getattr(cookie, "secure", False)) else "FALSE"
            expires = int(getattr(cookie, "expires", 0) or 0)
            name = _clean_cli_value(getattr(cookie, "name", None))
            value = _clean_cli_value(getattr(cookie, "value", None))
            if not name:
                continue
            handle.write("{}\t{}\t{}\t{}\t{}\t{}\t{}\n".format(
                domain, include_subdomains, path, secure, expires, name, value
            ))
        handle.close()
        yield handle.name
    finally:
        try:
            handle.close()
        except Exception:
            pass
        try:
            os.remove(handle.name)
        except OSError:
            pass


def _ytdlp_error_text(stderr, stdout):
    text = (stderr or stdout or b"").decode("utf-8", "replace")
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    return " ".join(lines[-8:]) or "yt-dlp returned no diagnostic output"


def _ytdlp_json(stdout):
    if len(stdout) > YTDL_METADATA_LIMIT:
        raise RuntimeError("yt-dlp metadata exceeded 64 MiB")
    text = stdout.decode("utf-8", "replace").strip()
    try:
        value = json.loads(text)
    except json.JSONDecodeError:
        value = None
        for line in reversed(text.splitlines()):
            try:
                value = json.loads(line)
                break
            except json.JSONDecodeError:
                continue
    if not isinstance(value, dict):
        raise RuntimeError("yt-dlp did not return a metadata object")
    return value


def _normalized_ytdl_headers(value):
    return {
        _clean_cli_value(key): _clean_cli_value(item)
        for key, item in dict(value or {}).items()
        if _clean_cli_value(key) and _clean_cli_value(item)
    }


def _normalize_ytdl_info(info, session_headers=None, depth=0):
    if not isinstance(info, dict):
        return info
    info = dict(info)
    base_url = clean_url(info.get("webpage_url") or info.get("original_url"))
    shared_headers = _normalized_ytdl_headers(session_headers)
    shared_headers.update(_normalized_ytdl_headers(info.get("http_headers")))

    if info.get("thumbnail") and base_url:
        info["thumbnail"] = urllib.parse.urljoin(base_url, clean_url(info["thumbnail"]))
    if isinstance(info.get("thumbnails"), list):
        for thumbnail in info["thumbnails"]:
            if isinstance(thumbnail, dict) and thumbnail.get("url") and base_url:
                thumbnail["url"] = urllib.parse.urljoin(base_url, clean_url(thumbnail["url"]))
    for group_name in ("requested_subtitles", "subtitles", "automatic_captions"):
        for values in dict(info.get(group_name) or {}).values():
            if not isinstance(values, list):
                values = [values]
            for subtitle in values:
                if isinstance(subtitle, dict) and subtitle.get("url") and base_url:
                    subtitle["url"] = urllib.parse.urljoin(base_url, clean_url(subtitle["url"]))

    formats = []
    for raw_format in info.get("formats") or []:
        if not isinstance(raw_format, dict):
            continue
        value = dict(raw_format)
        url = clean_url(value.get("url"))
        if not url:
            continue
        if base_url:
            url = urllib.parse.urljoin(base_url, url)
        value["url"] = url
        value["ext"] = string_value(value.get("ext")) or get_ext(url, ".bin").lstrip(".")
        value["format_id"] = string_value(value.get("format_id")) or "native"
        if not value.get("format"):
            label = value.get("format_note") or value.get("resolution") or value.get("format_id")
            value["format"] = string_value(label) or value["format_id"]
        if not value.get("protocol"):
            lower_url = url.lower()
            if ".m3u8" in lower_url:
                value["protocol"] = "m3u8_native"
            elif ".mpd" in lower_url:
                value["protocol"] = "http_dash_segments"
            else:
                value["protocol"] = urllib.parse.urlsplit(url).scheme or "https"
        headers = dict(shared_headers)
        headers.update(_normalized_ytdl_headers(value.get("http_headers")))
        value["http_headers"] = headers
        formats.append(value)
    info["formats"] = formats
    info["http_headers"] = shared_headers

    if depth < 4 and isinstance(info.get("entries"), list):
        info["entries"] = [
            _normalize_ytdl_info(entry, shared_headers, depth + 1)
            for entry in info["entries"] if isinstance(entry, dict)
        ]
    return info


class CompatYoutubeDL:
    def __init__(self, params=None, auto_init=True, verbose=None, *, cw=None,
                 type=None, options=None):
        del auto_init
        self.params = dict(YTDL_OPTIONS)
        self.params.update(dict(options or {}))
        self.params.update(dict(params or {}))
        if verbose is not None:
            self.params["verbose"] = bool(verbose)
        self.cw = cw
        self.type = type
        downloader_instance = getattr(cw, "downloader", None) if cw is not None else None
        self.session = getattr(downloader_instance, "session", None) or Session()
        self.cookiejar = self.session.cookies
        self._progress_hooks = []
        self._downloader = None

        downloader_type = string_value(getattr(downloader_instance, "type", None))
        if downloader_type and YTDL_LIVE_FROM_START.get(downloader_type):
            self.params.setdefault("live_from_start", True)
        headers = _normalized_ytdl_headers(getattr(self.session, "headers", None))
        if headers:
            merged = dict(headers)
            merged.update(_normalized_ytdl_headers(self.params.get("http_headers")))
            self.params["http_headers"] = merged
            user_agent = next((item for key, item in merged.items()
                               if key.lower() == "user-agent"), None)
            if user_agent:
                self.params.setdefault("user_agent", user_agent)

    def add_progress_hook(self, hook):
        if callable(hook):
            self._progress_hooks.append(hook)

    def to_screen(self, message, *args, **kwargs):
        del args, kwargs
        get_print(self.cw)("[ytdl] {}".format(message))

    def report_warning(self, message, *args, **kwargs):
        self.to_screen(message, *args, **kwargs)

    def urlopen(self, request):
        if hasattr(request, "full_url"):
            return urllib.request.urlopen(request)
        return urllib.request.urlopen(clean_url(request))

    def _arguments(self, url, download, ie_key, force_generic_extractor, cookie_path):
        params = self.params
        args = [
            "--ignore-config",
            "--no-plugin-dirs",
            "--dump-single-json",
            "--skip-download",
            "--no-progress",
            "--no-warnings",
            "--no-colors",
        ]
        ffmpeg = os.environ.get("HITOMI_NATIVE_FFMPEG", "").strip()
        if ffmpeg and os.path.isfile(ffmpeg) and os.access(ffmpeg, os.X_OK):
            args.extend(["--ffmpeg-location", os.path.dirname(os.path.abspath(ffmpeg))])
        deno = os.environ.get("HITOMI_NATIVE_DENO", "").strip()
        if deno and os.path.isfile(deno) and os.access(deno, os.X_OK):
            args.extend(["--js-runtimes", "deno:{}".format(os.path.abspath(deno))])

        boolean_flags = (
            ("nocheckcertificate", "--no-check-certificates"),
            ("ignore_no_formats_error", "--ignore-no-formats-error"),
            ("allow_unplayable_formats", "--allow-unplayable-formats"),
            ("live_from_start", "--live-from-start"),
            ("playlistreverse", "--playlist-reverse"),
            ("writesubtitles", "--write-subs"),
            ("writeautomaticsub", "--write-auto-subs"),
            ("allsubtitles", "--all-subs"),
        )
        for option, flag in boolean_flags:
            if _option_bool(params.get(option)):
                args.append(flag)

        if _option_bool(params.get("extract_flat")):
            args.append("--flat-playlist")
        if _option_bool(params.get("noplaylist")):
            args.append("--no-playlist")
        elif _option_bool(params.get("yesplaylist")):
            args.append("--yes-playlist")
        if force_generic_extractor or (string_value(ie_key) or "").lower() == "generic":
            args.append("--force-generic-extractor")

        value_options = (
            ("playliststart", "--playlist-start"),
            ("playlistend", "--playlist-end"),
            ("playlist_items", "--playlist-items"),
            ("socket_timeout", "--socket-timeout"),
            ("retries", "--retries"),
            ("fragment_retries", "--fragment-retries"),
            ("extractor_retries", "--extractor-retries"),
            ("age_limit", "--age-limit"),
            ("format", "--format"),
            ("subtitlesformat", "--sub-format"),
            ("username", "--username"),
            ("password", "--password"),
            ("twofactor", "--twofactor"),
            ("videopassword", "--video-password"),
            ("impersonate", "--impersonate"),
        )
        for option, flag in value_options:
            value = params.get(option)
            if value is not None and _clean_cli_value(value):
                args.extend([flag, _clean_cli_value(value)])

        subtitle_languages = _option_list(params.get("subtitleslangs"))
        if subtitle_languages:
            args.extend(["--sub-langs", ",".join(subtitle_languages)])
        format_sort = _option_list(params.get("format_sort"))
        if format_sort:
            args.extend(["--format-sort", ",".join(format_sort)])
        extractor_args = _extractor_args_value(params.get("extractor_args"))
        if extractor_args:
            args.extend(["--extractor-args", extractor_args])

        proxy = params.get("proxy")
        if not proxy:
            proxies = getattr(self.session, "proxies", {}) or {}
            proxy = proxies.get("https") or proxies.get("http")
        if proxy:
            args.extend(["--proxy", _clean_cli_value(proxy)])

        headers = _normalized_ytdl_headers(getattr(self.session, "headers", None))
        headers.update(_normalized_ytdl_headers(params.get("http_headers")))
        user_agent = _clean_cli_value(params.get("user_agent"))
        referer = _clean_cli_value(params.get("referer"))
        for key, value in headers.items():
            lower = key.lower()
            if lower == "user-agent" and not user_agent:
                user_agent = value
            elif lower in ("referer", "referrer") and not referer:
                referer = value
            elif lower != "cookie":
                args.extend(["--add-headers", "{}:{}".format(key, value)])
        if user_agent:
            args.extend(["--user-agent", user_agent])
        if referer:
            args.extend(["--referer", referer])

        configured_cookie_file = _clean_cli_value(params.get("cookiefile"))
        if configured_cookie_file and os.path.isfile(configured_cookie_file):
            args.extend(["--cookies", configured_cookie_file])
        elif cookie_path:
            args.extend(["--cookies", cookie_path])

        if download not in (None, False):
            self.to_screen("extract_info(download=True) is resolved by the native host")
        args.append(url)
        return args

    def extract_info(self, url, download=None, ie_key=None, extra_info=None,
                     process=True, force_generic_extractor=False):
        del process
        url = clean_url(url)
        if urllib.parse.urlsplit(url).scheme.lower() not in ("http", "https"):
            raise ValueError("ERROR: Unsupported URL: {}".format(url))
        with _ytdlp_cookie_path(self.session, url) as cookie_path:
            arguments = self._arguments(
                url, download, ie_key, force_generic_extractor, cookie_path
            )
            try:
                completed = subprocess.run(
                    [_ytdlp_executable()] + arguments,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    timeout=YTDL_METADATA_TIMEOUT,
                    check=False,
                    env=os.environ.copy(),
                )
            except subprocess.TimeoutExpired:
                raise RuntimeError(
                    "yt-dlp metadata extraction timed out after {} seconds".format(
                        YTDL_METADATA_TIMEOUT
                    )
                )
        if completed.returncode != 0:
            raise RuntimeError(_ytdlp_error_text(completed.stderr, completed.stdout))
        info = _ytdlp_json(completed.stdout)
        if extra_info:
            info.update(dict(extra_info))
        return _normalize_ytdl_info(info, getattr(self.session, "headers", None))


YTDL_EXTRACTOR_PATTERNS = (
    (r"(?:youtube\.com|youtu\.be|yewtu\.be)", "youtube"),
    (r"(?:twitch\.tv)", "twitch"),
    (r"(?:nicovideo\.jp|niconico\.com|nico\.ms)", "niconico"),
    (r"(?:soundcloud\.com)", "soundcloud"),
    (r"(?:vimeo\.com)", "vimeo"),
    (r"(?:twitter\.com|x\.com)", "twitter"),
    (r"(?:tiktok\.com|douyin\.com)", "tiktok"),
    (r"(?:pornhub\.com|pornhubpremium\.com)", "pornhub"),
    (r"(?:xhamster\.)", "xhamster"),
    (r"(?:youporn\.com)", "youporn"),
    (r"(?:youku\.com)", "youku"),
    (r"(?:bilibili\.com|b23\.tv)", "bilibili"),
    (r"(?:coub\.com)", "coub"),
    (r"(?:tv\.kakao\.com)", "kakao"),
    (r"(?:tv\.naver\.com|chzzk\.naver\.com)", "naver"),
    (r"(?:spankbang\.)", "spankbang"),
)
YTDL_EXTRACTOR_CLASSES = {}


def _extractor_name_for_url(url):
    value = clean_url(url).lower()
    for pattern, name in YTDL_EXTRACTOR_PATTERNS:
        if re.search(pattern, value):
            return name
    return "generic"


def _extractor_class(name):
    if name in YTDL_EXTRACTOR_CLASSES:
        return YTDL_EXTRACTOR_CLASSES[name]

    def init(self, downloader=None):
        self._downloader = downloader

    def suitable(cls, url):
        return _extractor_name_for_url(url) == name

    def match_id(self, url):
        path = urllib.parse.urlsplit(clean_url(url)).path.rstrip("/")
        return pathlib.PurePosixPath(path).name

    extractor_class = type(
        "{}IE".format(name.title().replace("_", "")),
        (),
        {
            "__init__": init,
            "suitable": classmethod(suitable),
            "_match_id": match_id,
            "IE_NAME": name,
            "__module__": "yt_dlp.extractor.{}".format(name),
        },
    )
    YTDL_EXTRACTOR_CLASSES[name] = extractor_class
    return extractor_class


def get_extractor(url, cache=True):
    del cache
    name = _extractor_name_for_url(url)
    if name in ("generic", "youtube"):
        return None
    return _extractor_class(name)()


def extractor_to_name(value):
    if value is None:
        return "generic"
    return string_value(getattr(value, "__module__", "")).split(".")[-1] or "generic"


def get_extractor_name(url):
    return extractor_to_name(get_extractor(url))


class CompatYTDLExtractorNamespace:
    @staticmethod
    def gen_extractors():
        return [_extractor_class(name)() for _pattern, name in YTDL_EXTRACTOR_PATTERNS]


class CompatYTDLUtilsNamespace:
    sanitized_Request = urllib.request.Request
    sanitized_request = urllib.request.Request


class CompatYTDLDownloaderNamespace:
    @staticmethod
    def get_suitable_downloader(_info, _params):
        return CompatYTDLDownloader


class CompatYTDLRuntime:
    __name__ = "yt_dlp"
    extractor = CompatYTDLExtractorNamespace()
    utils = CompatYTDLUtilsNamespace()
    downloader = CompatYTDLDownloaderNamespace()
    YoutubeDL = CompatYoutubeDL


YTDL_RUNTIME = CompatYTDLRuntime()


def get_ytdl(module_name=None, url_pypi=None, allow_reload=True):
    del module_name, url_pypi, allow_reload
    return YTDL_RUNTIME


def _format_session(session, value):
    if session is None:
        result = Session()
    else:
        result = Session.load(session.dump())
    result.headers.update(_normalized_ytdl_headers(value.get("http_headers")))
    return result


def _format_is_hls(value):
    protocol = (string_value(value.get("protocol")) or "").lower()
    url = clean_url(value.get("url")).lower()
    return protocol.startswith("m3u8") or ".m3u8" in url


def _format_is_dash(value):
    protocol = (string_value(value.get("protocol")) or "").lower()
    url = clean_url(value.get("url")).lower()
    return protocol in ("dash", "http_dash_segments") and ".mpd" in url


def _format_metadata(value):
    return {
        key: string_value(value.get(key))
        for key in ("format_id", "format", "ext", "protocol", "resolution", "vcodec", "acodec")
        if value.get(key) is not None
    }


def _format_native_asset(value, session=None, source_url=None, live=False):
    value = dict(value or {})
    url = clean_url(value.get("url"))
    if not url:
        raise ValueError("yt-dlp format has no URL")
    format_session = _format_session(session, value)
    referer = next((item for key, item in format_session.headers.items()
                    if key.lower() in ("referer", "referrer")), None)
    referer = referer or clean_url(source_url)
    if _format_is_hls(value):
        return M3u8Stream(
            url, base_url=url, referer=referer, session=format_session,
            info=_format_metadata(value), live=live
        )
    if _format_is_dash(value):
        return DashStream(
            url, base_url=url, referer=referer, session=format_session,
            info=_format_metadata(value), live=live
        )
    headers = dict(format_session.headers)
    if not any(key.lower() == "cookie" for key in headers):
        cookies = format_session.cookies.get_dict()
        if cookies:
            headers["Cookie"] = "; ".join(
                "{}={}".format(key, item) for key, item in cookies.items()
            )
    return {
        "url": url,
        "referer": referer,
        "headers": headers,
        "metadata": _format_metadata(value),
    }


class CompatYTDLDownloader:
    def __init__(self, ydl, info, format, live=False, cw=None):
        self.ydl = ydl
        self.info = dict(info or {})
        self._format = dict(format or {})
        self._url = clean_url(self._format.get("url"))
        self.live = bool(live)
        self.cw = cw
        self.session = getattr(ydl, "session", None) or Session()

    def native_asset(self):
        source_url = self.info.get("webpage_url") or self.info.get("original_url")
        return _format_native_asset(
            self._format, self.session, source_url=source_url, live=self.live
        )

    def stop(self):
        return None

    def download(self, _filename):
        raise RuntimeError("ytdl.Downloader downloads are performed by the native host")

    def progress_hook(self, status):
        get_print(self.cw)(status)

    def __str__(self):
        return self._url

    def __repr__(self):
        return "ytdl.Downloader({})".format(self._url)


class CompatYTDLVideo:
    def __init__(self, url, video, *, live=False, session=None):
        self.live = bool(live)
        self._url = clean_url(url)
        self.video = dict(video or {})
        self.format = string_value(self.video.get("format")) or string_value(
            self.video.get("format_id")
        ) or "unknown"
        self.subtype = string_value(self.video.get("ext")) or "bin"
        self.video_codec = string_value(self.video.get("vcodec"))
        self.audio_codec = string_value(self.video.get("acodec"))
        if (self.video_codec or "").lower() == "none":
            self.video_codec = None
        if (self.audio_codec or "").lower() == "none":
            self.audio_codec = None
        self.abr = self.video.get("abr") if self.audio_codec else None
        self.tbr = self.video.get("tbr")
        if self.abr is None and self.audio_codec:
            self.abr = self.tbr
        self.abr_str = "{}kbps".format(self.abr) if self.abr is not None else None
        self.abr_fixed = bool(self.video.get("abr_fixed", False))
        height = self.video.get("height")
        if height:
            self.resolution = "{}p".format(height)
        else:
            match = re.search(r"(?:x|\b)([0-9]{3,4})p?\b", self.format)
            self.resolution = "{}p".format(match.group(1)) if match else None
        self.fps = self.video.get("fps") or 0
        self._dash_type = None
        asset = _format_native_asset(
            self.video, session=session, source_url=self._url, live=self.live
        )
        self.url = asset.get("url") if isinstance(asset, dict) else asset

    def setDashType(self, type_):
        self._dash_type = type_

    def __repr__(self):
        return "Video({}, {})".format(self.format, self.subtype)


class CompatYouTube:
    def __init__(self, url, cw=None):
        self.url = clean_url(url)
        self.streams = Nothing()
        self.streams.all = self.streams_all
        self.videos = []
        ydl = CompatYoutubeDL({"ignore_no_formats_error": True}, cw=cw)
        self.info = ydl.extract_info(self.url)
        live = bool(self.info.get("is_live"))
        for value in self.info.get("formats") or []:
            try:
                self.videos.append(
                    CompatYTDLVideo(self.url, value, live=live, session=ydl.session)
                )
            except Exception as error:
                get_print(cw)("[ytdl] skipped format: {}".format(error))
        self.title = self.info.get("fulltitle") or self.info.get("title") or "video"
        self.video_id = string_value(self.info.get("id")) or ""
        self.watch_url = self.info.get("webpage_url") or self.url
        self.thumbnail_url = clean_url(self.info.get("thumbnail"))
        self.subtitles = get_subtitles(self.info)

    def streams_all(self):
        return list(self.videos)


def get_subtitles(info):
    result = {}
    for group_name in ("requested_subtitles", "subtitles", "automatic_captions"):
        for language, values in dict((info or {}).get(group_name) or {}).items():
            if not isinstance(values, list):
                values = [values]
            language = string_value(language).lower().replace("_", "-")
            selected = next((value for value in values
                             if isinstance(value, dict) and value.get("ext") == "vtt"
                             and value.get("url")), None)
            if selected:
                result[language] = clean_url(selected["url"])
    return result


def download_thumb(thumbnail_url, cw=None, session=None):
    session = session or getattr(getattr(cw, "downloader", None), "session", None) or Session()
    original = clean_url(thumbnail_url)
    candidates = []
    for quality in ("maxresdefault", "sddefault", "hqdefault", "mqdefault", "default"):
        candidate = re.sub(
            r"(?:maxresdefault|sddefault|hqdefault|mqdefault|default)", quality, original
        )
        if candidate not in candidates:
            candidates.append(candidate)
    if original and original not in candidates:
        candidates.append(original)
    last_error = None
    for candidate in candidates:
        try:
            response = session.get(candidate, timeout=30)
            response.raise_for_status()
            if response.content:
                return candidate, io.BytesIO(response.content)
        except Exception as error:
            last_error = error
    if last_error is not None:
        raise last_error
    raise RuntimeError("Empty thumbnail")


YTDL_RUNTIME.Downloader = CompatYTDLDownloader
YTDL_RUNTIME.Video = CompatYTDLVideo
YTDL_RUNTIME.YouTube = CompatYouTube
YTDL_RUNTIME.get_extractor = get_extractor
YTDL_RUNTIME.get_extractor_name = get_extractor_name
YTDL_RUNTIME.extractor_to_name = extractor_to_name
YTDL_RUNTIME.get_subtitles = get_subtitles
YTDL_RUNTIME.download_thumb = download_thumb


def urljoin_q(base, value):
    return urllib.parse.urljoin(clean_url(base), clean_url(value))


def kill_process(pid, delay=None):
    if delay:
        compatibility_sleep(delay)
    os.kill(int(pid), signal.SIGKILL)


def request_get(url, **kwargs):
    return Session().get(url, **kwargs)


def request_post(url, **kwargs):
    return Session().post(url, **kwargs)


class MiniNode:
    def __init__(self, name="[document]", attrs=None, parent=None, text_value=None):
        self.name = name
        self.attrs = dict(attrs or [])
        self.parent = parent
        self.children = []
        self._text_value = text_value

    def __getitem__(self, key):
        return self.attrs[key]

    def __contains__(self, key):
        return key in self.attrs

    def get(self, key, default=None):
        return self.attrs.get(key, default)

    @property
    def text(self):
        return self.get_text()

    @property
    def contents(self):
        return self.children

    @property
    def string(self):
        texts = [child for child in self.children if child.name == "#text"]
        elements = [child for child in self.children if child.name != "#text"]
        if len(texts) == 1 and not elements:
            return texts[0]._text_value
        return None

    def get_text(self, separator="", strip=False):
        if self.name == "#text":
            value = self._text_value or ""
            return value.strip() if strip else value
        parts = [child.get_text(separator=separator, strip=strip) for child in self.children]
        value = separator.join(part for part in parts if part or not strip)
        return value.strip() if strip else value

    def _matches(self, name=None, attrs=None, class_=None, **kwargs):
        if self.name == "#text":
            return False
        if name not in (None, True):
            if callable(name):
                if not name(self):
                    return False
            elif isinstance(name, (list, tuple, set)):
                if self.name not in name:
                    return False
            elif self.name != name:
                return False
        expected = dict(attrs or {})
        expected.update(kwargs)
        if class_ is not None:
            expected["class"] = class_
        for key, wanted in expected.items():
            actual = self.attrs.get(key.rstrip("_"))
            if callable(wanted):
                if not wanted(actual):
                    return False
            elif key.rstrip("_") == "class":
                classes = (actual or "").split()
                wanted_values = wanted if isinstance(wanted, (list, tuple, set)) else [wanted]
                if not all(value in classes for value in wanted_values):
                    return False
            elif hasattr(wanted, "search"):
                if actual is None or not wanted.search(actual):
                    return False
            elif actual != wanted:
                return False
        return True

    def descendants(self):
        for child in self.children:
            yield child
            yield from child.descendants()

    def find_all(self, name=None, attrs=None, recursive=True, limit=None, class_=None, **kwargs):
        source = self.descendants() if recursive else iter(self.children)
        result = []
        for node in source:
            if node._matches(name=name, attrs=attrs, class_=class_, **kwargs):
                result.append(node)
                if limit and len(result) >= limit:
                    break
        return result

    def find(self, name=None, attrs=None, recursive=True, class_=None, **kwargs):
        values = self.find_all(name, attrs, recursive, 1, class_, **kwargs)
        return values[0] if values else None

    findAll = find_all
    findChild = find

    def has_attr(self, key):
        return key in self.attrs

    def __getattr__(self, name):
        if name.startswith("_"):
            raise AttributeError(name)
        value = self.find(name)
        if value is None:
            raise AttributeError(name)
        return value

    def select(self, selector):
        current = [self]
        for token in [part for part in re.split(r"\s+", selector.strip()) if part]:
            current = [node for parent in current for node in parent.descendants()
                       if node._matches_css(token)]
        return current

    def select_one(self, selector):
        result = self.select(selector)
        return result[0] if result else None

    def _matches_css(self, token):
        attribute_name = None
        attribute_value = None
        attribute_match = re.search(r"\[([^=\]]+)(?:=([^\]]+))?\]$", token)
        if attribute_match:
            attribute_name = attribute_match.group(1)
            attribute_value = (attribute_match.group(2) or "").strip("\"'") or None
            token = token[:attribute_match.start()]
        id_match = re.search(r"#([\w-]+)", token)
        class_matches = re.findall(r"\.([\w-]+)", token)
        tag = re.split(r"[.#]", token, 1)[0] or None
        if tag and self.name != tag:
            return False
        if id_match and self.attrs.get("id") != id_match.group(1):
            return False
        classes = self.attrs.get("class", "").split()
        if any(value not in classes for value in class_matches):
            return False
        if attribute_name:
            if attribute_name not in self.attrs:
                return False
            if attribute_value is not None and self.attrs.get(attribute_name) != attribute_value:
                return False
        return self.name != "#text"


class MiniHTMLParser(HTMLParser):
    VOID_TAGS = {"area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr"}

    def __init__(self, source):
        super().__init__(convert_charrefs=True)
        self.root = MiniNode()
        self.stack = [self.root]
        self.feed(source)

    def handle_starttag(self, tag, attrs):
        node = MiniNode(tag, attrs, self.stack[-1])
        self.stack[-1].children.append(node)
        if tag not in self.VOID_TAGS:
            self.stack.append(node)

    def handle_startendtag(self, tag, attrs):
        node = MiniNode(tag, attrs, self.stack[-1])
        self.stack[-1].children.append(node)

    def handle_endtag(self, tag):
        for index in range(len(self.stack) - 1, 0, -1):
            if self.stack[index].name == tag:
                del self.stack[index:]
                break

    def handle_data(self, data):
        self.stack[-1].children.append(MiniNode("#text", parent=self.stack[-1], text_value=data))


def Soup(source, *args, **kwargs):
    del args, kwargs
    if isinstance(source, bytes):
        source = source.decode("utf-8", "replace")
    try:
        from bs4 import BeautifulSoup
        return BeautifulSoup(source, "html.parser")
    except ImportError:
        return MiniHTMLParser(source).root


def compatibility_beautiful_soup(source, *args, **kwargs):
    del args, kwargs
    if isinstance(source, bytes):
        source = source.decode("utf-8", "replace")
    return MiniHTMLParser(string_value(source) or "").root


def read_html(url, referer=None, session=None, headers=None, **kwargs):
    session = session or Session()
    request_headers = dict(headers or {})
    if referer:
        request_headers.setdefault("Referer", string_value(referer))
    response = session.get(url, headers=request_headers, **kwargs)
    response.raise_for_status()
    return response.text


def read_soup(url, referer=None, session=None, headers=None, **kwargs):
    return Soup(read_html(url, referer=referer, session=session, headers=headers, **kwargs))


def read_json(url, referer=None, session=None, headers=None, **kwargs):
    return json.loads(read_html(url, referer=referer, session=session, headers=headers, **kwargs))


def mastodon_get_info(domain, username, footer, session, cw=None, login_url=None):
    print_function = get_print(cw)
    max_files = get_max_range(cw)
    session = session or Session()
    base_url = clean_url(domain)
    if not urllib.parse.urlsplit(base_url).scheme:
        base_url = "https://" + base_url
    host = urllib.parse.urlsplit(base_url).netloc
    html_source = read_html(base_url, session=session)
    token = ree_find(r"['\"]access_token['\"] *: *['\"](.+?)['\"]", html_source)
    if token:
        print_function("token: {}".format(token))
        session.headers.update({"Authorization": "Bearer {}".format(token)})

    at_count = username.count("@")
    if at_count < 1:
        raise ValueError("@<1")
    if at_count == 1:
        query = "{}@{}".format(username, host)
    elif at_count == 2:
        query = username
    else:
        raise ValueError("@>2")
    prefix, account_name, account_host = query.split("@")
    if host.split(":", 1)[0] == "baraag.net" and account_host != "baraag.net":
        account_host = account_host.split(".")[0]
        query = "@".join([prefix, account_name, account_host])

    print_function(query)
    encoded_query = urllib.parse.quote(query)
    search_url = urljoin_q(base_url, "/api/v2/search?q={}&resolve=true&limit=5".format(encoded_query))
    search_result = read_json(search_url, session=session)
    if "accounts" not in search_result or not search_result["accounts"]:
        error_message = string_value(search_result.get("error")) or ""
        login_url = login_url or urljoin_q(base_url, "/auth/sign_in")
        raise LoginRequired(error_message, method="browser", url=login_url)

    account = search_result["accounts"][0]
    print_function(account)
    account_local_name = string_value(account.get("acct")) or ""
    if account_local_name.split("@")[0].lower() != username.split("@")[1].lower():
        raise ValueError("no account")
    title = string_value(account.get("display_name")) or account_local_name.split("@")[0]
    account_id = string_value(account.get("id"))
    if not account_id:
        raise ValueError("account id is missing")

    visited_ids = set()
    files = []
    while check_alive(cw):
        if visited_ids:
            maximum_id = min(visited_ids) - 1
            status_path = "/api/v1/accounts/{}/statuses?max_id={}&only_media=true&limit=40".format(
                account_id, maximum_id)
        else:
            status_path = "/api/v1/accounts/{}/statuses?only_media=true&limit=40".format(account_id)
        status_url = urljoin_q(base_url, status_path)
        print_function(status_url)
        statuses = try_n(3)(read_json)(status_url, session=session)
        added = 0
        for item in statuses:
            status_id = int(item["id"])
            if status_id in visited_ids:
                continue
            for position, media in enumerate(item.get("media_attachments") or []):
                media_url = clean_url(media.get("url"))
                if not media_url:
                    continue
                visited_ids.add(status_id)
                extension = get_ext(media_url)
                date = string_value(item.get("created_at")) or ""
                filename = "[{}] {}_p{}{}".format(date[2:10], status_id, position, extension)
                files.append(File({
                    "url": media_url,
                    "referer": urljoin_q(base_url, "/{}".format(username)),
                    "name": filename,
                }))
                added += 1
                if len(files) >= max_files:
                    break
            if len(files) >= max_files:
                break

        if cw is not None:
            cw.setTitle("{} {} ({}) - {}".format(tr_("읽는 중..."), title, footer, len(files)))
        if not added or len(files) >= max_files:
            break

    return {"title": title, "files": files}


def real_url(url, referer=None, session=None, headers=None, **kwargs):
    session = session or Session()
    request_headers = dict(headers or {})
    if referer:
        request_headers.setdefault("Referer", string_value(referer))
    return session.head(url, headers=request_headers, **kwargs).url


def getsize(url, referer=None, session=None, headers=None, **kwargs):
    session = session or Session()
    request_headers = dict(headers or {})
    if referer:
        request_headers.setdefault("Referer", string_value(referer))
    response = session.head(url, headers=request_headers, **kwargs)
    value = response.headers.get("Content-Length")
    return int(value) if value and value.isdigit() else None


def _session_render_headers(session):
    headers = dict(getattr(session, "headers", {}) or {})
    cookies = getattr(session, "cookies", None)
    cookie_values = cookies.get_dict() if hasattr(cookies, "get_dict") else {}
    if cookie_values and not any((string_value(key) or "").lower() == "cookie" for key in headers):
        headers["Cookie"] = "; ".join(
            "{}={}".format(key, value) for key, value in cookie_values.items()
        )
    result = {}
    for key, value in headers.items():
        name = string_value(key)
        text = string_value(value)
        if name is not None and text is not None:
            result[name] = text
    return result


def _native_browser_render(url, session, show, delay, timeout, check_body):
    endpoint = os.environ.get("HITOMI_NATIVE_RENDER_ENDPOINT", "").strip()
    token = os.environ.get("HITOMI_NATIVE_RENDER_TOKEN", "").strip()
    if not endpoint or not token:
        return None

    payload = json.dumps({
        "url": clean_url(url),
        "headers": _session_render_headers(session),
        "show": bool(show),
        "delay": float(delay or 0),
        "timeout": float(timeout or 90),
        "checkBody": bool(check_body),
    }, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    request = urllib.request.Request(
        endpoint,
        data=payload,
        headers={
            "Authorization": "Bearer " + token,
            "Content-Type": "application/json",
        },
        method="POST",
    )
    try:
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
        with opener.open(request, timeout=max(2.0, float(timeout or 90) + 2.0)) as response:
            data = response.read(20 * 1024 * 1024 + 1)
    except urllib.error.HTTPError as error:
        detail = error.read(64 * 1024).decode("utf-8", "replace")
        try:
            detail = json.loads(detail).get("error") or detail
        except (TypeError, ValueError):
            pass
        raise RuntimeError("Native browser render failed: {}".format(detail)) from error
    except OSError as error:
        raise RuntimeError("Native browser render failed: {}".format(error)) from error
    if len(data) > 20 * 1024 * 1024:
        raise RuntimeError("Native browser render response exceeded the 20 MiB limit")
    try:
        result = json.loads(data.decode("utf-8"))
    except (UnicodeDecodeError, ValueError) as error:
        raise RuntimeError("Native browser render returned invalid JSON") from error
    if not isinstance(result, dict) or not isinstance(result.get("html"), str):
        raise RuntimeError("Native browser render returned an invalid result")
    cookies = result.get("cookies")
    if isinstance(cookies, dict) and hasattr(getattr(session, "cookies", None), "update"):
        session.cookies.update(cookies)
    return {"url": clean_url(result.get("url") or url), "html": result["html"]}


def _native_browser_download(url, path, timeout):
    endpoint = os.environ.get("HITOMI_NATIVE_DOWNLOAD_ENDPOINT", "").strip()
    token = os.environ.get("HITOMI_NATIVE_RENDER_TOKEN", "").strip()
    if not endpoint or not token:
        raise RuntimeError("Native browser download is unavailable")

    payload = json.dumps({
        "url": clean_url(url),
        "path": os.path.abspath(os.fspath(path)),
        "headers": {},
        "timeout": float(timeout or 120),
    }, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    request = urllib.request.Request(
        endpoint,
        data=payload,
        headers={
            "Authorization": "Bearer " + token,
            "Content-Type": "application/json",
        },
        method="POST",
    )
    try:
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
        with opener.open(request, timeout=max(2.0, float(timeout or 120) + 2.0)) as response:
            data = response.read(256 * 1024 + 1)
    except urllib.error.HTTPError as error:
        detail = error.read(64 * 1024).decode("utf-8", "replace")
        try:
            detail = json.loads(detail).get("error") or detail
        except (TypeError, ValueError):
            pass
        raise RuntimeError("Native browser download failed: {}".format(detail)) from error
    except OSError as error:
        raise RuntimeError("Native browser download failed: {}".format(error)) from error
    if len(data) > 256 * 1024:
        raise RuntimeError("Native browser download response exceeded the 256 KiB limit")
    try:
        result = json.loads(data.decode("utf-8"))
    except (UnicodeDecodeError, ValueError) as error:
        raise RuntimeError("Native browser download returned invalid JSON") from error
    actual_path = result.get("path") if isinstance(result, dict) else None
    if not isinstance(actual_path, str) or not actual_path or not os.path.isfile(actual_path):
        raise RuntimeError("Native browser download returned an invalid result")
    return actual_path


def browser_download(url, path=None, timeout=120, cw=None):
    del cw
    if path is None:
        path = os.path.join(tempfile.gettempdir(), "{}.tmp".format(uuid_module.uuid4()))
    return _native_browser_download(url, path, timeout)


def solve(url, session=None, cw=None, show=False, delay=1.0, f=None,
          timeout=90.0, check_body=True):
    del cw
    session = session or Session()
    result = _native_browser_render(url, session, show, delay, timeout, check_body)
    if result is None:
        response = session.get(url, timeout=timeout)
        response.raise_for_status()
        result = {"url": response.url, "html": response.text}
    if callable(f):
        f(result["html"])
    return result


class LazyUrl:
    types = {}
    type = None
    CW = "#cUsToMwIdGeT#"
    DOWNLOADER = "#dOwNlOaDeR#"
    SESSION = "#sEsSiOn#"

    def __init__(self, referer, function, obj=None, url_alter=None, secret=False,
                 pp=None, detect_local=True):
        self._url = string_value(referer)
        self.referer = self._url
        self.function = function
        self.f = function
        self.obj = obj
        self.image = obj
        self._url_alter = url_alter
        self.secret = secret
        self.pp = pp
        self.detect_local = detect_local
        self._value = None

    def __call__(self):
        if self._value is None:
            if self.obj is not None:
                try:
                    self._value = self.function(self.obj)
                except TypeError:
                    self._value = self.function()
            else:
                try:
                    signature = inspect.signature(self.function)
                    required = [
                        parameter for parameter in signature.parameters.values()
                        if parameter.kind in (parameter.POSITIONAL_ONLY, parameter.POSITIONAL_OR_KEYWORD)
                        and parameter.default is parameter.empty
                    ]
                except (TypeError, ValueError):
                    required = []
                if required:
                    self._value = self.function(self._url)
                else:
                    self._value = self.function()
            if callable(self._url_alter):
                self._value = self._url_alter(self._value)
        return self._value

    @property
    def url(self):
        return string_value(self())

    def __str__(self):
        return self.url

    def __repr__(self):
        return "{}({})".format(type(self).__name__, self._url)

    def dump(self):
        return {"type": getattr(type(self), "type", None), "url": self._url}

    @classmethod
    def register(cls, lazy_class):
        type_name = string_value(getattr(lazy_class, "type", None))
        if not type_name:
            raise ValueError("No type")
        cls.types[type_name] = lazy_class
        return lazy_class

    @classmethod
    def get(cls, type_name, default=None):
        return cls.types.get(type_name, default)


class Counter:
    def __init__(self, n=0, max=0):
        self.n = n
        self.max = max

    def next(self):
        self.n += 1
        return self.n

    def dump(self):
        return {"n": self.n, "max": self.max}

    @classmethod
    def load(cls, data):
        return cls(data["n"], data["max"])


class Progress:
    def __init__(self, value=0, maximum=0):
        self.value = value
        self.maximum = maximum

    def dump(self):
        return {"value": self.value, "maximum": self.maximum}

    @classmethod
    def load(cls, data):
        return cls(data["value"], data["maximum"])


class Size:
    def __init__(self, cw=None, progress=None, maxSpeed=None):
        self.cw = cw
        self.progress = progress
        self.maxSpeed = maxSpeed
        self.size = int(getattr(cw, "filesize", 0) or 0) if cw is not None else 0

    def __add__(self, value):
        self.size += int(value or 0)
        return self

    def __iadd__(self, value):
        return self.__add__(value)

    def __int__(self):
        return self.size

    def reset(self):
        self.size = 0
        return self


class FileNotImplementedError(Exception):
    pass


class File:
    types = {}
    type = None
    format = None
    secret = False
    detect_local = True
    utime = None
    segment = None
    cw = None
    downloader = None
    session = None
    max_try = None

    def __init_subclass__(cls, **kwargs):
        super().__init_subclass__(**kwargs)
        if getattr(cls, "type", None) is not None:
            File.register(cls)

    @classmethod
    def register(cls, file_class):
        type_name = getattr(file_class, "type", None)
        if not isinstance(type_name, str):
            raise TypeError("type is not str")
        if re.fullmatch(r"[\w.]+", type_name, re.UNICODE) is None:
            raise ValueError("Invalid type")
        if cls.types.get(type_name) is file_class:
            return None
        cls.types[type_name] = file_class
        if getattr(file_class, "format", None):
            ORIGINAL_SITE_DEFAULTS.setdefault(type_name, {})["format"] = file_class.format
        return file_class

    def __init__(self, info, name=None, referer=None, headers=None):
        if isinstance(info, dict) and name is None and referer is None and headers is None:
            self._check_serializable(info)
            self._info = dict(info)
        else:
            self._info = {
                "url": info,
                "name": name,
                "referer": referer,
                "headers": dict(headers or {}),
            }
        self._cache_info_lazy = None
        self._hitomi_native_ready = False
        self._try = 0
        self.cw = None
        self.downloader = None
        self.session = None

    @classmethod
    def _check_serializable(cls, info, *, lazy=False):
        if lazy:
            if not isinstance(info, (dict, list)):
                raise TypeError("must be dict or list")
            if isinstance(info, list) and not all(isinstance(value, dict) for value in info):
                raise TypeError("must be list of dict")
        elif not isinstance(info, dict):
            raise TypeError("must be dict")
        json.dumps(info)

    @property
    def url(self):
        return self._info.get("url") or self._info.get("src")

    @url.setter
    def url(self, value):
        self._info["url"] = value

    @property
    def name(self):
        return (self._info.get("name") or self._info.get("filename") or
                self._info.get("referer") or self._info.get("url"))

    @name.setter
    def name(self, value):
        self._info["name"] = value

    @property
    def filename(self):
        return self._info.get("filename") or self._info.get("name")

    @filename.setter
    def filename(self, value):
        self._info["filename"] = value

    @property
    def referer(self):
        return self._info.get("referer")

    @referer.setter
    def referer(self, value):
        self._info["referer"] = value

    @property
    def headers(self):
        return dict(self._info.get("headers") or {})

    @headers.setter
    def headers(self, value):
        self._info["headers"] = dict(value or {})

    def __repr__(self):
        return "{}({})".format(self.__class__.__name__, display_url(self.name))

    def __str__(self):
        return string_value(self.url) or ""

    def dump(self):
        return self._info.copy()

    @classmethod
    def load(cls, info):
        return cls(info)

    def __getitem__(self, key):
        return self._info[key]

    def __setitem__(self, key, value):
        self._info[key] = value

    def get_(self, value, default=None):
        return self._info.get(value, default)

    def get(self):
        raise FileNotImplementedError()

    def alter(self):
        raise FileNotImplementedError()

    def ready(self, cw, i=None):
        self.cw = cw
        try:
            self.downloader = cw.downloader
            self.session = cw.downloader.session
        except Exception:
            self.downloader = None
            self.session = None
        info_lazy = self._cache_info_lazy
        if info_lazy is None:
            try:
                info_lazy = self.get()
                self._check_serializable(info_lazy, lazy=True)
                self._cache_info_lazy = info_lazy
            except FileNotImplementedError:
                info_lazy = {}
            finally:
                self.cw = None
                self.downloader = None
                self.session = None
        files = []
        if isinstance(info_lazy, list):
            if info_lazy:
                self._info.update(info_lazy[0])
            if i is not None:
                for offset, extra in enumerate(info_lazy[1:], 1):
                    info = self.dump()
                    info.update(extra)
                    files.append((i, offset, File.load(info)))
        else:
            self._info.update(info_lazy)
        self._hitomi_native_ready = True
        return files


class DummyProgressBar:
    def __init__(self):
        self._maximum = 0
        self.value = 0

    def setMaximum(self, value):
        self._maximum = value

    def setValue(self, value):
        self.value = value

    def setFormat(self, _value):
        return None


class DummyCW:
    def __init__(self, url=""):
        self.url = url
        self.title = ""
        self.dir = ""
        self.outputPath = ""
        self.metadata = {}
        self.status = "ready"
        self.valid = True
        self.total = 0
        self.completed = 0
        self.error = None
        self.paused = False
        self.pause_lock = False
        self.alive = True
        self.type = None
        self.range = None
        self.range_p = None
        self.pc = None
        self.tags = []
        self._comment = ""
        self.imgs = []
        self.names = []
        self.names_old = []
        self.dones = set()
        self.dirs_fail = []
        self.urls = []
        self.downloader = None
        self.detect_removed = True
        self.detect_local_lazy = True
        self.lock = False
        self.release_timestamp = None
        self.dir_retry = None
        self.artist = None
        self.live = False
        self.single = False
        self.p2f = False
        self.allow_retry = False
        self.filesize = 0
        self.trash_can = []
        self.pids = []
        self.stop_live = False
        self.subtitle = False
        self.pbar = DummyProgressBar()
        self._extra = {}

    def print_(self, *args, **kwargs):
        print(*args, **kwargs)

    def setTitle(self, value):
        self.title = string_value(value) or ""

    def comment(self):
        return self._comment

    def enableSegment(self, *_args, **_kwargs):
        return None

    def disableSegment(self, *_args, **_kwargs):
        return None

    def get_extra(self, key, default=None):
        return self._extra.get(key, default)

    def set_extra(self, key, value):
        self._extra[key] = value

    def remove_extra(self, key):
        self._extra.pop(key, None)

    def setSubtitle(self, value):
        self.subtitle = bool(value)

    def __getattr__(self, _name):
        return lambda *_args, **_kwargs: None


class Downloader:
    types = {}
    instances = []
    waiting_init = False
    mainWindow = None
    fix_urls = {}
    key_ids = {}
    MAX_CORE = 16
    MAX_PARALLEL = 4
    MAX_SPEED = None
    URLS = None
    type = None
    fix_url = None
    key_id = None
    icon = None
    single = False
    session = None
    lock = False
    detect_removed = True
    detect_local_lazy = True
    _title = None
    _icon = None
    user_agent = None
    referer = None
    header = None
    status = "ready"
    update_filesize = True
    size = None
    _artist = None
    display_name = None
    keep_date = False
    strip_header = True
    atts = []
    _enabled = True
    ACC_MTIME = False
    skip_convert_imgs = False
    ACCEPT_COOKIES = None
    STOP_READING = True
    PRIORITY = 0
    NO_LIMIT = False

    def __init_subclass__(cls, **kwargs):
        super().__init_subclass__(**kwargs)
        if getattr(cls, "type", None) is not None:
            Downloader.register(cls)

    @classmethod
    def register(cls, downloader_class):
        type_name = string_value(getattr(downloader_class, "type", None))
        if not type_name or not re.fullmatch(r"[\w.]+", type_name, re.UNICODE):
            raise ValueError("Invalid Downloader.type: {!r}".format(type_name))
        cls.types[type_name] = downloader_class
        if downloader_class not in REGISTERED_DOWNLOADERS:
            REGISTERED_DOWNLOADERS.append(downloader_class)
        return downloader_class

    @classmethod
    def get(cls, type_name, default=None):
        return cls.types.get(type_name, default)

    @classmethod
    def count(cls):
        counts = {}
        for instance in cls.instances:
            if getattr(getattr(instance, "cw", None), "live", False):
                continue
            type_name = string_value(getattr(instance, "type", None)) or "unknown"
            counts[type_name] = counts.get(type_name, 0) + 1
        return counts

    def __init__(self, url="", cw=None, thread=None, n_core=None, server=None,
                 dirFormat=None, event=None):
        del thread, n_core, server, dirFormat
        self._urls = []
        self._filenames = {}
        self._cw = cw or DummyCW(url)
        self._cw.downloader = self
        self._url = clean_url(getattr(self._cw, "url", None) or url)
        self._title = getattr(type(self), "_title", None)
        self._artist = getattr(type(self), "_artist", None)
        self.session = getattr(type(self), "session", None) or Session()
        self.size = Size(self._cw)
        self.header = getattr(type(self), "header", None)
        self.referer = getattr(type(self), "referer", None)
        self.user_agent = getattr(type(self), "user_agent", None)
        Downloader.instances.append(self)
        if event is not None and hasattr(event, "set"):
            event.set()

    @property
    def url(self):
        return self._url

    @url.setter
    def url(self, value):
        self._url = clean_url(value)
        if self._cw is not None:
            self._cw.url = self._url

    @property
    def title(self):
        return self._title or "download"

    @title.setter
    def title(self, value):
        self._title = clean_title(value)
        if self._cw is not None:
            self._cw.setTitle(self._title)

    @property
    def artist(self):
        return self._artist

    @artist.setter
    def artist(self, value):
        if value in ("", "N/A", "N／A"):
            value = None
        self._artist = string_value(value)
        if self._cw is not None:
            self._cw.artist = self._artist

    @property
    def urls(self):
        return self._urls

    @urls.setter
    def urls(self, value):
        self._urls = list(value or [])

    @property
    def filenames(self):
        return self._filenames

    @filenames.setter
    def filenames(self, value):
        self._filenames = dict(value or {})

    @property
    def cw(self):
        return self._cw

    @property
    def customWidget(self):
        return self._cw

    @property
    def enableSegment(self):
        return self._cw.enableSegment

    @property
    def disableSegment(self):
        return self._cw.disableSegment

    @property
    def dir(self):
        retry = getattr(self._cw, "dir_retry", None)
        if isinstance(retry, (str, bytes)) and string_value(retry):
            return string_value(retry)
        return string_value(getattr(self._cw, "dir", None) or getattr(self._cw, "outputPath", None)) or ""

    def init(self):
        return None

    def read(self):
        raise NotImplementedError

    def print_(self, *args, **kwargs):
        get_print(self._cw)(*args, **kwargs)

    def Invalid(self, s="", e=None, fail=False):
        return raise_invalid(self.type, self._cw, s, e, fail)

    def on_error(self, error):
        raise error

    def fix_dirname(self, title=None):
        if title is not None:
            self.title = title
        return self.dir

    def stop(self):
        if self._cw is not None:
            self._cw.alive = False
        return None


class _Hook:
    def __init__(self, hook, event, name):
        self.hook = hook
        self.event = event
        self.name = string_value(name) or "default"

    def __call__(self, function):
        self.hook._hooks[self.event][self.name] = function
        return function

    def unhook(self):
        try:
            del self.hook._hooks[self.event][self.name]
            return True
        except KeyError:
            return False


class Hook:
    _hooks = REGISTERED_HOOKS

    @classmethod
    def task_about_to_start(cls, name):
        return _Hook(cls, "task_about_to_start", name)

    @classmethod
    def task_about_to_download(cls, name):
        return _Hook(cls, "task_about_to_download", name)

    @classmethod
    def task_finished(cls, name):
        return _Hook(cls, "task_finished", name)

    @classmethod
    def format(cls, type_name):
        return _Hook(cls, "format", type_name)


class QColor:
    _names = {
        "black": (0, 0, 0, 255),
        "white": (255, 255, 255, 255),
        "red": (255, 0, 0, 255),
        "green": (0, 128, 0, 255),
        "blue": (0, 0, 255, 255),
        "gray": (128, 128, 128, 255),
        "grey": (128, 128, 128, 255),
        "transparent": (0, 0, 0, 0),
    }

    def __init__(self, *values):
        self._rgba = self._parse(values)

    @classmethod
    def _parse(cls, values):
        if len(values) == 1:
            value = values[0]
            if isinstance(value, QColor):
                return value.getRgb()
            if isinstance(value, QBrush):
                return value.color().getRgb()
            if isinstance(value, (list, tuple)):
                return cls._parse(tuple(value))
            text = string_value(value)
            if text is None:
                return (0, 0, 0, 255)
            text = text.strip().lower()
            if text in cls._names:
                return cls._names[text]
            if re.fullmatch(r"#[0-9a-f]{3,8}", text):
                raw = text[1:]
                if len(raw) in (3, 4):
                    raw = "".join(character * 2 for character in raw)
                if len(raw) == 6:
                    raw += "ff"
                if len(raw) == 8:
                    return tuple(int(raw[index:index + 2], 16) for index in range(0, 8, 2))
            match = re.fullmatch(r"rgba?\(([^)]+)\)", text)
            if match:
                parts = [part.strip() for part in match.group(1).split(",")]
                try:
                    rgb = [cls._component(part) for part in parts[:3]]
                    alpha = cls._alpha(parts[3]) if len(parts) > 3 else 255
                    return tuple(rgb + [alpha])
                except (TypeError, ValueError):
                    pass
            return (0, 0, 0, 255)
        if len(values) >= 3:
            rgba = [cls._component(value) for value in values[:3]]
            rgba.append(cls._alpha(values[3]) if len(values) > 3 else 255)
            return tuple(rgba)
        return (0, 0, 0, 255)

    @staticmethod
    def _component(value):
        return max(0, min(255, int(round(float(value)))))

    @staticmethod
    def _alpha(value):
        number = float(value)
        if 0 <= number <= 1:
            number *= 255
        return max(0, min(255, int(round(number))))

    def isValid(self):
        return True

    def name(self, *_args):
        return "#{:02X}{:02X}{:02X}".format(*self._rgba[:3])

    def getRgb(self):
        return self._rgba

    def red(self):
        return self._rgba[0]

    def green(self):
        return self._rgba[1]

    def blue(self):
        return self._rgba[2]

    def alpha(self):
        return self._rgba[3]

    def lighter(self, factor=150):
        scale = max(0, float(factor)) / 100.0
        return QColor(*(min(255, round(value * scale)) for value in self._rgba[:3]), self._rgba[3])

    def darker(self, factor=200):
        scale = 100.0 / max(1, float(factor))
        return QColor(*(round(value * scale) for value in self._rgba[:3]), self._rgba[3])

    def __str__(self):
        return self.name()


class QBrush:
    def __init__(self, color=None, *_args):
        self._color = color if isinstance(color, QColor) else QColor(color or "#000000")

    def color(self):
        return self._color


class QPalette:
    Active = 0
    Disabled = 1
    Inactive = 2
    WindowText = 0
    Button = 1
    Light = 2
    Midlight = 3
    Dark = 4
    Mid = 5
    Text = 6
    BrightText = 7
    ButtonText = 8
    Base = 9
    Window = 10
    Shadow = 11
    Highlight = 12
    HighlightedText = 13
    Link = 14
    LinkVisited = 15
    AlternateBase = 16
    NoRole = 17
    ToolTipBase = 18
    ToolTipText = 19
    PlaceholderText = 20
    Accent = 21

    def __init__(self, other=None):
        self._colors = dict(getattr(other, "_colors", {}))

    def setColor(self, *values):
        if len(values) == 2:
            group = None
            role, color = values
        elif len(values) == 3:
            group, role, color = values
        else:
            raise TypeError("setColor expects role/color or group/role/color")
        self._colors[(group, int(role))] = color if isinstance(color, QColor) else QColor(color)

    def setBrush(self, *values):
        values = list(values)
        values[-1] = values[-1].color() if isinstance(values[-1], QBrush) else values[-1]
        self.setColor(*values)

    def color(self, *values):
        if len(values) == 1:
            group = None
            role = int(values[0])
        elif len(values) == 2:
            group, role = values
            role = int(role)
        else:
            raise TypeError("color expects role or group/role")
        return self._colors.get((group, role)) or self._colors.get((None, role)) or QColor("#000000")

    def brush(self, *values):
        return QBrush(self.color(*values))


class _PaletteColorRole:
    pass


class _PaletteColorGroup:
    pass


for _name in (
    "WindowText", "Button", "Light", "Midlight", "Dark", "Mid", "Text", "BrightText",
    "ButtonText", "Base", "Window", "Shadow", "Highlight", "HighlightedText", "Link",
    "LinkVisited", "AlternateBase", "NoRole", "ToolTipBase", "ToolTipText", "PlaceholderText", "Accent",
):
    setattr(_PaletteColorRole, _name, getattr(QPalette, _name))
for _name in ("Active", "Disabled", "Inactive"):
    setattr(_PaletteColorGroup, _name, getattr(QPalette, _name))
QPalette.ColorRole = _PaletteColorRole
QPalette.ColorGroup = _PaletteColorGroup


class _QtGlobalColor:
    black = QColor("black")
    white = QColor("white")
    red = QColor("red")
    green = QColor("green")
    blue = QColor("blue")
    gray = QColor("gray")
    transparent = QColor("transparent")


class Qt:
    GlobalColor = _QtGlobalColor
    black = _QtGlobalColor.black
    white = _QtGlobalColor.white
    red = _QtGlobalColor.red
    green = _QtGlobalColor.green
    blue = _QtGlobalColor.blue
    gray = _QtGlobalColor.gray
    transparent = _QtGlobalColor.transparent
    NoBrush = 0
    Horizontal = 1
    Vertical = 2


class HeadlessControl:
    def __init__(self, checked=False, value=0, items=None, index=0, text=""):
        self._checked = bool(checked)
        self._value = value
        self._items = list(items or [])
        self._index = int(index or 0)
        self._text = compatstr(text)

    def isChecked(self):
        return self._checked

    def setChecked(self, value):
        self._checked = bool(value)

    def value(self):
        return self._value

    def setValue(self, value):
        self._value = value

    def currentIndex(self):
        return self._index

    def setCurrentIndex(self, value):
        self._index = max(0, int(value or 0))

    def currentText(self):
        if self._items and self._index < len(self._items):
            return compatstr(self._items[self._index])
        return self._text

    def text(self):
        return self._text or self.currentText()

    def setText(self, value):
        self._text = compatstr(value)

    def count(self):
        return len(self._items)

    def item(self, index):
        return HeadlessControl(text=self.itemText(index))

    def itemText(self, index):
        return compatstr(self._items[index]) if 0 <= index < len(self._items) else ""

    def itemIcon(self, _index):
        return QIcon()

    def addItem(self, *values):
        if values:
            self._items.append(values[-1])

    def setItemIcon(self, *_args):
        return None

    def viewport(self):
        return self

    def update(self):
        return None


class HeadlessSignal:
    def __init__(self):
        self.callbacks = []

    def connect(self, callback):
        if callable(callback):
            self.callbacks.append(callback)

    def emit(self, *args, **kwargs):
        for callback in list(self.callbacks):
            callback(*args, **kwargs)


class HeadlessWidget(HeadlessControl):
    def __init__(self, *args, **kwargs):
        text = args[0] if args and isinstance(args[0], str) else kwargs.pop("text", "")
        super().__init__(text=text)
        self.layout = None
        self.parent = args[-1] if args and not isinstance(args[-1], str) else None

    def setLayout(self, layout):
        self.layout = layout

    def setWindowTitle(self, value):
        self.window_title = string_value(value) or ""

    def show(self):
        return None

    def close(self):
        return None

    def __getattr__(self, _name):
        return lambda *_args, **_kwargs: None


class HeadlessDialog(HeadlessWidget):
    Rejected = 0
    Accepted = 1

    def exec(self):
        return self.Accepted

    exec_ = exec

    def accept(self):
        return self.Accepted

    def reject(self):
        return self.Rejected


class HeadlessLayout:
    def __init__(self, *_args, **_kwargs):
        self.items = []

    def addWidget(self, widget, *_args):
        self.items.append(widget)

    def addLayout(self, layout, *_args):
        self.items.append(layout)

    def addRow(self, *items):
        self.items.append(items)


class HeadlessComboBox(HeadlessWidget):
    def addItems(self, values):
        self._items.extend(list(values or []))


class HeadlessDialogButtonBox(HeadlessWidget):
    Ok = 1
    Cancel = 2

    def __init__(self, *_args, **_kwargs):
        super().__init__()
        self.accepted = HeadlessSignal()
        self.rejected = HeadlessSignal()


class HeadlessUISetting:
    def __init__(self):
        self._controls = {
            "albumArt": HeadlessControl(False),
            "askYoutube": HeadlessControl(False),
            "chapterMarkerCheck": HeadlessControl(True),
            "checkDither": HeadlessControl(True),
            "groupBox_tag": HeadlessControl(False),
            "playlist_numerate": HeadlessControl(False),
            "subtitle": HeadlessControl(False),
            "subtitleCombo": HeadlessControl(items=["en"], index=0),
            "tagList": HeadlessControl(items=[]),
            "thumbCheck": HeadlessControl(False),
            "torrentSelectFiles": HeadlessControl(False),
            "ugoira_convert": HeadlessControl(items=["none", "gif", "webp", "ugoira"], index=0),
            "ugoira_quality": HeadlessControl(value=90),
            "youtubeCombo_abr": HeadlessControl(items=["192k"], index=0),
            "youtubeCombo_res": HeadlessControl(items=["720p"], index=0),
            "youtubeCombo_type": HeadlessControl(items=["video"], index=0),
            "youtubeMtimeCheck": HeadlessControl(False),
        }
        for name, control in self._controls.items():
            setattr(self, name, control)

    def __getattr__(self, name):
        control = HeadlessControl(False)
        self._controls[name] = control
        setattr(self, name, control)
        return control


class HeadlessUI:
    @staticmethod
    def listWidget(items, *_args, **_kwargs):
        return list(items or [])


class HeadlessExecQueue:
    @staticmethod
    def run(function, *args, **kwargs):
        return function(*args, **kwargs)


class HeadlessPixmap:
    def isNull(self):
        return False

    def size(self):
        return (0, 0)


class HeadlessImageReader:
    QPixmap = HeadlessPixmap

    @staticmethod
    def getFilePixmap(*_args, **_kwargs):
        return HeadlessPixmap()


class QIcon:
    def __init__(self, value=None):
        self.value = value
        self.pixmaps = []

    def addPixmap(self, pixmap):
        self.pixmaps.append(pixmap)

    def isNull(self):
        return self.value is None and not self.pixmaps


class QStyle:
    PM_ListViewIconSize = 0
    SP_FileIcon = 1

    class PixelMetric:
        PM_ListViewIconSize = 0

    class StandardPixmap:
        SP_FileIcon = 1

    def pixelMetric(self, _metric):
        return 32

    def standardIcon(self, value):
        return QIcon(value)


class QApplication:
    _instance = None
    _palette = QPalette()
    _style = QStyle()
    _style_sheet = ""

    @classmethod
    def instance(cls):
        if cls._instance is None:
            cls._instance = cls()
        return cls._instance

    @classmethod
    def palette(cls):
        return QPalette(cls._palette)

    @classmethod
    def setPalette(cls, palette):
        cls._palette = QPalette(palette) if isinstance(palette, QPalette) else QPalette()

    @classmethod
    def style(cls):
        return cls._style

    @classmethod
    def setStyle(cls, style):
        cls._style = style if style is not None else QStyle()

    @classmethod
    def styleSheet(cls):
        return cls._style_sheet

    @classmethod
    def setStyleSheet(cls, value):
        cls._style_sheet = string_value(value) or ""

    @classmethod
    def themeState(cls):
        return QPalette(cls._palette), cls._style, cls._style_sheet

    @classmethod
    def restoreThemeState(cls, state):
        palette, style, style_sheet = state
        cls._palette = QPalette(palette)
        cls._style = style
        cls._style_sheet = string_value(style_sheet) or ""

    @classmethod
    def resetThemeState(cls):
        cls._palette = QPalette()
        cls._style = QStyle()
        cls._style_sheet = ""


class QInputDialog:
    @staticmethod
    def getInt(_parent, _title, _label, value=0, *_args, **_kwargs):
        return int(value or 0), False

    @staticmethod
    def getText(_parent, _title, _label, *_args, **_kwargs):
        return "", False


class QMessageBox:
    NoIcon = 0
    Information = 1
    Warning = 2
    Critical = 3
    Question = 4
    Ok = 1024
    Cancel = 4194304


def headless_message_box(message, title="", icon=None, parent=None, **_kwargs):
    del icon, parent
    prefix = "{}: ".format(compatstr(title)) if title else ""
    original_log(prefix + compatstr(message))
    return QMessageBox.Ok


class WindowSet(set):
    def append(self, item):
        self.add(item)


def original_actions(type_name):
    def wrapper(function):
        REGISTERED_ACTIONS[type_name] = function
        return function
    return wrapper


HEADLESS_UI_SETTING = HeadlessUISetting()
HEADLESS_UI = HeadlessUI()
HEADLESS_EXEC_QUEUE = HeadlessExecQueue()
HEADLESS_IMAGE_READER = HeadlessImageReader()
HEADLESS_WINDOWS = WindowSet()


class QProxyStyle:
    def __init__(self, base=None):
        self.base = base


class QStyleFactory:
    @staticmethod
    def create(name):
        return string_value(name)

    @staticmethod
    def keys():
        return ["Fusion", "Windows"]


def addTheme(theme_key, descriptor):
    key = (string_value(theme_key) or "").strip().lower()
    if not key:
        raise ValueError("Theme key is empty")
    if not isinstance(descriptor, dict):
        raise TypeError("Theme descriptor must be a dictionary")
    display_name = descriptor.get("display_name")
    if not string_value(display_name):
        raise ValueError('No key: "display_name"')
    REGISTERED_THEMES[key] = dict(descriptor)


def setTheme(theme_key):
    global CURRENT_THEME
    key = (string_value(theme_key) or "").strip().lower()
    if key not in REGISTERED_THEMES:
        return False
    CURRENT_THEME = key
    return True


def updateTheme():
    return None


def pal_default():
    return QPalette()


class CompatibilityCache:
    def __init__(self, limit=4):
        self.limit = max(0, int(limit or 0))
        self._values = {}
        self._order = []
        self._lock = threading.RLock()

    def setCacheLimit(self, limit):
        with self._lock:
            self.limit = max(0, int(limit or 0))
            self.clean()

    def clean(self):
        with self._lock:
            while self.limit and len(self._order) > self.limit:
                key = self._order.pop(0)
                self._values.pop(key, None)
            if self.limit == 0:
                self._values.clear()
                self._order[:] = []

    def get(self, key, default=None):
        with self._lock:
            if key not in self._values:
                return default
            self._order.remove(key)
            self._order.append(key)
            return self._values[key]

    def set(self, key, value):
        with self._lock:
            if key in self._values:
                self._order.remove(key)
            self._values[key] = value
            self._order.append(key)
            self.clean()
        return value

    def remove(self, key):
        with self._lock:
            self._values.pop(key, None)
            if key in self._order:
                self._order.remove(key)

    def pop(self, key, default=None):
        with self._lock:
            if key not in self._values:
                return default
            value = self._values.pop(key)
            self._order.remove(key)
            return value

    def clear(self):
        with self._lock:
            self._values.clear()
            self._order[:] = []

    def __contains__(self, key):
        return key in self._values

    def __len__(self):
        return len(self._values)

    def __getitem__(self, key):
        value = self.get(key, self)
        if value is self:
            raise KeyError(key)
        return value

    def __setitem__(self, key, value):
        self.set(key, value)


class CompatibilityCacheDecorator:
    def __init__(self, maxage=None):
        self.maxage = None if maxage is None else max(0.0, float(maxage))

    def __call__(self, function):
        lock_ = threading.RLock()
        state = {"ready": False, "time": 0.0, "value": None}

        @functools.wraps(function)
        def wrapped(*args, **kwargs):
            with lock_:
                now = time.monotonic()
                fresh = state["ready"] and (
                    self.maxage is None or now - state["time"] <= self.maxage
                )
                if fresh:
                    return state["value"]
                state["value"] = function(*args, **kwargs)
                state["time"] = now
                state["ready"] = True
                return state["value"]
        return wrapped


class CompatibilityClock:
    TIMES = {}
    COUNTS = {}
    _lock = threading.RLock()

    def __init__(self, name, verbose=False):
        self.name = string_value(name) or "clock"
        self.verbose = bool(verbose)
        self.started = None

    def __enter__(self):
        self.started = time.perf_counter()
        return self

    def __exit__(self, _type, _value, _traceback):
        elapsed = time.perf_counter() - (self.started or time.perf_counter())
        with self._lock:
            self.TIMES[self.name] = self.TIMES.get(self.name, 0.0) + elapsed
            self.COUNTS[self.name] = self.COUNTS.get(self.name, 0) + 1
        if self.verbose:
            print("{}: {:.6f}s".format(self.name, elapsed))

    @classmethod
    def times(cls):
        with cls._lock:
            return dict(cls.TIMES)

    @classmethod
    def counters(cls):
        with cls._lock:
            return dict(cls.COUNTS)


def compatibility_lock_n(count=1):
    semaphore = threading.Semaphore(max(1, int(count or 1)))

    def decorator(function):
        @functools.wraps(function)
        def wrapped(*args, **kwargs):
            with semaphore:
                return function(*args, **kwargs)
        return wrapped
    return decorator


def compatibility_filesize(value, system=None):
    del system
    amount = float(value or 0)
    units = ("byte", "KB", "MB", "GB", "TB", "PB", "EB")
    index = 0
    while abs(amount) >= 1024.0 and index + 1 < len(units):
        amount /= 1024.0
        index += 1
    if index == 0:
        return "{} {}".format(int(amount), "byte" if abs(amount) == 1 else "bytes")
    return "{:.1f} {}".format(amount, units[index])


def compatibility_datetime_parse(value, default=None, dayfirst=False, yearfirst=False,
                                 fuzzy=False, ignoretz=False, tzinfos=None, **kwargs):
    del tzinfos, kwargs
    if isinstance(value, datetime_module.datetime):
        result = value
    elif isinstance(value, datetime_module.date):
        result = datetime_module.datetime.combine(value, datetime_module.time())
    else:
        text = (string_value(value) or "").strip()
        if not text:
            raise ValueError("Unknown string format")
        normalized = text.replace("Z", "+00:00") if text.endswith("Z") else text
        normalized = re.sub(r"([+-][0-9]{2})([0-9]{2})$", r"\1:\2", normalized)
        result = None
        try:
            result = datetime_module.datetime.fromisoformat(normalized)
        except ValueError:
            pass
        if result is None:
            try:
                result = email.utils.parsedate_to_datetime(text)
            except (TypeError, ValueError, OverflowError):
                pass
        formats = [
            "%Y-%m-%d %H:%M:%S.%f", "%Y-%m-%d %H:%M:%S", "%Y-%m-%d",
            "%Y/%m/%d %H:%M:%S", "%Y/%m/%d", "%Y.%m.%d %H:%M:%S", "%Y.%m.%d",
            "%a %b %d %H:%M:%S %z %Y", "%a, %d %b %Y %H:%M:%S %z",
        ]
        if dayfirst:
            formats.extend(("%d/%m/%Y %H:%M:%S", "%d/%m/%Y"))
        elif yearfirst:
            formats.extend(("%Y/%m/%d %H:%M:%S", "%Y/%m/%d"))
        else:
            formats.extend(("%m/%d/%Y %H:%M:%S", "%m/%d/%Y"))
        if result is None:
            for format_ in formats:
                try:
                    result = datetime_module.datetime.strptime(text, format_)
                    break
                except ValueError:
                    continue
        if result is None and fuzzy:
            match = re.search(
                r"[0-9]{4}[-/.][0-9]{1,2}[-/.][0-9]{1,2}"
                r"(?:[ T][0-9]{1,2}:[0-9]{2}(?::[0-9]{2}(?:\.[0-9]+)?)?)?",
                text,
            )
            if match:
                return compatibility_datetime_parse(match.group(0), default=default)
        if result is None:
            raise ValueError("Unknown string format: {}".format(text))
    if ignoretz and result.tzinfo is not None:
        result = result.replace(tzinfo=None)
    if default is not None and isinstance(default, datetime_module.datetime):
        fields = (result.year, result.month, result.day, result.hour, result.minute, result.second)
        if fields[:3] == (1900, 1, 1):
            result = result.replace(year=default.year, month=default.month, day=default.day)
    return result


class CompatibilityFileType:
    def __init__(self, extension, mime):
        self.extension = extension
        self.mime = mime

    def __repr__(self):
        return "<filetype.types.{}>".format(self.extension.upper())


def compatibility_file_header(value, limit=4096):
    if isinstance(value, (bytes, bytearray, memoryview)):
        return bytes(value[:limit])
    if isinstance(value, (str, os.PathLike)):
        with open(value, "rb") as handle:
            return handle.read(limit)
    if hasattr(value, "read"):
        position = value.tell() if hasattr(value, "tell") else None
        data = value.read(limit)
        if position is not None and hasattr(value, "seek"):
            value.seek(position)
        return bytes(data)
    return b""


def compatibility_filetype_guess(value):
    data = compatibility_file_header(value)
    signatures = (
        (b"\xff\xd8\xff", "jpg", "image/jpeg"),
        (b"\x89PNG\r\n\x1a\n", "png", "image/png"),
        (b"GIF87a", "gif", "image/gif"),
        (b"GIF89a", "gif", "image/gif"),
        (b"BM", "bmp", "image/bmp"),
        (b"II*\x00", "tif", "image/tiff"),
        (b"MM\x00*", "tif", "image/tiff"),
        (b"PK\x03\x04", "zip", "application/zip"),
        (b"\x1aE\xdf\xa3", "webm", "video/webm"),
    )
    for signature, extension, mime in signatures:
        if data.startswith(signature):
            return CompatibilityFileType(extension, mime)
    if len(data) >= 12 and data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        return CompatibilityFileType("webp", "image/webp")
    if len(data) >= 12 and data[4:8] == b"ftyp":
        brand = data[8:12]
        if brand in (b"avif", b"avis"):
            return CompatibilityFileType("avif", "image/avif")
        return CompatibilityFileType("mp4", "video/mp4")
    return None


class NativeOwnedFeature(RuntimeError):
    def __init__(self, feature):
        self.feature = string_value(feature) or "native resolver feature"
        super().__init__("{} is handled by the native resolver".format(self.feature))


def native_owned(name):
    def unavailable(*_args, **_kwargs):
        raise NativeOwnedFeature(name)
    return unavailable


def refine_gallery_number(value):
    text = clean_url(value)
    matches = re.findall(r"(?:galleries|galleryblock|reader|mpv|g)/[^/?#]*?([0-9]{3,})", text, re.I)
    if not matches:
        matches = re.findall(r"(?:^|[^0-9])([0-9]{3,})(?:[^0-9]|$)", text)
    if not matches:
        raise ValueError("Gallery number was not found: {}".format(text))
    return int(matches[-1])


class CompatibilityImage:
    def __init__(self, data=b"", size=(0, 0), mode="RGBA"):
        self.data = bytes(data)
        self.size = tuple(size)
        self.width, self.height = self.size
        self.mode = mode
        self.format = None

    def copy(self):
        return CompatibilityImage(self.data, self.size, self.mode)

    def convert(self, mode):
        result = self.copy()
        result.mode = mode
        return result

    def save(self, target, format=None, **_kwargs):
        del format
        if hasattr(target, "write"):
            target.write(self.data)
        else:
            with open(target, "wb") as handle:
                handle.write(self.data)

    def close(self):
        return None

    def __enter__(self):
        return self

    def __exit__(self, *_args):
        self.close()


def compatibility_image_size(data):
    if data.startswith(b"\x89PNG\r\n\x1a\n") and len(data) >= 24:
        return int.from_bytes(data[16:20], "big"), int.from_bytes(data[20:24], "big")
    if data[:6] in (b"GIF87a", b"GIF89a") and len(data) >= 10:
        return int.from_bytes(data[6:8], "little"), int.from_bytes(data[8:10], "little")
    if data.startswith(b"\xff\xd8"):
        offset = 2
        while offset + 9 < len(data):
            if data[offset] != 0xFF:
                offset += 1
                continue
            marker = data[offset + 1]
            if marker in range(0xC0, 0xC4):
                return int.from_bytes(data[offset + 7:offset + 9], "big"), int.from_bytes(data[offset + 5:offset + 7], "big")
            if offset + 4 > len(data):
                break
            length = int.from_bytes(data[offset + 2:offset + 4], "big")
            offset += max(2, length + 2)
    return (0, 0)


def compatibility_image_open(value, *args, **kwargs):
    del args, kwargs
    if isinstance(value, (str, os.PathLike)):
        with open(value, "rb") as handle:
            data = handle.read()
    elif hasattr(value, "read"):
        position = value.tell() if hasattr(value, "tell") else None
        data = value.read()
        if position is not None and hasattr(value, "seek"):
            value.seek(position)
    else:
        data = bytes(value)
    image = CompatibilityImage(data, compatibility_image_size(data))
    kind = compatibility_filetype_guess(data)
    image.format = kind.extension.upper() if kind is not None else None
    return image


def compatibility_numpy_array(value, *args, **kwargs):
    del args, kwargs
    if isinstance(value, CompatibilityImage):
        raise NativeOwnedFeature("pixel array conversion")
    return list(value) if not isinstance(value, list) else value[:]


def compatibility_zeros_like(value):
    if isinstance(value, list):
        return [compatibility_zeros_like(item) for item in value]
    if isinstance(value, tuple):
        return tuple(compatibility_zeros_like(item) for item in value)
    return 0


class UnsupportedWebSocketContext:
    async def __aenter__(self):
        raise NativeOwnedFeature("websocket media negotiation")

    async def __aexit__(self, *_args):
        return False


def compatibility_websocket_connect(*_args, **_kwargs):
    return UnsupportedWebSocketContext()


def compatibility_makedir_event(path, cw=None):
    del cw
    os.makedirs(path, exist_ok=True)
    return path


def compatibility_ok_url(value):
    parsed = urllib.parse.urlsplit(clean_url(value))
    return parsed.scheme.lower() in ("http", "https") and bool(parsed.netloc)


def module(name, values):
    result = types.ModuleType(name)
    result.__dict__.update(values)
    sys.modules[name] = result
    return result


def install_qt_theme_modules():
    gui_values = {
        "QColor": QColor,
        "QBrush": QBrush,
        "QIcon": QIcon,
        "QPalette": QPalette,
        "QGuiApplication": QApplication,
        "qRgb": lambda red, green, blue: (int(red), int(green), int(blue)),
    }
    core_values = {"Qt": Qt}
    widget_values = {
        "QApplication": QApplication,
        "QComboBox": HeadlessComboBox,
        "QDialog": HeadlessDialog,
        "QDialogButtonBox": HeadlessDialogButtonBox,
        "QFormLayout": HeadlessLayout,
        "QInputDialog": QInputDialog,
        "QLabel": HeadlessWidget,
        "QMessageBox": QMessageBox,
        "QProxyStyle": QProxyStyle,
        "QStyle": QStyle,
        "QStyleFactory": QStyleFactory,
        "QVBoxLayout": HeadlessLayout,
        "QWidget": HeadlessWidget,
    }
    for binding in ("PyQt5", "PySide2", "PyQt6", "PySide6"):
        package = module(binding, {})
        package.__path__ = []
        package.QtGui = module(binding + ".QtGui", dict(gui_values))
        package.QtCore = module(binding + ".QtCore", dict(core_values))
        package.QtWidgets = module(binding + ".QtWidgets", dict(widget_values))


def theme_color(value):
    if isinstance(value, QBrush):
        value = value.color()
    if isinstance(value, QColor):
        return value.name()
    if isinstance(value, (tuple, list)) and len(value) >= 3:
        try:
            return QColor(*value[:4]).name()
        except (TypeError, ValueError):
            return None
    text = (string_value(value) or "").strip()
    if not text:
        return None
    lower = text.lower()
    if lower in QColor._names:
        return QColor(lower).name()
    if re.fullmatch(r"#[0-9a-fA-F]{3,8}", text):
        return QColor(text).name()
    if re.fullmatch(r"rgba?\([^)]+\)", lower):
        return QColor(lower).name()
    return None


def theme_value(descriptor, *names):
    lowered = {(string_value(key) or "").lower(): value for key, value in descriptor.items()}
    for name in names:
        if name.lower() in lowered:
            return lowered[name.lower()]
    return None


def theme_bool(value, default=False):
    if value is None:
        return default
    if isinstance(value, str):
        normalized = value.strip().lower()
        if normalized in ("false", "0", "no", "off", ""):
            return False
        if normalized in ("true", "1", "yes", "on"):
            return True
    return bool(value)


def evaluated_theme_value(value, label):
    if not callable(value):
        return value
    try:
        return value()
    except Exception as error:
        print("theme {} callable failed: {}".format(label, error))
        return None


def palette_theme_colors(value):
    value = evaluated_theme_value(value, "palette")
    if value is None:
        return {}
    if isinstance(value, dict):
        lowered = {string_value(key).lower(): item for key, item in value.items()}

        def from_dict(*names):
            for name in names:
                color = theme_color(lowered.get(name.lower()))
                if color:
                    return color
            return None

        return {
            "background": from_dict("window", "background", "bg"),
            "surface": from_dict("base", "button", "alternatebase", "surface"),
            "foreground": from_dict("windowtext", "text", "buttontext", "foreground"),
            "accent": from_dict("highlight", "accent", "link"),
        }
    if not isinstance(value, QPalette):
        return {}

    def palette_color(*roles):
        for role in roles:
            for group in (None, QPalette.Active, QPalette.Inactive, QPalette.Disabled):
                color = value._colors.get((group, role))
                if color is not None:
                    normalized = theme_color(color)
                    if normalized:
                        return normalized
        return None

    return {
        "background": palette_color(QPalette.Window),
        "surface": palette_color(QPalette.Base, QPalette.Button, QPalette.AlternateBase),
        "foreground": palette_color(QPalette.WindowText, QPalette.Text, QPalette.ButtonText),
        "accent": palette_color(QPalette.Highlight, QPalette.Accent, QPalette.Link),
    }


def stylesheet_theme_colors(value):
    value = evaluated_theme_value(value, "style_sheet")
    style = string_value(value) or ""
    if not style:
        return {}, ""
    declarations = []
    expression = re.compile(
        r"(?i)(selection-background-color|background-color|border-color|color)\s*:\s*"
        r"(#[0-9a-f]{3,8}|rgba?\([^)]+\)|[a-z]+)"
    )
    for match in expression.finditer(style):
        color = theme_color(match.group(2))
        if not color:
            continue
        block_start = style.rfind("}", 0, match.start()) + 1
        selector = style[block_start:match.start()].lower()
        declarations.append((match.group(1).lower(), color, selector))

    accent = None
    backgrounds = []
    foregrounds = []
    for property_name, color, selector in declarations:
        accent_context = any(token in selector for token in (
            "progressbar::chunk", "slider::handle", "selection", "selected", "highlight", "link",
        ))
        if property_name == "selection-background-color" or accent_context:
            accent = accent or color
        elif property_name == "background-color":
            backgrounds.append(color)
        elif property_name == "color":
            foregrounds.append(color)
    return {
        "background": backgrounds[0] if backgrounds else None,
        "surface": backgrounds[1] if len(backgrounds) > 1 else None,
        "foreground": foregrounds[0] if foregrounds else None,
        "accent": accent,
    }, style


def theme_luminance(color):
    color = theme_color(color)
    if not color:
        return None
    values = [int(color[index:index + 2], 16) / 255.0 for index in (1, 3, 5)]
    return 0.2126 * values[0] + 0.7152 * values[1] + 0.0722 * values[2]


def run_theme_callback(descriptor, name):
    callback = theme_value(descriptor, name)
    if not callable(callback):
        return False
    try:
        callback()
        return True
    except Exception as error:
        print("theme {} callback failed: {}".format(name, error))
        return False


def theme_descriptor(key, descriptor, run_lifecycle=False):
    application = QApplication.instance()
    prior_state = application.themeState()
    palette_value = None
    style_value = None
    lifecycle_palette_present = False
    lifecycle_style_present = False

    try:
        if run_lifecycle:
            run_theme_callback(descriptor, "__init__")

        palette_value = evaluated_theme_value(theme_value(descriptor, "palette"), "palette")
        if isinstance(palette_value, QPalette):
            application.setPalette(palette_value)
        lifecycle_palette_present = bool(application.palette()._colors)

        style_value = evaluated_theme_value(
            theme_value(descriptor, "style_sheet", "stylesheet"),
            "style_sheet",
        )
        if style_value is not None:
            application.setStyleSheet(style_value)
        lifecycle_style_present = bool(application.styleSheet())

        if run_lifecycle:
            run_theme_callback(descriptor, "after_theme_added")

        final_palette = application.palette()
        final_style = application.styleSheet()
        lifecycle_palette_present = bool(final_palette._colors)
        lifecycle_style_present = bool(final_style)
        palette_source = final_palette if final_palette._colors else palette_value
        style_source = final_style if final_style else style_value
        palette_colors = palette_theme_colors(palette_source)
        style_colors, style = stylesheet_theme_colors(style_source)

        def first_color(*names, fallback=None):
            explicit = theme_color(theme_value(descriptor, *names))
            return explicit or fallback

        background = first_color(
            "background", "background_color", "window_color", "bg_color", "bg",
            fallback=palette_colors.get("background") or style_colors.get("background"),
        )
        surface = first_color(
            "surface", "surface_color", "base_color", "panel_color", "alternate_background",
            fallback=palette_colors.get("surface") or style_colors.get("surface"),
        )
        foreground = first_color(
            "foreground", "foreground_color", "text_color", "color",
            fallback=palette_colors.get("foreground") or style_colors.get("foreground"),
        )
        accent = first_color(
            "accent", "accent_color", "highlight", "highlight_color", "theme_color", "primary_color",
            fallback=palette_colors.get("accent") or style_colors.get("accent"),
        )

        darkmode = theme_value(descriptor, "darkmode", "dark_mode", "appearance")
        if isinstance(darkmode, bool):
            appearance = "dark" if darkmode else "light"
        else:
            mode = (string_value(darkmode) or "").strip().lower()
            if mode in ("dark", "night", "black"):
                appearance = "dark"
            elif mode in ("light", "day", "white"):
                appearance = "light"
            elif mode in ("both", "system", "auto", "automatic"):
                appearance = "system"
            else:
                luminance = theme_luminance(background)
                appearance = "dark" if luminance is not None and luminance < 0.48 else "system"

        return {
            "key": key,
            "displayName": (string_value(theme_value(descriptor, "display_name", "displayName")) or key)[:200],
            "appearance": appearance,
            "accentColor": accent,
            "backgroundColor": background,
            "surfaceColor": surface,
            "foregroundColor": foreground,
            "base": string_value(theme_value(descriptor, "base")),
            "system": theme_bool(theme_value(descriptor, "system")),
            "translucent": theme_bool(theme_value(descriptor, "translucent"), default=True),
            "buttonShadow": theme_bool(theme_value(descriptor, "button_shadow", "buttonShadow"), default=True),
            "styleSheetPresent": bool(style) or lifecycle_style_present,
            "palettePresent": theme_value(descriptor, "palette") is not None or lifecycle_palette_present,
        }
    finally:
        if run_lifecycle:
            run_theme_callback(descriptor, "__del__")
        application.restoreThemeState(prior_state)


def theme_descriptors(run_lifecycle=False):
    return [
        theme_descriptor(key, descriptor, run_lifecycle=run_lifecycle)
        for key, descriptor in REGISTERED_THEMES.items()
    ]


def install_compatibility_modules():
    install_qt_theme_modules()
    common = {
        "Downloader": Downloader,
        "LazyUrl": LazyUrl,
        "File": File,
        "Live": Live,
        "LiveStream": CompatFFmpegStream,
        "Counter": Counter,
        "Progress": Progress,
        "Size": Size,
        "Nothing": Nothing,
        "CustomWidget": DummyCW,
        "Hook": Hook,
        "_Hook": _Hook,
        "QColor": QColor,
        "QBrush": QBrush,
        "QApplication": QApplication,
        "QIcon": QIcon,
        "QInputDialog": QInputDialog,
        "QMessageBox": QMessageBox,
        "QPalette": QPalette,
        "QStyle": QStyle,
        "Qt": Qt,
        "addTheme": addTheme,
        "setTheme": setTheme,
        "updateTheme": updateTheme,
        "THEMES": REGISTERED_THEMES,
        "CURRENT_THEME": CURRENT_THEME,
        "DARK": False,
        "DARKMODE": False,
        "COLOR": {"main": (0, 122, 255), "disable": (120, 120, 120)},
        "pal_default": pal_default,
        "Session": Session,
        "Soup": Soup,
        "read_html": read_html,
        "read_soup": read_soup,
        "read_json": read_json,
        "real_url": real_url,
        "getsize": getsize,
        "get_size": getsize,
        "get_ext": get_ext,
        "get_resolution": get_resolution,
        "get_abr": get_abr,
        "clean_title": clean_title,
        "clean_url": clean_url,
        "remove_dup": remove_dup,
        "fix_dup": fix_dup,
        "fix_enumerate": original_fix_enumerate,
        "fix_protocol": fix_protocol,
        "filter_range": filter_range,
        "Range": Range,
        "try_n": try_n,
        "limits": limits,
        "lock": lock,
        "lazy": lazy,
        "check_alive": check_alive,
        "check_alive_iter": check_alive_iter,
        "get_print": get_print,
        "print_": print_,
        "print_error": print_error,
        "get_max_range": get_max_range,
        "get_restart": get_restart,
        "parse_time_str": parse_time_str,
        "HUGE": HUGE,
        "DEFAULT_MAXIMUM": DEFAULT_MAXIMUM,
        "format_filename": format_filename,
        "format_title": original_format_title,
        "format_title_gal": format_title_gal,
        "fix_title": fix_title,
        "format": original_data_format,
        "capitalize": original_capitalize,
        "query_url": query_url,
        "update_url_query": update_url_query,
        "generate_csrf_token": generate_csrf_token,
        "atoi": atoi,
        "uuid": original_uuid,
        "compatstr": compatstr,
        "join": original_join,
        "domain": original_domain,
        "display_url": display_url,
        "cut_pair": cut_pair,
        "dir": original_dir,
        "esc": original_esc,
        "get_imgs_already": get_imgs_already,
        "get_text": get_text,
        "log": original_log,
        "natural_sort": original_natural_sort,
        "open": original_open,
        "pp_subtitle": original_pp_subtitle,
        "process_olds": original_process_olds,
        "SkipCounter": SkipCounter,
        "SD": ORIGINAL_SITE_DEFAULTS,
        "TOKENS": TOKENS,
        "ADD_TOKENS": ADD_TOKENS,
        "LIVES": ACTIVE_LIVES,
        "ACTIONS": REGISTERED_ACTIONS,
        "json": json,
        "re": re,
        "html": html,
        "tr_": tr_,
        "download": downloader_download,
        "ua": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Safari/537.36",
        "REPLACE_UA": False,
        "makedir_event": compatibility_makedir_event,
        "ok_url": compatibility_ok_url,
        "actions": original_actions,
        "exec_queue": HEADLESS_EXEC_QUEUE,
        "image_reader": HEADLESS_IMAGE_READER,
        "messageBox": headless_message_box,
        "orig_ehen": False,
        "submit_remove": original_submit_remove,
        "ui": HEADLESS_UI,
        "ui_setting": HEADLESS_UI_SETTING,
        "update_live": update_live,
        "windows": HEADLESS_WINDOWS,
        "Invalid": raise_invalid,
        "urljoin": urllib.parse.urljoin,
        "urlparse": urllib.parse.urlparse,
        "parse_qs": urllib.parse.parse_qs,
        "urlencode": urllib.parse.urlencode,
        "quote": urllib.parse.quote,
        "unquote": urllib.parse.unquote,
        "html_escape": html.escape,
        "html_unescape": html.unescape,
    }
    common["__all__"] = sorted(key for key in common if not key.startswith("_"))
    utils_module = module("utils", common)
    downloader_module = module("downloader", dict(common))
    utils_module.downloader = downloader_module
    if "downloader" not in utils_module.__all__:
        utils_module.__all__.append("downloader")
    module("customWidget", {"CustomWidget": DummyCW})
    module("customWidget_new", {"CustomWidget": DummyCW})
    module("size", {"Size": Size})
    module("clf2", {
        "solve": solve,
        "download": browser_download,
        "_is_captcha": lambda source: bool(re.search(
            r"captcha|cf-chl-|challenge-platform|g-recaptcha|hcaptcha", string_value(source) or "", re.I
        )),
        "Timeout": TimeoutError,
    })
    constants_module = module("constants", {
        "LANG": "en",
        "curlang": "en",
        "TIMEOUT": 30,
        "available": [],
        "APP_NAME": "HitomiBadayo",
        "DARKMODE": False,
        "FAST": False,
        "version": "4.2",
        "EH_DOMAINS": ["e-hentai.org", "exhentai.org"],
        "HARUKAS": [],
        "priority": {},
        "available_extra": [],
        "compact": False,
        "admin": False,
        "CODECS_PRI": [],
        "ALANG": "en",
        "opacity_max": 1.0,
        "CW_VERSION": "1.2",
        "root": tempfile.gettempdir(),
        "outdir": tempfile.gettempdir(),
        "mainWindow": None,
        "langs_cc": ["en"],
        "TAG_TIMER": TAG_TIMER,
        "HUGE": HUGE,
        "DEFAULT_MAXIMUM": DEFAULT_MAXIMUM,
        "compatstr": string_value,
        "uuid": original_uuid,
        "isValidURL": is_valid_url,
        "isValidURL_single": is_valid_url,
        "mybrowser": None,
        "resize_dpi": lambda value: value,
        "setChanged": lambda: None,
    })

    dateutil_parser_module = module("dateutil.parser", {
        "parse": compatibility_datetime_parse,
        "ParserError": ValueError,
        "__all__": ["parse", "ParserError"],
    })
    dateutil_module = module("dateutil", {
        "parser": dateutil_parser_module,
        "__version__": "2.8-compatible",
    })
    dateutil_module.__path__ = []

    bs4_element_module = module("bs4.element", {
        "Tag": MiniNode,
        "PageElement": MiniNode,
        "NavigableString": str,
    })
    bs4_module = module("bs4", {
        "BeautifulSoup": compatibility_beautiful_soup,
        "element": bs4_element_module,
        "__all__": ["BeautifulSoup"],
    })
    bs4_module.__path__ = []

    filetype_module = module("filetype", {
        "guess": compatibility_filetype_guess,
        "guess_extension": lambda value: (
            compatibility_filetype_guess(value).extension
            if compatibility_filetype_guess(value) is not None else None
        ),
        "guess_mime": lambda value: (
            compatibility_filetype_guess(value).mime
            if compatibility_filetype_guess(value) is not None else None
        ),
        "Type": CompatibilityFileType,
    })

    image_module = module("PIL.Image", {
        "Image": CompatibilityImage,
        "open": compatibility_image_open,
        "fromarray": native_owned("Pillow fromarray"),
        "new": lambda mode, size, color=None: CompatibilityImage(b"", size, mode),
    })
    pil_module = module("PIL", {"Image": image_module})
    pil_module.__path__ = []

    module("numpy", {
        "array": compatibility_numpy_array,
        "asarray": compatibility_numpy_array,
        "zeros_like": compatibility_zeros_like,
        "ndarray": list,
        "uint8": int,
    })
    module("websockets", {
        "connect": compatibility_websocket_connect,
        "ConnectionClosed": RuntimeError,
    })

    module("cacher", {
        "Cache": CompatibilityCache,
        "CacheDecorator": CompatibilityCacheDecorator,
        "cache": CompatibilityCacheDecorator,
    })
    module("clock", {
        "clock": CompatibilityClock,
        "TIMES": CompatibilityClock.TIMES,
        "COUNTS": CompatibilityClock.COUNTS,
    })
    module("locker", {
        "lock": lock,
        "lock_n": compatibility_lock_n,
        "close": lambda: None,
    })
    filesystem_units = types.SimpleNamespace()
    module("filesize", {
        "size": compatibility_filesize,
        "alternative": filesystem_units,
        "traditional": filesystem_units,
    })
    compatibility_options = {}
    module("options", {
        "OPTIONS": compatibility_options,
        "get": lambda key, default=None: compatibility_options.get(key, default),
    })
    module("Qt", {
        "Qt": Qt,
        "QComboBox": HeadlessComboBox,
        "QDialog": HeadlessDialog,
        "QDialogButtonBox": HeadlessDialogButtonBox,
        "QFormLayout": HeadlessLayout,
        "QLabel": HeadlessWidget,
        "QVBoxLayout": HeadlessLayout,
        "QWidget": HeadlessWidget,
    })
    module("ips", {"get": lambda *_args, **_kwargs: ""})
    module("order", {"getOrder": lambda values, *_args, **_kwargs: values})

    torrent_unavailable = native_owned("BitTorrent transfer")
    module("torrent", {
        "set_max_speed": lambda *_args, **_kwargs: None,
        "set_anon": lambda *_args, **_kwargs: None,
        "set_proxy": lambda *_args, **_kwargs: None,
        "key_id": lambda value: (clean_url(value), None),
        "get_info": torrent_unavailable,
        "get_files": torrent_unavailable,
        "download": torrent_unavailable,
        "get_file_progress": torrent_unavailable,
        "pieces": torrent_unavailable,
    })

    exhen_downloader_module = module("extractor.exhen_downloader", {
        "get_cookie": lambda *_args, **_kwargs: {},
    })
    hiyobi_downloader_module = module("extractor.hiyobi_downloader", {
        "pop_img_hiyobi": native_owned("Hiyobi image extraction"),
    })
    extractor_module = module("extractor", {
        "exhen_downloader": exhen_downloader_module,
        "hiyobi_downloader": hiyobi_downloader_module,
    })
    extractor_module.__path__ = []
    module("exhen_utils", {"USERS": {}})
    module("hitomi_downloader", {"ehen_token": ""})
    module("fucking_encoding", {"refine_gal_num": refine_gallery_number})
    module("gallery", {
        "get_gal": native_owned("Hitomi gallery metadata"),
        "get_gal_ehen": native_owned("E-Hentai gallery metadata"),
    })
    module("hitomi", {
        "Session": Session,
        "pop_img": native_owned("Hitomi gallery image extraction"),
        "get_gal": native_owned("Hitomi gallery metadata"),
        "get_gallery_url": lambda value: "https://hitomi.la/galleries/{}.html".format(int(value)),
        "read_ani": native_owned("Hitomi animation extraction"),
    })

    ree_values = {
        name: getattr(re, name)
        for name in dir(re)
        if not name.startswith("_")
    }
    ree_values.update({"NotFound": ReeNotFound, "find": ree_find})
    ree_values["__all__"] = sorted(name for name in ree_values if not name.startswith("_"))
    ree_module = module("ree", ree_values)
    utils_module.re = ree_module
    downloader_module.re = ree_module
    module("mastodon", {"get_info": mastodon_get_info, "__all__": ["get_info"]})
    ratelimit_decorators = module("ratelimit.decorators", {
        "RateLimitDecorator": RateLimitDecorator,
        "sleep_and_retry": sleep_and_retry,
        "now": time.monotonic,
        "__all__": ["RateLimitDecorator", "sleep_and_retry"],
    })
    ratelimit_exception = module("ratelimit.exception", {
        "RateLimitException": RateLimitException,
        "__all__": ["RateLimitException"],
    })
    ratelimit_module = module("ratelimit", {
        "RateLimitDecorator": RateLimitDecorator,
        "RateLimitException": RateLimitException,
        "limits": RateLimitDecorator,
        "rate_limited": RateLimitDecorator,
        "sleep_and_retry": sleep_and_retry,
        "__all__": ["RateLimitException", "limits", "rate_limited", "sleep_and_retry"],
        "__version__": "2.2.1",
    })
    ratelimit_module.__path__ = []
    ratelimit_module.decorators = ratelimit_decorators
    ratelimit_module.exception = ratelimit_exception
    downloader_v3_module = module("downloader_v3", {
        "Task": DownloaderV3Task,
        "Thread": threading.Thread,
        "threads": DOWNLOADER_V3_THREADS,
        "update_progress": downloader_v3_update_progress,
        "download": downloader_v3_download,
        "OPEN_QT": False,
        "TIMEOUT": 180,
        "__all__": ["threads", "download"],
    })
    module("translator", {
        "DICS": TRANSLATIONS,
        "DICS_sp": TRANSLATIONS_SPECIAL,
        "DICS_nm": TRANSLATIONS_NORMAL,
        "SEP": TRANSLATION_SEPARATOR,
        "update_tr": update_translation,
        "translate": translate,
        "print_error": lambda: traceback.format_exc(),
        "tr_": tr_,
        "tr": tr,
        "tr_app": lambda value, lang=None: tr(value, lang),
    })
    errors_module = module("errors", {
        "Invalid": InvalidError,
        "LoginRequired": LoginRequired,
        "BrowserRequired": BrowserRequired,
        "OutdatedExtension": OutdatedExtension,
        "Disgusting": Disgusting,
        "Retry": Retry,
        "StopReading": StopReading,
        "errors": ORIGINAL_ERRORS,
    })
    errors_module.__all__ = [error.__name__ for error in ORIGINAL_ERRORS] + ["errors"]
    for common_module_name in ("utils", "downloader"):
        common_module = sys.modules[common_module_name]
        common_module.errors = errors_module
        if "errors" not in common_module.__all__:
            common_module.__all__.append("errors")
    module("timee", {
        "sleep": compatibility_sleep,
        "_sleep": time.sleep,
        "time": time.time,
        "perf_counter": time.perf_counter,
        "monotonic": time.monotonic,
        "clock": time.perf_counter,
        "uclock": lambda: time.perf_counter(),
    })
    module("error_printer", {
        "_format_exc": format_compatibility_traceback,
        "format_exc": format_compatibility_traceback,
        "format_exc0": traceback.format_exc,
        "print_error": print_error,
    })
    selector_module = module("selector", {
        "Cancel": SELECTOR_CANCEL,
        "CALLBACKS": SELECTOR_CALLBACKS,
        "OPTIONS": SELECTOR_OPTIONS,
        "DEFAULT": SELECTOR_DEFAULT,
        "register": selector_register,
        "process": selector_process,
        "options": selector_options,
        "default_option": selector_default_option,
    })
    selector_module.__all__ = [
        "Cancel", "CALLBACKS", "OPTIONS", "DEFAULT", "register", "process",
        "options", "default_option",
    ]
    page_selector_module = module("page_selector", {
        "get_pagess": PAGE_CALLBACKS,
        "register": page_register,
        "filter": page_filter,
        "selectPages": select_pages,
    })
    page_selector_module.__all__ = ["get_pagess", "register", "filter", "selectPages"]
    temp_directory = os.path.abspath(tempfile.gettempdir())
    module("putils", {
        "DIR": temp_directory,
        "DIRf": temp_directory,
        "kill": kill_process,
    })
    m3u8_module = module("m3u8_tools", {
        "EMPTY_SEG": EmptySegment,
        "Thread": threading.Thread,
        "Segment": Segment,
        "M3u8_stream": M3u8Stream,
        "Dash_stream": DashStream,
        "playlist2stream": playlist2stream,
        "dash2stream": dash2stream,
        "urljoin_q": urljoin_q,
        "POST_PROCESSING": True,
        "DEFAULT_N_THREAD": 2,
        "DEFAULT_N_THREAD_LIVE": 1,
    })
    m3u8_module.__all__ = [
        "Thread", "Segment", "M3u8_stream", "Dash_stream", "playlist2stream", "dash2stream",
    ]
    ffmpeg_module = module("ffmpeg", {
        "ALIVE": True,
        "DEFAULT_PIPE_OPTIONS": FFMPEG_DEFAULT_PIPE_OPTIONS,
        "THREADS": FFMPEG_THREADS,
        "LOCAL_FFMPEG": bool(os.environ.get("HITOMI_NATIVE_FFMPEG")),
        "LOCAL_FFPROBE": bool(os.environ.get("HITOMI_NATIVE_FFPROBE")),
        "pids": FFMPEG_PROCESSES,
        "Popen": CompatFFmpegPopen,
        "kill": ffmpeg_kill,
        "end": ffmpeg_end,
        "ready": ffmpeg_ready,
        "load": ffmpeg_load,
        "get_print": get_print,
        "run": ffmpeg_run,
        "check_code": ffmpeg_check_code,
        "rename": ffmpeg_rename,
        "merge": ffmpeg_merge,
        "convert": ffmpeg_convert,
        "gif_video": ffmpeg_gif_video,
        "gif": ffmpeg_gif,
        "gif_": ffmpeg_gif_force,
        "join_force": ffmpeg_join_force,
        "join": ffmpeg_join,
        "add_cover": ffmpeg_add_cover,
        "Chapter": CompatFFmpegChapter,
        "add_chapters": ffmpeg_add_chapters,
        "is_image": ffmpeg_is_image,
        "capture_fast": ffmpeg_capture_fast,
        "capture": ffmpeg_capture,
        "get_info": ffmpeg_get_info,
        "s2secs": ffmpeg_s2secs,
        "s2size": ffmpeg_s2size,
        "pipe": ffmpeg_pipe,
        "print_res": ffmpeg_print_res,
        "Stream": CompatFFmpegStream,
    })
    ffmpeg_module.__all__ = [
        "Popen", "kill", "end", "ready", "load", "get_print", "run", "rename",
        "check_code", "merge", "convert", "gif_video", "gif", "gif_", "join_force", "join", "add_cover",
        "Chapter", "add_chapters", "is_image", "capture_fast", "capture", "get_info",
        "s2secs", "s2size", "pipe", "print_res", "Stream",
    ]
    for common_module_name in ("utils", "downloader"):
        common_module = sys.modules[common_module_name]
        common_module.ffmpeg = ffmpeg_module
        common_module.Stream = CompatFFmpegStream
        for exported_name in ("ffmpeg", "Stream"):
            if exported_name not in common_module.__all__:
                common_module.__all__.append(exported_name)
    ytdl_module = module("ytdl", {
        "DOWNLOAD": YTDL_DOWNLOAD,
        "OPTIONS": YTDL_OPTIONS,
        "LIVE_FROM_START": YTDL_LIVE_FROM_START,
        "YoutubeDL": CompatYoutubeDL,
        "YouTube": CompatYouTube,
        "Video": CompatYTDLVideo,
        "Downloader": CompatYTDLDownloader,
        "extractor": CompatYTDLExtractorNamespace(),
        "get_ytdl": get_ytdl,
        "get_extractor": get_extractor,
        "get_extractor_name": get_extractor_name,
        "extractor_to_name": extractor_to_name,
        "get_subtitles": get_subtitles,
        "download_thumb": download_thumb,
    })
    ytdl_module.__all__ = [
        "DOWNLOAD", "OPTIONS", "LIVE_FROM_START", "YoutubeDL", "YouTube", "Video",
        "Downloader", "extractor", "get_ytdl", "get_extractor", "get_extractor_name",
        "extractor_to_name", "get_subtitles", "download_thumb",
    ]
    constants_module.errors = errors_module

    if "requests" not in sys.modules:
        try:
            __import__("requests")
        except ImportError:
            requests_module = module("requests", {
                "Session": Session,
                "Response": CompatResponse,
                "get": request_get,
                "post": request_post,
                "head": lambda url, **kwargs: Session().head(url, **kwargs),
                "put": lambda url, **kwargs: Session().put(url, **kwargs),
                "patch": lambda url, **kwargs: Session().patch(url, **kwargs),
                "delete": lambda url, **kwargs: Session().delete(url, **kwargs),
                "options": lambda url, **kwargs: Session().options(url, **kwargs),
                "request": lambda method, url, **kwargs: Session().request(method, url, **kwargs),
            })
            requests_module.exceptions = types.SimpleNamespace(
                RequestException=Exception,
                HTTPError=RuntimeError,
                ConnectionError=OSError,
                Timeout=TimeoutError,
                TooManyRedirects=RuntimeError,
            )

    return common


def load_script(path):
    global CURRENT_THEME
    REGISTERED_DOWNLOADERS[:] = []
    Downloader.types.clear()
    Downloader.instances[:] = []
    LazyUrl.types.clear()
    for event in HOOK_EVENTS:
        REGISTERED_HOOKS[event].clear()
    REGISTERED_THEMES.clear()
    CURRENT_THEME = "default"
    QApplication.resetThemeState()
    source_path = pathlib.Path(path).resolve()
    if not source_path.is_file():
        raise FileNotFoundError(str(source_path))
    if source_path.stat().st_size > 128 * 1024 * 1024:
        raise ValueError("Script exceeds the 128 MiB limit")
    raw = source_path.read_bytes()
    source = None
    encoding = None
    for candidate in ("utf-8-sig", "utf-8", "cp949", "shift_jis", "cp1252", "latin-1"):
        try:
            source = raw.decode(candidate)
            encoding = candidate
            break
        except UnicodeDecodeError:
            continue
    if source is None:
        raise UnicodeError("Unable to decode script")

    compat = install_compatibility_modules()
    script_module = types.ModuleType("hitomi_user_script_" + hashlib.sha256(raw).hexdigest()[:16])
    script_module.__file__ = str(source_path)
    script_module.__package__ = None
    script_module.__dict__.update(compat)
    script_module.__dict__.update({
        "os": os,
        "re": re,
        "json": json,
        "time": time,
        "threading": threading,
        "urllib": urllib,
        "urlparse": urllib.parse.urlparse,
        "urlencode": urllib.parse.urlencode,
    })
    sys.modules[script_module.__name__] = script_module
    sys.path.insert(0, str(source_path.parent))
    try:
        code = compile(source, str(source_path), "exec")
        exec(code, script_module.__dict__, script_module.__dict__)
    finally:
        if sys.path and sys.path[0] == str(source_path.parent):
            sys.path.pop(0)
    return script_module, encoding, raw


def descriptor(downloader_class):
    patterns = getattr(downloader_class, "URLS", None) or []
    if isinstance(patterns, (str, bytes)):
        patterns = [patterns]
    return {
        "className": downloader_class.__name__,
        "type": string_value(getattr(downloader_class, "type", None)) or downloader_class.__name__,
        "urlPatterns": [string_value(value) for value in patterns if string_value(value)],
        "single": bool(getattr(downloader_class, "single", False)),
    }


def hook_descriptors():
    return [
        {"event": event, "name": name}
        for event in HOOK_EVENTS
        for name in REGISTERED_HOOKS[event]
    ]


def call_fix_url(downloader_class, url):
    function = getattr(downloader_class, "fix_url", None)
    if not callable(function):
        return url
    try:
        value = function(url)
    except TypeError:
        value = function(downloader_class, url)
    return clean_url(value or url)


def instantiate(downloader_class, url):
    cw = DummyCW(url)
    try:
        signature = inspect.signature(downloader_class)
        positional = [parameter for parameter in signature.parameters.values()
                      if parameter.kind in (parameter.POSITIONAL_ONLY, parameter.POSITIONAL_OR_KEYWORD)]
        has_varargs = any(parameter.kind == parameter.VAR_POSITIONAL
                          for parameter in signature.parameters.values())
        if not positional and not has_varargs:
            instance = downloader_class()
            instance.url = url
        elif len(positional) <= 1 and not has_varargs:
            instance = downloader_class(url)
        else:
            instance = downloader_class(url, cw)
    except (TypeError, ValueError):
        instance = downloader_class(url, cw)
    if not hasattr(instance, "_cw"):
        instance._cw = cw
    if not hasattr(instance, "_urls"):
        instance._urls = []
    if not hasattr(instance, "_filenames"):
        instance._filenames = {}
    if not getattr(instance, "session", None):
        instance.session = Session()
    cw.downloader = instance
    cw.single = bool(getattr(instance, "single", False))
    return instance


def prepare_asset_items(instance, values):
    prepared = []
    cw = getattr(instance, "_cw", None) or getattr(instance, "cw", None)
    for index, item in enumerate(values):
        if isinstance(item, File) and not item._hitomi_native_ready:
            should_resolve = type(item).get is not File.get or item.url is None
            if should_resolve:
                extra_files = item.ready(cw, index)
                prepared.append(item)
                prepared.extend(value[2] for value in extra_files)
                continue
        prepared.append(item)
    return prepared


def filename_for(instance, original, resolved, index):
    filenames = getattr(instance, "filenames", {}) or {}
    if isinstance(filenames, dict):
        for key, value in filenames.items():
            matches = key is original or key is resolved
            if not matches:
                try:
                    matches = string_value(key) in {string_value(original), string_value(resolved)}
                except Exception:
                    matches = False
            if matches and value:
                return string_value(value)
        for key in (index, index + 1, str(index), str(index + 1)):
            if key in filenames and filenames[key]:
                return string_value(filenames[key])
    path = urllib.parse.urlsplit(string_value(resolved) or "").path
    name = urllib.parse.unquote(pathlib.PurePosixPath(path).name)
    return name or "{:04d}.bin".format(index + 1)


def normalized_headers(value):
    if not isinstance(value, dict):
        return {}
    return {string_value(key): string_value(item) for key, item in value.items()
            if string_value(key) and string_value(item)}


def flattened_ffmpeg_stream_others(stream, limit=256):
    result = []
    active = set()

    def visit(value):
        identity = id(value)
        if identity in active:
            raise ValueError("ffmpeg.Stream contains a recursive addition")
        active.add(identity)
        try:
            for other in list(getattr(value, "others", None) or []):
                if not isinstance(other, CompatFFmpegStream):
                    raise TypeError("ffmpeg.Stream additions must also be Stream instances")
                result.append(other)
                if len(result) > limit:
                    raise ValueError("ffmpeg.Stream contains too many additions")
                visit(other)
        finally:
            active.remove(identity)

    visit(stream)
    return result


def resolved_custom_stream_urls(stream):
    base_url = clean_url(getattr(stream, "base_url", None)) or clean_url(getattr(stream, "url", None))
    if isinstance(stream, CompatFFmpegStream) and stream._fragments:
        values = stream._fragments({}) if callable(stream._fragments) else stream._fragments
        result = []
        for item in list(values or []):
            raw_url = item.get("url") if isinstance(item, dict) else item
            value = clean_url(raw_url)
            if value:
                result.append(urljoin_q(base_url, value))
        return result
    result = []
    for item in list(getattr(stream, "urls", None) or []):
        if isinstance(item, (tuple, list)) and len(item) == 2:
            item = item[1]
        raw_url = getattr(item, "url", item)
        value = clean_url(raw_url)
        if not value:
            continue
        if base_url:
            value = urljoin_q(base_url, value)
        result.append(value)
    return result


def resolved_stream_asset(instance, stream, original, index, filename, referer,
                          user_agent, headers, metadata, include_additional=True):
    inherited_referer = referer
    inherited_user_agent = user_agent
    inherited_headers = dict(headers)
    stream_type = string_value(getattr(stream, "stream_type", None)) or "m3u8"
    session = getattr(stream, "session", None)
    headers.update(normalized_headers(getattr(session, "headers", None)))
    headers.update(normalized_headers(getattr(stream, "headers", None)))
    cookies = getattr(session, "cookies", None)
    if cookies is not None and not any(key.lower() == "cookie" for key in headers):
        try:
            values = cookies.get_dict()
        except AttributeError:
            values = {cookie.name: cookie.value for cookie in cookies}
        if values:
            headers["Cookie"] = "; ".join("{}={}".format(key, value)
                                                for key, value in values.items())

    referer = string_value(getattr(stream, "referer", None)) or referer
    stream_referer = getattr(stream, "referer_seg", "auto")
    if stream_referer == "auto":
        stream_referer = referer
    else:
        stream_referer = string_value(stream_referer)
    user_agent = string_value(getattr(stream, "user_agent", None)) or user_agent
    if not user_agent:
        user_agent = next((value for key, value in headers.items()
                           if key.lower() == "user-agent"), None)

    stream_url = clean_url(getattr(stream, "url", None))
    if not stream_url:
        raise ValueError("Empty stream URL at index {}".format(index))
    if not filename:
        path = pathlib.PurePosixPath(urllib.parse.urlsplit(stream_url).path)
        stem = path.stem or "stream-{:04d}".format(index + 1)
        filename = stem + ".ts"
    metadata.update(normalized_headers(getattr(stream, "info", None)))
    preferred = string_value(getattr(stream, "_hitomi_native_preferred_resolution", None))
    custom_urls = resolved_custom_stream_urls(stream)
    decorator = getattr(stream, "deco", None)
    alter = getattr(stream, "alter", None)
    post_processing = getattr(stream, "post_processing", None)
    has_decorator = decorator is not None
    has_alter = alter is not None
    additional_streams = []
    if include_additional and isinstance(stream, CompatFFmpegStream):
        for additional in flattened_ffmpeg_stream_others(stream):
            additional_streams.append(resolved_stream_asset(
                instance,
                additional,
                additional,
                index,
                "",
                inherited_referer,
                inherited_user_agent,
                dict(inherited_headers),
                {},
                include_additional=False,
            ))
    return {
        "url": stream_url,
        "filename": filename,
        "referer": referer,
        "userAgent": user_agent,
        "headers": headers,
        "metadata": metadata,
        "stream": {
            "type": stream_type,
            "baseURL": string_value(getattr(stream, "base_url", None)),
            "segmentReferer": stream_referer,
            "preferredResolution": preferred,
            "live": bool(getattr(stream, "live", False)),
            "customURLCount": len(custom_urls),
            "customURLs": custom_urls,
            "hasDecorator": has_decorator,
            "hasAlter": has_alter,
            "hasTransforms": has_decorator or has_alter,
            "postProcessing": None if post_processing is None else bool(post_processing),
            "additionalStreams": additional_streams,
        },
    }


def resolve_asset(instance, item, index, default_referer, default_user_agent, default_headers):
    original = item
    filename = None
    referer = default_referer
    user_agent = default_user_agent
    headers = dict(default_headers)
    metadata = {}

    if isinstance(item, File):
        filename = item.filename or item.name
        referer = string_value(item.referer) or referer
        headers.update(normalized_headers(item.headers))
        item = item.url
    if isinstance(item, LazyUrl):
        referer = item.referer or referer
        item = item()
    elif callable(item) and not isinstance(item, (str, bytes)):
        item = item()
    if isinstance(item, CompatYTDLDownloader):
        item = item.native_asset()
    elif isinstance(item, CompatYTDLVideo):
        item = item.url
    if isinstance(item, (M3u8Stream, CompatFFmpegStream)):
        return resolved_stream_asset(
            instance, item, original, index, filename, referer, user_agent, headers, metadata
        )
    if isinstance(item, dict):
        filename = item.get("filename") or item.get("name") or filename
        referer = string_value(item.get("referer")) or referer
        user_agent = string_value(item.get("userAgent") or item.get("user_agent")) or user_agent
        headers.update(normalized_headers(item.get("headers")))
        metadata.update(normalized_headers(item.get("metadata")))
        item = item.get("url") or item.get("src")
    elif isinstance(item, (list, tuple)):
        if not item:
            raise ValueError("Empty URL tuple at index {}".format(index))
        if len(item) > 1 and item[1]:
            filename = string_value(item[1])
        item = item[0]
    if isinstance(item, LazyUrl):
        referer = item.referer or referer
        item = item()
    if isinstance(item, CompatYTDLDownloader):
        item = item.native_asset()
    elif isinstance(item, CompatYTDLVideo):
        item = item.url
    if isinstance(item, (M3u8Stream, CompatFFmpegStream)):
        return resolved_stream_asset(
            instance, item, original, index, filename, referer, user_agent, headers, metadata
        )

    url = clean_url(item)
    if not url:
        raise ValueError("Empty URL at index {}".format(index))
    filename = filename or filename_for(instance, original, item, index)
    return {
        "url": url,
        "filename": filename,
        "referer": referer,
        "userAgent": user_agent,
        "headers": headers,
        "metadata": metadata,
    }


def run_inspect(request):
    _module, encoding, raw = load_script(request["scriptPath"])
    return {
        "ok": True,
        "encoding": encoding,
        "sha256": hashlib.sha256(raw).hexdigest(),
        "downloaders": [descriptor(value) for value in REGISTERED_DOWNLOADERS],
        "hooks": hook_descriptors(),
        "themes": theme_descriptors(run_lifecycle=True),
    }


def run_resolve(request):
    _module, encoding, raw = load_script(request["scriptPath"])
    class_name = request.get("className")
    downloader_class = next((value for value in REGISTERED_DOWNLOADERS
                             if value.__name__ == class_name), None)
    if downloader_class is None:
        raise ValueError("Downloader class is no longer registered: {}".format(class_name))
    source_url = call_fix_url(downloader_class, request["sourceURL"])
    instance = instantiate(downloader_class, source_url)
    instance.init()
    instance.read()

    urls = prepare_asset_items(instance, list(getattr(instance, "urls", None) or []))
    max_assets = max(1, min(100000, int(request.get("maxAssets", 100000))))
    if len(urls) > max_assets:
        raise ValueError("Script returned too many URLs: {} (limit {})".format(len(urls), max_assets))
    if not urls:
        raise ValueError("Script completed without adding any URLs")

    class_headers = normalized_headers(getattr(instance, "header", None))
    session_headers = normalized_headers(getattr(getattr(instance, "session", None), "headers", None))
    default_headers = normalized_headers(request.get("requestHeaders"))
    default_headers.update(class_headers)
    default_headers.update(session_headers)
    referer = string_value(getattr(instance, "referer", None))
    user_agent = string_value(getattr(instance, "user_agent", None))
    if not user_agent:
        user_agent = default_headers.pop("User-Agent", None) or default_headers.pop("user-agent", None)
    if not referer:
        referer = default_headers.pop("Referer", None) or default_headers.pop("referer", None)

    assets = [resolve_asset(instance, value, index, referer, user_agent, default_headers)
              for index, value in enumerate(urls)]
    title = clean_title(getattr(instance, "title", None) or pathlib.PurePosixPath(urllib.parse.urlsplit(source_url).path).name or "download")
    artist = string_value(getattr(instance, "artist", None))
    result_metadata = normalized_headers(getattr(instance, "metadata", None))
    cw = getattr(instance, "_cw", None) or getattr(instance, "cw", None)
    result_metadata.update(normalized_headers(getattr(cw, "metadata", None)))
    if getattr(cw, "live", False):
        result_metadata.update({"live": "true", "is_live": "true"})
    return {
        "ok": True,
        "encoding": encoding,
        "sha256": hashlib.sha256(raw).hexdigest(),
        "downloaders": [descriptor(value) for value in REGISTERED_DOWNLOADERS],
        "hooks": hook_descriptors(),
        "themes": theme_descriptors(),
        "selected": descriptor(downloader_class),
        "result": {
            "title": title,
            "artist": artist,
            "sourceURL": source_url,
            "single": bool(getattr(instance, "single", False)),
            "metadata": result_metadata,
            "assets": assets,
        },
    }


def materialized_asset_item(item):
    for _ in range(12):
        if isinstance(item, M3u8Stream):
            return item
        if isinstance(item, File):
            item = item.url
            continue
        if isinstance(item, LazyUrl):
            item = item()
            continue
        if callable(item) and not isinstance(item, (str, bytes)):
            item = item()
            continue
        if isinstance(item, CompatYTDLDownloader):
            item = item.native_asset()
            continue
        if isinstance(item, CompatYTDLVideo):
            item = item.url
            continue
        if isinstance(item, dict):
            item = item.get("url") or item.get("src")
            continue
        if isinstance(item, (list, tuple)):
            if not item:
                return item
            item = item[0]
            continue
        return item
    raise ValueError("Asset callback nesting is too deep")


def selected_stream(request):
    _module, encoding, raw = load_script(request["scriptPath"])
    class_name = request.get("className")
    downloader_class = next((value for value in REGISTERED_DOWNLOADERS
                             if value.__name__ == class_name), None)
    if downloader_class is None:
        raise ValueError("Downloader class is no longer registered: {}".format(class_name))
    source_url = call_fix_url(downloader_class, request["sourceURL"])
    instance = instantiate(downloader_class, source_url)
    instance.init()
    instance.read()
    urls = prepare_asset_items(instance, list(getattr(instance, "urls", None) or []))
    stream_index = int(request.get("streamIndex", -1))
    if stream_index < 0 or stream_index >= len(urls):
        raise ValueError("Stream index is no longer available: {}".format(stream_index))
    stream = materialized_asset_item(urls[stream_index])
    if not isinstance(stream, M3u8Stream):
        raise ValueError("Asset at index {} is no longer an M3u8_stream".format(stream_index))
    stream.cw = getattr(instance, "_cw", None) or getattr(instance, "cw", None)
    return encoding, raw, instance, stream


def atomic_replace_bytes(path, data):
    directory = os.path.dirname(path) or os.getcwd()
    descriptor, temporary = tempfile.mkstemp(prefix=".hitominative-deco-", dir=directory)
    try:
        with os.fdopen(descriptor, "wb") as handle:
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
    except Exception:
        try:
            os.close(descriptor)
        except OSError:
            pass
        try:
            os.unlink(temporary)
        except OSError:
            pass
        raise


def run_stream_decorate(request):
    encoding, raw, _instance, stream = selected_stream(request)
    decorator = getattr(stream, "deco", None)
    if not callable(decorator):
        raise ValueError("Selected M3u8_stream no longer has a byte decorator")
    paths = list(request.get("segmentPaths") or [])
    if not paths:
        raise ValueError("No segment files were provided for decoration")
    if len(paths) > 100000:
        raise ValueError("Too many segment files were provided")

    transformed = 0
    for path in paths:
        path = os.path.abspath(string_value(path) or "")
        if not os.path.isfile(path):
            raise ValueError("Segment file does not exist: {}".format(path))
        with io.open(path, "rb") as handle:
            data = handle.read()
        value = decorator(data)
        if isinstance(value, memoryview):
            value = value.tobytes()
        elif isinstance(value, bytearray):
            value = bytes(value)
        if not isinstance(value, bytes):
            raise TypeError("M3u8_stream deco must return bytes, not {}".format(
                type(value).__name__))
        atomic_replace_bytes(path, value)
        transformed += 1

    return {
        "ok": True,
        "encoding": encoding,
        "sha256": hashlib.sha256(raw).hexdigest(),
        "transformedCount": transformed,
    }


def segment_key_from_request(value):
    key_url = clean_url(value.get("keyURL"))
    if not key_url:
        return None
    encoded_iv = string_value(value.get("keyIV"))
    iv = None
    if encoded_iv:
        iv = "0x" + base64.b64decode(encoded_iv).hex()
    return SegmentKey("AES-128", key_url, iv)


def serialized_segment_key(key, base_url):
    if key is None:
        return False, None, None
    if isinstance(key, dict):
        method = string_value(key.get("method"))
        uri = key.get("uri") or key.get("url")
        iv = key.get("iv")
    else:
        method = string_value(getattr(key, "method", None))
        uri = getattr(key, "uri", None) or getattr(key, "url", None)
        iv = getattr(key, "iv", None)
    if method and method.upper() == "NONE":
        return False, None, None
    key_url = clean_url(uri)
    if key_url:
        key_url = urljoin_q(base_url, key_url)
    encoded_iv = None
    if isinstance(iv, bytes):
        encoded_iv = base64.b64encode(iv).decode("ascii")
    elif iv is not None:
        value = string_value(iv).strip()
        if value.lower().startswith("0x"):
            value = value[2:]
        try:
            encoded_iv = base64.b64encode(bytes.fromhex(value)).decode("ascii")
        except (TypeError, ValueError):
            try:
                base64.b64decode(value, validate=True)
                encoded_iv = value
            except (ValueError, TypeError):
                encoded_iv = None
    return True, key_url or None, encoded_iv


def altered_segment_payload(item, source_index, stream):
    if item is EmptySegment or isinstance(item, EmptySegment):
        return None
    if isinstance(item, dict):
        raw_url = item.get("url") or item.get("uri") or item.get("src")
        headers = normalized_headers(item.get("headers"))
        key = item.get("key")
        ignore_error = bool(item.get("ignoreError") or item.get("ignore_error"))
        item_source_index = item.get("sourceIndex", source_index)
    else:
        raw_url = getattr(item, "url", None) or getattr(item, "uri", None) or item
        headers = normalized_headers(getattr(item, "headers", None))
        key = getattr(item, "key", None)
        ignore_error = bool(getattr(item, "_ignore_err", False))
        item_source_index = getattr(item, "_hitomi_native_source_index", source_index)
    url = clean_url(raw_url)
    if not url:
        raise ValueError("alter returned a segment without a URL")
    base_url = clean_url(getattr(stream, "base_url", None)) or clean_url(getattr(stream, "url", None))
    url = urljoin_q(base_url, url)
    try:
        item_source_index = int(item_source_index)
    except (TypeError, ValueError):
        item_source_index = source_index
    has_key, key_url, key_iv = serialized_segment_key(key, base_url)
    return {
        "sourceIndex": item_source_index,
        "url": url,
        "headers": headers,
        "hasKey": has_key,
        "keyURL": key_url,
        "keyIV": key_iv,
        "ignoreError": ignore_error,
    }


def run_stream_alter(request):
    encoding, raw, instance, stream = selected_stream(request)
    alter = getattr(stream, "alter", None)
    if not callable(alter):
        raise ValueError("Selected M3u8_stream no longer has a segment-alter callback")
    values = list(request.get("segments") or [])
    if not values:
        raise ValueError("No segments were provided for alteration")
    if len(values) > 100000:
        raise ValueError("Too many segments were provided")

    base_url = clean_url(getattr(stream, "base_url", None)) or clean_url(getattr(stream, "url", None))
    session = getattr(stream, "session", None) or getattr(instance, "session", None) or Session()
    cw = getattr(instance, "_cw", None) or getattr(instance, "cw", None)
    altered = []
    for fallback_index, value in enumerate(values):
        source_index = int(value.get("sourceIndex", fallback_index))
        segment = Segment(value.get("url"), base_url, session, normalized_headers(value.get("headers")))
        segment.url = clean_url(value.get("url"))
        segment.key = segment_key_from_request(value)
        segment._ignore_err = bool(value.get("ignoreError", False))
        segment._hitomi_native_source_index = source_index
        result = alter(segment, cw)
        if not result:
            continue
        if isinstance(result, (str, bytes, Segment, dict)):
            result = [result]
        else:
            result = list(result)
        for item in result:
            payload = altered_segment_payload(item, source_index, stream)
            if payload is not None:
                altered.append(payload)

    return {
        "ok": True,
        "encoding": encoding,
        "sha256": hashlib.sha256(raw).hexdigest(),
        "alteredSegments": altered,
    }


def hook_state(context):
    context = dict(context or {})
    source_url = clean_url(context.get("sourceURL"))
    cw = DummyCW(source_url)
    cw.title = string_value(context.get("title")) or ""
    cw.outputPath = string_value(context.get("outputPath")) or ""
    cw.dir = (os.path.dirname(cw.outputPath)
              if cw.outputPath and os.path.isfile(cw.outputPath)
              else cw.outputPath)
    cw._initial_dir = cw.dir
    cw._initial_url = source_url
    cw.names = [string_value(value) for value in context.get("names", []) if string_value(value)]
    cw.imgs = [value.get("url") for value in context.get("assets", []) if value.get("url")]
    cw.metadata = normalized_headers(context.get("metadata"))
    cw.status = string_value(context.get("status")) or "ready"
    cw.valid = bool(context.get("valid", True))
    cw.total = int(context.get("total") or 0)
    cw.completed = int(context.get("completed") or 0)
    cw.error = string_value(context.get("errorMessage"))

    downloader = Downloader(source_url, cw)
    downloader._title = cw.title or None
    downloader.artist = string_value(context.get("artist"))
    downloader.type = string_value(context.get("type"))
    downloader.metadata = dict(cw.metadata)
    downloader.single = bool(context.get("single", False))
    downloader._hook_assets = list(context.get("assets", []))
    downloader.urls = []
    downloader.filenames = {}
    for asset in downloader._hook_assets:
        url = clean_url(asset.get("url"))
        if not url:
            continue
        downloader.urls.append(url)
        filename = string_value(asset.get("filename"))
        if filename:
            downloader.filenames[url] = filename
    cw.downloader = downloader
    return cw, downloader


def hook_context_from_state(cw, downloader, original_context):
    original_context = dict(original_context or {})
    original_assets = list(original_context.get("assets", []))
    assets = []
    for index, item in enumerate(list(getattr(downloader, "urls", None) or [])):
        original = original_assets[index] if index < len(original_assets) else {}
        resolved = resolve_asset(
            downloader,
            item,
            index,
            string_value(original.get("referer")),
            string_value(original.get("userAgent")),
            normalized_headers(original.get("headers")),
        )
        original_metadata = normalized_headers(original.get("metadata"))
        original_metadata.update(normalized_headers(resolved.get("metadata")))
        resolved["metadata"] = original_metadata
        assets.append(resolved)

    source_url = clean_url(getattr(downloader, "url", None))
    cw_url = clean_url(getattr(cw, "url", None))
    if cw_url and cw_url != getattr(cw, "_initial_url", None) and source_url == getattr(cw, "_initial_url", None):
        source_url = cw_url

    output_path = string_value(getattr(cw, "outputPath", None)) or ""
    cw_dir = string_value(getattr(cw, "dir", None)) or ""
    if cw_dir and cw_dir != getattr(cw, "_initial_dir", None):
        output_path = cw_dir
    elif not output_path:
        output_path = cw_dir

    title = string_value(getattr(downloader, "title", None)) or ""
    cw_title = string_value(getattr(cw, "title", None)) or ""
    if cw_title and cw_title != original_context.get("title") and title == original_context.get("title"):
        title = cw_title

    metadata = normalized_headers(getattr(downloader, "metadata", None))
    metadata.update(normalized_headers(getattr(cw, "metadata", None)))
    return {
        "sourceURL": source_url,
        "title": title,
        "artist": string_value(getattr(downloader, "artist", None)),
        "type": string_value(getattr(downloader, "type", None)),
        "status": string_value(getattr(cw, "status", None)) or "",
        "outputPath": output_path,
        "metadata": metadata,
        "assets": assets,
        "names": [string_value(value) for value in getattr(cw, "names", []) if string_value(value)],
        "total": int(getattr(cw, "total", 0) or len(assets)),
        "completed": int(getattr(cw, "completed", 0) or 0),
        "errorMessage": string_value(getattr(cw, "error", None)),
        "valid": bool(getattr(cw, "valid", True)),
        "single": bool(getattr(downloader, "single", False)),
    }


def apply_format_hooks(context, selected_names):
    assets = list(context.get("assets", []))
    base_metadata = normalized_headers(context.get("metadata"))
    for name in selected_names:
        function = REGISTERED_HOOKS["format"].get(name)
        if function is None:
            continue
        for index, asset in enumerate(assets):
            filename = string_value(asset.get("filename")) or ""
            extension = pathlib.PurePosixPath(filename).suffix
            data = dict(base_metadata)
            data.update(normalized_headers(asset.get("metadata")))
            data.update({
                "title": string_value(context.get("title")) or "",
                "artist": string_value(context.get("artist")) or "",
                "type": string_value(context.get("type")) or name,
                "id": data.get("id") or str(index + 1),
                "index": str(index + 1),
                "filename": filename,
                "url": string_value(asset.get("url")) or "",
            })
            formatted = function(data, extension)
            if formatted is not None and string_value(formatted):
                asset["filename"] = string_value(formatted)
    context["assets"] = assets
    return context


def run_hook(request):
    _module, encoding, raw = load_script(request["scriptPath"])
    event = request.get("hookEvent")
    if event not in HOOK_EVENTS:
        raise ValueError("Unknown hook event: {}".format(event))
    available = REGISTERED_HOOKS[event]
    selected_names = request.get("hookNames") or list(available)
    missing = [name for name in selected_names if name not in available]
    if missing:
        raise ValueError("Hook is no longer registered: {}".format(", ".join(missing)))

    context = dict(request.get("hookContext") or {})
    if event == "format":
        context = apply_format_hooks(context, selected_names)
    else:
        cw, downloader = hook_state(context)
        for name in selected_names:
            available[name](cw)
        context = hook_context_from_state(cw, downloader, context)

    return {
        "ok": True,
        "encoding": encoding,
        "sha256": hashlib.sha256(raw).hexdigest(),
        "downloaders": [descriptor(value) for value in REGISTERED_DOWNLOADERS],
        "hooks": hook_descriptors(),
        "themes": theme_descriptors(),
        "hookContext": context,
    }


def exception_details(error):
    values = {}
    for name in ("method", "url", "cookie", "w", "h", "fail", "status", "feature"):
        value = getattr(error, name, None)
        if value is not None:
            values[name] = value
    return values


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--request", required=True)
    args = parser.parse_args()
    captured = io.StringIO()
    with contextlib.redirect_stdout(captured), contextlib.redirect_stderr(captured):
        try:
            with io.open(args.request, "r", encoding="utf-8") as handle:
                request = json.load(handle)
            action = request.get("action")
            if action == "inspect":
                payload = run_inspect(request)
            elif action == "resolve":
                payload = run_resolve(request)
            elif action == "stream_decorate":
                payload = run_stream_decorate(request)
            elif action == "stream_alter":
                payload = run_stream_alter(request)
            elif action == "hook":
                payload = run_hook(request)
            else:
                raise ValueError("Unknown action: {}".format(action))
        except Exception as error:
            payload = {
                "ok": False,
                "error": "{}: {}".format(type(error).__name__, error),
                "errorKind": type(error).__name__,
                "errorDetails": exception_details(error),
                "traceback": traceback.format_exc(limit=20),
            }
    logs = captured.getvalue()
    if logs:
        payload["logs"] = logs[-65536:]
    emit(payload)


if __name__ == "__main__":
    main()
