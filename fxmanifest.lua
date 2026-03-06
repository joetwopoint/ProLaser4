------------------------------
fx_version 'cerulean'

games { 'gta5' }
lua54 'on'

author 'Trevor Barns'
description 'Lidar Resource.'

version '1.1.1'						-- Readonly version of currently installed version.
------------------------------
ui_page('UI/html/index.html')

files {
	'speedlimits.json',
	'UI/html/index.html',
	'UI/html/fonts/**.ttf',
	'UI/html/**.png',
	'UI/html/**.jpg',
	'UI/html/lidar.js',
	'UI/html/**.css',
	'UI/html/sounds/*.ogg',
	'UI/weapons_dlc_bb.png',
	'metas/*.meta',
}

data_file 'WEAPON_METADATA_FILE' 'metas/weaponarchetypes.meta'
data_file 'WEAPON_ANIMATIONS_FILE' 'metas/weaponanimations.meta'
data_file 'CONTENT_UNLOCKING_META_FILE' 'metas/contentunlocks.meta'
data_file 'PED_PERSONALITY_FILE' 'metas/pedpersonality.meta'
data_file 'WEAPONINFO_FILE' 'metas/weapons.meta'

client_scripts {
	'UI/cl_*.lua',
	'UTIL/cl_*.lua',
}

server_scripts {
	'UTIL/sv_*.lua',
	'UTIL/semver.lua'
}

shared_scripts {
	'config.lua',
}
