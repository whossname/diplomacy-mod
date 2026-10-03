# scripts

| script | what it does |
|---|---|
| `run.sh` / `stop.sh` / `restart.sh` | start / kill / restart the game (restart for new files) |
| `reload.sh` | hot-reload widgets + gadgets after code edits |
| `say.sh "/diplo info"` | type chat/slash commands into the game window (X11) |
| `log.sh [all]` | follow infolog filtered to diplomacy lines + errors |
| `errors.sh` | list Lua errors from the last run |
| `test.sh` | offline unit tests |

`say.py` needs `pip install python-xlib` and `wmctrl`.
