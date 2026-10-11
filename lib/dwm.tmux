# Loaded by the executable dwm.tmux entrypoint after registering its commands.
set -gqo @dwm-enabled on
set -gqo @dwm-kill-last off
set -gqo @dwm-step 3
set -gqo @dwm-bindings meta

# A dedicated key table is available for custom bindings, for example:
# bind D switch-client -T dwm
bind -T dwm n dwm-newpane
bind -T dwm w dwm-newpanecurdir
bind -T dwm c dwm-killpane
bind -T dwm j dwm-nextpane
bind -T dwm k dwm-prevpane
bind -T dwm < dwm-rotateccw
bind -T dwm > dwm-rotatecw
bind -T dwm Enter dwm-promote
bind -T dwm t dwm-layouttile
bind -T dwm Space dwm-toggle-zoom
bind -T dwm h dwm-decmfact
bind -T dwm l dwm-incmfact
bind -T dwm Escape switch-client -T root
