"""Run the bot's Lua files inside Python tests (lupa; Lua 5.3 like OpenComputers)."""
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent


def runtime(stubs=False):
    """A fresh Lua runtime that can require() the bot's files.

    stubs=True also loads tests/oc_stubs.lua, so files that need OpenComputers
    components (action.lua, autoBreed.lua) can load.
    """
    impl = None
    for name in ("lua53", "lua54"):
        try:
            impl = __import__("lupa." + name, fromlist=["LuaRuntime"])
            break
        except ImportError:
            continue
    if impl is None:
        raise RuntimeError("lupa with Lua 5.3 or 5.4 is required: python -m pip install lupa")
    lua = impl.LuaRuntime(unpack_returned_tuples=True)
    lua.execute("package.path = '%s/?.lua;' .. package.path" % REPO.as_posix())
    if stubs:
        lua.execute((REPO / "tests" / "oc_stubs.lua").read_text(encoding="utf-8"))
    return lua
