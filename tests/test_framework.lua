-- Minimal describe/it/assert test framework.
-- No external dependencies are available in the BAR/Spring Lua sandbox,
-- so this is a small hand-rolled runner rather than busted/luaunit.

local framework = {}

local suites = {}
local currentSuite = nil

function framework.describe(name, fn)
    currentSuite = { name = name, tests = {} }
    table.insert(suites, currentSuite)
    fn()
    currentSuite = nil
end

function framework.it(name, fn)
    assert(currentSuite, "it() must be called inside describe()")
    table.insert(currentSuite.tests, { name = name, fn = fn })
end

local function deepEquals(a, b)
    if a == b then return true end
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    for k, v in pairs(a) do
        if not deepEquals(v, b[k]) then return false end
    end
    for k in pairs(b) do
        if a[k] == nil then return false end
    end
    return true
end

framework.expect = {}

local function newExpectation(actual)
    local self = {}
    function self.toBe(expected)
        if actual ~= expected then
            error(("expected %s to be %s"):format(tostring(actual), tostring(expected)), 2)
        end
    end
    function self.toEqual(expected)
        if not deepEquals(actual, expected) then
            error(("expected value to deep-equal %s, got %s"):format(tostring(expected), tostring(actual)), 2)
        end
    end
    function self.toBeNil()
        if actual ~= nil then
            error(("expected nil, got %s"):format(tostring(actual)), 2)
        end
    end
    function self.toContain(expected)
        if type(actual) ~= "table" then
            error("toContain() requires a table", 2)
        end
        for _, v in pairs(actual) do
            if v == expected then return end
        end
        error(("expected table to contain %s"):format(tostring(expected)), 2)
    end
    function self.toHaveLength(n)
        if #actual ~= n then
            error(("expected length %d, got %d"):format(n, #actual), 2)
        end
    end
    return self
end

function framework.expectValue(actual)
    return newExpectation(actual)
end

function framework.run()
    local totalPass, totalFail = 0, 0
    for _, suite in ipairs(suites) do
        print("\n" .. suite.name)
        for _, test in ipairs(suite.tests) do
            local ok, err = pcall(test.fn)
            if ok then
                totalPass = totalPass + 1
                print("  [PASS] " .. test.name)
            else
                totalFail = totalFail + 1
                print("  [FAIL] " .. test.name)
                print("         " .. tostring(err))
            end
        end
    end
    print(("\n%d passed, %d failed"):format(totalPass, totalFail))
    return totalFail == 0
end

return framework
