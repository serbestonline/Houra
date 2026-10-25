# dmgbuild ayarları — build.sh --dmg tarafından çağrılır:
#   uvx dmgbuild -s scripts/dmg_settings.py -D app=... -D background=... -D volume_icon=... "Houra" out.dmg
# Simge konumları scripts/make_dmg_background.swift içindeki ok ile eşleşmelidir.
import os.path

app_path = defines["app"]  # noqa: F821 — dmgbuild tarafından sağlanır
app_name = os.path.basename(app_path)

format = "UDZO"
filesystem = "HFS+"
files = [app_path]
symlinks = {"Applications": "/Applications"}
hide_extensions = [app_name]
icon = defines["volume_icon"]  # noqa: F821
background = defines["background"]  # noqa: F821

window_rect = ((200, 120), (600, 428))  # 400 içerik + başlık çubuğu
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False
icon_size = 128
text_size = 13
icon_locations = {
    app_name: (150, 190),
    "Applications": (450, 190),
}
