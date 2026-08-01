fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'gangs'
author 'DieselJones21'
description 'Original territory / organization gang resource inspired by popular FiveM gang systems'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'locales/en.lua',
    'shared/*.lua',
}

client_scripts {
    'bridge/client.lua',
    'client/*.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'bridge/server.lua',
    'server/*.lua',
}

ui_page 'web/index.html'

files {
    'web/index.html',
    'web/style.css',
    'web/app.js',
    'web/logo.html',
}

dependencies {
    'oxmysql',
    'ox_lib',
}
