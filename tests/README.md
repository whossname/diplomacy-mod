# Diplomacy Mod — Unit Tests

These tests exercise the server-side game logic in
[`LuaRules/Gadgets/api_diplomacy.lua`](../LuaRules/Gadgets/api_diplomacy.lua)
without needing to launch Beyond All Reason / Spring.

## How it works

The gadget relies entirely on the Spring/Recoil engine's global API
(`Spring.*`, `gadgetHandler`, `UnitDefs`) and keeps its state (`teamStates`,
`teamCommanders`, `pendingProposals`) in file-local variables with no public
accessors. To test it in isolation, [`mock_env.lua`](./mock_env.lua):

- Mocks just the subset of the `Spring` API the gadget calls
  (`GetTeamList`, `GetTeamInfo`, `SetAlly`, `KillTeam`, `TransferUnit`,
  `GetTeamUnits`, `GetUnitDefID`, chat/message functions, etc.).
- Loads a **fresh copy** of the gadget chunk per test into a sandboxed
  environment table, so no state leaks between tests.
- Records every call made to the mocked Spring functions (alliances,
  eliminations, unit transfers, chat messages) so tests can assert on
  observable *behavior* — exactly what another player would see happen in a
  real match — rather than reaching into gadget internals.
- Simulates the engine firing the synced `UnitGiven` call-in whenever a unit
  is transferred, since the real engine does this automatically.

Tests are written with a tiny hand-rolled `describe`/`it`/`expect` framework
([`test_framework.lua`](./test_framework.lua)) because no Lua package
manager (busted, luaunit, etc.) is available in this environment.

Since there's no standalone `lua` binary installed here either, tests run
through [`lupa`](https://pypi.org/project/lupa/), which embeds a Lua runtime
directly in Python.

## Running the tests

```bash
pip install lupa   # first time only
python3 tests/run_tests.py
```

A non-zero exit code means at least one test failed.

## What's covered

- Independent teams are eliminated when their last Commander dies.
- Partnership formation and alliance side-effects.
- Partnership collapse into King/Vassal when a partner loses their last
  Commander.
- Fealty: automatic Commander seizure, and a Vassal regaining Independence
  when they get a new Commander.
- **Bug fix:** a King who loses their last Vassal becomes Independent again
  (previously they stayed stuck as a vassal-less "King" forever).
- **Bug fix:** a King who gifts their last Commander to one of their own
  Vassals has the relationship reverse (the Vassal becomes the new King,
  inheriting any other Vassals) instead of the whole kingdom being
  eliminated.

Each bug-fix test was verified to fail against the pre-fix gadget code and
pass against the fixed code.

## Not covered

`LuaUI/gui_diplomacy.lua` (the menu widget) is presentation-only — it just
sends `/diplomacy ...` chat commands and renders buttons — so it isn't unit
tested here. If it grows real logic worth testing, apply the same
mocking approach to the `widget` table and `gl`/`Spring` UI calls it uses.
