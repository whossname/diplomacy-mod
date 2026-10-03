# uat-scripts

| script | what it does |
|---|---|
| `game start\|stop\|restart\|reload` | launch (you + 2 AIs, waits until in-game, cheats on) / kill / both / hot-reload widgets. Gadget or new-file changes need `restart`. |
| `say N <command>` | run a diplomacy command as team N (0 = you, 1 = Alice, 2 = Bob), e.g. `say 2 partner 1`, `say 1 accept 0`. Prints the resulting log lines. |
| `say --raw "<chat line>"` | type any chat/slash line into the game |
| `logs [-f] [-a]` | Lua errors + diplomacy lines from the infolog; `-f` follow, `-a` everything |
| `uat` | full end-to-end scenario with pass/fail (restarts the game) |

`say` types into the game window over X11 (needs `python-xlib`, `wmctrl`). `/diplomacy as <team> ...` is a
cheat-gated test hook in the gadget; unit tests live in `../tests/` (`python3 tests/run_tests.py`).
