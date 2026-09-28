local shell = require('shell')
local scripts = {
    'setup.lua',
    'action.lua',
    'database.lua',
    'events.lua',
    'gps.lua',
    'scanner.lua',
    'config.lua',
    'autoStat.lua',
    'autoTier.lua',
    'autoSpread.lua',
    'autoBreed.lua',
    'breeding.lua',
    'breedpolicy.lua',
    'crops.lua',
    'uninstall.lua'
}

-- UNINSTALL
for i=1, #scripts do
    shell.execute(string.format('rm %s', scripts[i]))
    print(string.format('Uninstalled %s', scripts[i]))
end