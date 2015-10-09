local Lfs      = require "lfs"
local Lustache = require "lustache"
local Colors   = require 'ansicolors'
local Reporter = require "luacov.reporter"

local prefix    = os.getenv "COSY_PREFIX"

local string_mt = getmetatable ""

function string_mt.__mod (pattern, variables)
  return Lustache:render (pattern, variables)
end

function _G.string.split (s, delimiter)
  local result = {}
  for part in s:gmatch ("[^" .. delimiter .. "]+") do
    result [#result+1] = part
  end
  return result
end

-- Compute path:
local main = package.searchpath ("cosy.check", package.path)
if main:sub (1, 2) == "./" then
  main = Lfs.currentdir () .. "/" .. main:sub (3)
end
main = main:gsub ("/check/init.lua", "")

local status = true

status = os.execute ([[{{{luacheck}}} {{{path}}}/*/*.lua]] % {
  luacheck = prefix .. "/local/cosy/5.1/bin/luacheck",
  path     = main,
}) and status

for module in Lfs.dir (main) do
  local path = main .. "/" .. module
  if  module ~= "." and module ~= ".."
  and Lfs.attributes (path, "mode") == "directory" then
    if Lfs.attributes (path .. "/test.lua", "mode") == "file" then
      status = os.execute ([[{{{lua}}} {{{path}}}/test.lua --verbose]] % {
        lua  = prefix .. "/local/cosy/5.1/bin/luajit",
        path = path,
      }) and status
      for _, version in ipairs {
        "5.2",
      } do
        status = os.execute ([[
          export LUA_PATH="{{{luapath}}}"
          export LUA_CPATH="{{{luacpath}}}"
          {{{lua}}} {{{path}}}/test.lua --verbose --coverage --output=TAP >> {{{output}}}
        ]] % {
          lua      = "lua" .. version,
          path     = path:gsub ("5%.1", version),
          output   = "tap.txt",
          luapath  = package.path :gsub ("5%.1", version),
          luacpath = package.cpath:gsub ("5%.1", version),
        }) and status
      end
    end
  end
end

print ()

do
  Reporter.report ()

  local report = {}
  Lfs.mkdir ("coverage")

  local file      = "luacov.report.out"
  local output    = nil
  local in_header = false
  local current
  for line in io.lines (file) do
    if     not in_header
    and    line:find ("==============================================================================") == 1
    then
      in_header = true
      if output then
        output:close ()
        output = nil
      end
    elseif in_header
    and    line:find ("==============================================================================") == 1
    then
      in_header = false
    elseif in_header
    then
      current = line
      if current ~= "Summary" then
        local filename = line:match (prefix .. "/local/cosy/[^/]+/share/lua/[^/]+/(.*)")
        if filename and filename:match "^cosy" then
          local parts = {}
          for part in filename:gmatch "[^/]+" do
            parts [#parts+1] = part
            if not part:match ".lua$" then
              Lfs.mkdir ("coverage/" .. table.concat (parts, "/"))
            end
          end
          output = io.open ("coverage/" .. table.concat (parts, "/"), "w")
        end
      end
    elseif output then
      output:write (line .. "\n")
    else
      local filename = line:match (prefix .. "/local/cosy/[^/]+/share/lua/[^/]+/(.*)")
      if filename and filename:match "^cosy" then
        line = line:gsub ("\t", " ")
        local parts = line:split " "
        if #parts == 4 and parts [4] ~= "" then
          report [filename] = parts [3]
        end
      end
    end
  end
  if output then
    output:close ()
  end

  local max_size = 0
  for k, _ in pairs (report) do
    max_size = math.max (max_size, #k)
  end
  max_size = max_size + 3

  local keys = {}
  for k, _ in pairs (report) do
    keys [#keys + 1] = k
  end
  table.sort (keys)

  for i = 1, #keys do
    local k = keys   [i]
    local v = report [k]
    if v == "100.00%" then
      status = Colors("%{bright green}Full")
    else
      status = Colors("%{bright red}" .. v)
    end
    local line = k
    for _ = #k, max_size do
      line = line .. " "
    end
    line = line .. status
    print ("Coverage " .. line)
  end
end

os.exit (status and 0 or 1)