fx_version 'cerulean'

game 'gta5'

name 'Hawes Weather Control'
author 'Hawes'
description 'Weather control menu with ACE/Badger Discord permissions.'
version '1.0.0'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
    'data/schedules.json'
}

shared_script 'config.lua'

client_script 'client/main.lua'

server_script 'server/main.lua'
