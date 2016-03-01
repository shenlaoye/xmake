--!The Automatic Cross-platform Build Tool
-- 
-- XMake is free software; you can redistribute it and/or modify
-- it under the terms of the GNU Lesser General Public License as published by
-- the Free Software Foundation; either version 2.1 of the License, or
-- (at your option) any later version.
-- 
-- XMake is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU Lesser General Public License for more details.
-- 
-- You should have received a copy of the GNU Lesser General Public License
-- along with XMake; 
-- If not, see <a href="http://www.gnu.org/licenses/"> http://www.gnu.org/licenses/</a>
-- 
-- Copyright (C) 2015 - 2016, ruki All rights reserved.
--
-- @author      ruki
-- @file        action.lua
--

-- define module: action
local action = action or {}

-- load modules
local os        = require("base/os")
local path      = require("base/path")
local utils     = require("base/utils")
local option    = require("base/option")
local global    = require("base/global")
local config    = require("base/config")
local project   = require("base/project")
local platform  = require("base/platform")

-- load the given action
function action._load(name)
    
    -- load the given action
    return require("action/" .. name)
end

-- load the project file
function action._load_project()

    -- the options
    local options = option.options()
    assert(options)

    -- enter the project directory
    if not os.cd(xmake._PROJECT_DIR) then
        -- error
        return string.format("not found project: %s!", xmake._PROJECT_DIR)
    end

    -- check the project file
    if not os.isfile(xmake._PROJECT_FILE) then
        return string.format("not found the project file: %s", xmake._PROJECT_FILE)
    end

    -- init the build directory
    if options.buildir and path.is_absolute(options.buildir) then
        options.buildir = path.relative(options.buildir, xmake._PROJECT_DIR)
    end

    -- xmake config or marked as "reconfig"?
    if option.task() == "config" or config._RECONFIG then

        -- probe the current project 
        project.probe()

        -- clear up the configure
        config.clearup()

    end

    -- load the project 
    return project.load()
end

-- done the given action
function action.done(name)
    
    -- load the given action
    local _action = action._load(name)
    if not _action then return false end

    -- load the global configure first
    if _action.need("global") then global.load() end

    -- load the project configure
    if _action.need("config") then
        local errors = config.load()
        if errors then
            -- error
            utils.error(errors)
            return false
        end
    end

    -- probe the platform
    if _action.need("platform") and (option.task() == "config" or config._RECONFIG) then
        if not platform.probe(false) then
            return false
        end
    end

    -- make the platform configure
    if _action.need("platform") and not platform.make() then
        utils.error("make platform configure: %s failed!", config.get("plat"))
        return false
    end

    -- load the project file
    if _action.need("project") then
        local errors = action._load_project()
        if errors then
            -- error
            utils.error(errors)
            return false
        end
    end

    -- reconfig it first if marked as "reconfig"
    if _action.need("config") and config._RECONFIG then

        -- config it
        local _action_config = action._load("config")
        if not _action_config or not _action_config.done() then
            -- error
            utils.error("reconfig failed for the changed host!")
            return false
        end
    end

    -- done the given action
    return _action.done()
end


-- return module: action
return action