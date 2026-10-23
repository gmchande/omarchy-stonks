-- Gives the tophat's nested Hyprland the owner's animations: it runs
-- Omarchy's look'n'feel files, the defaults and then the owner's own, with
-- only their curves, animations, and `animations` settings reaching the
-- compositor. Without it the session has Hyprland's own animations, and a
-- popup fades in over about 700 ms, not Omarchy's 179. The rest of those
-- files (gaps, borders, rounding) the session takes from the host's live
-- values, so only these are read here.
--
-- Called from nested.lua as: loadfile(this)(DEFAULTS, OWNERS). A defaults
-- file that won't load is an error, so the session never starts on the
-- wrong motion; the owner's file may be missing.
local defaults, owners = ...

local only_animations = setmetatable({
  curve = hl.curve,
  animation = hl.animation,
  config = function(settings)
    if settings.animations then hl.config({ animations = settings.animations }) end
  end,
}, { __index = function() return function() end end })
local function include() error("a look'n'feel file that includes another can't be filtered to its animations") end
local env = setmetatable({ hl = only_animations, dofile = include, loadfile = include, require = include }, { __index = _G })

local function run(path, required)
  local file = io.open(path, "r")
  if not file then
    if required then error("cannot read " .. path) end
    return
  end
  local source = file:read("a")
  file:close()
  assert(load(source, "@" .. path, "t", env))()
end

run(defaults, true)
run(owners, false)
