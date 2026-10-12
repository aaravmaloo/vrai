import os

app = defines["app"]
name = os.path.basename(app)

format = "UDZO"
compression_level = 9
filesystem = "HFS+"
files = [app]
symlinks = {"Applications": "/Applications"}
hide_extensions = [name]
icon = os.path.join(app, "Contents", "Resources", "AppIcon.icns")
background = defines["background"]
window_rect = ((200, 160), (640, 428))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False
include_icon_view_settings = True
icon_size = 128
text_size = 13
arrange_by = None
icon_locations = {name: (170, 148), "Applications": (470, 148)}
