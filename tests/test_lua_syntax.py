import unittest

from lua_env import REPO, runtime


class LuaSyntaxTest(unittest.TestCase):
    def test_every_lua_file_compiles(self):
        lua = runtime()
        compile_error = lua.eval("function(src, name) local _, err = load(src, '=' .. name) return err end")
        for path in sorted(REPO.glob("*.lua")):
            with self.subTest(file=path.name):
                self.assertIsNone(compile_error(path.read_text(encoding="utf-8"), path.name))

    def test_config_has_autobreed_settings(self):
        config = runtime().eval("require('config')")
        self.assertEqual(list(config['seedContainerPos'].values()), [-3, 0])
        self.assertIsNone(config['breedTarget'])


if __name__ == "__main__":
    unittest.main()
