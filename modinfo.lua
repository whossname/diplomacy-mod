local modinfo = {
    name = "Diplomacy Mod",
    shortname = "dipmod",
    version = "1.0",
    mutator = {
        require = {
            -- This tells the engine to load BAR first, then your code on top
            "Beyond All Reason", 
        },
    },
}
return modinfo

