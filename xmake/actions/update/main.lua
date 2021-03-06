--!A cross-platform build utility based on Lua
--
-- Licensed to the Apache Software Foundation (ASF) under one
-- or more contributor license agreements.  See the NOTICE file
-- distributed with this work for additional information
-- regarding copyright ownership.  The ASF licenses this file
-- to you under the Apache License, Version 2.0 (the
-- "License"); you may not use this file except in compliance
-- with the License.  You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
-- 
-- Copyright (C) 2015 - 2018, TBOOX Open Source Group.
--
-- @author      ruki
-- @file        main.lua
--

-- imports
import("core.base.semver")
import("core.base.option")
import("core.base.task")
import("net.http")
import("devel.git")
import("net.fasturl")
import("core.base.privilege")
import("privilege.sudo")
import("actions.require.impl.environment", {rootdir = os.programdir()})

-- run cmd with privilege
function _sudo(cmd)

    -- attempt to install directly
    try
    {
        function ()
            os.vrun(cmd)
            return true
        end,

        catch
        {
            -- failed or not permission? request administrator permission and run it again
            function (errors)

                -- try get privilege
                if privilege.get() then
                    local ok = try
                    {
                        function ()
                            os.vrun(cmd)
                            return true
                        end
                    }

                    -- release privilege
                    privilege.store()

                    -- ok?
                    if ok then 
                        return true 
                    end
                end

                -- show tips
                cprint("\r${bright red}error: ${default red}run `%s` failed, may permission denied!", cmd)

                -- continue to install with administrator permission?
                if sudo.has() then

                    -- get confirm
                    local confirm = option.get("yes")
                    if confirm == nil then

                        -- show tips
                        cprint("\r${bright yellow}note: ${default yellow}try continue to run `%s` with administrator permission again?", cmd)
                        cprint("\rplease input: y (y/n)")

                        -- get answer
                        io.flush()
                        local answer = io.read()
                        if answer == 'y' or answer == '' then
                            confirm = true
                        end
                    end

                    -- confirm to install?
                    if confirm then
                        sudo.vrun(cmd)
                        return true
                    end
                end
            end
        }
    }
end

-- do uninstall
function _uninstall()
    if is_host("windows") then
        local uninstaller = path.join(os.programdir(), "uninstall.exe")
        if os.isfile(uninstaller) then
            -- UAC on win7
            if winos:version():gt("winxp") then
                local proc = process.openv("cscript", {path.join(os.programdir(), "scripts", "sudo.vbs"), uninstaller})
                if proc ~= nil then
                    process.close(proc)
                end
            else
                local proc = process.open(uninstaller)
                if proc ~= nil then
                    process.close(proc)
                end
            end
        else
            raise("the uninstaller(%s) not found!", uninstaller)
        end
    else
        if os.programdir():startswith("/usr/") then
            _sudo("rm -rf " .. os.programdir())
            if os.isfile("/usr/local/bin/xmake") then
                _sudo("rm -f /usr/local/bin/xmake")
            end
            if os.isfile("/usr/bin/xmake") then
                _sudo("rm -f /usr/bin/xmake")
            end
        else
            os.rm(os.programdir())
            os.rm(os.programfile())
            os.rm("~/.local/bin/xmake")
        end
    end
end

-- do install
function _install(sourcedir, version)

    -- the install task
    local install_task = function ()

        -- trace
        cprintf("\r${yellow}  => ${clear}installing to %s ..  ", os.programdir())
        local ok = try 
        {
            function ()

                -- install it 
                os.cd(sourcedir)
                if is_host("windows") then
                    local installer = "xmake-" .. version .. ".exe"
                    if os.isfile(installer) then
                        -- UAC on win7
                        if winos:version():gt("winxp") then
                            local proc = process.openv("cscript", {path.join(os.programdir(), "scripts", "sudo.vbs"), installer})
                            if proc ~= nil then
                                process.close(proc)
                            end
                        else
                            local proc = process.open(installer)
                            if proc ~= nil then
                                process.close(proc)
                            end
                        end
                    else
                        raise("the installer(%s) not found!", installer)
                    end
                else
                    if os.programdir():startswith("/usr/") then
                        os.vrun("make build")
                        _sudo("make install") 
                    else
                        os.vrun("./scripts/get.sh __local__")
                    end
                end
                return true
            end,
            catch 
            {
                function (errors)
                    vprint(errors)
                end
            }
        }
            
        -- trace
        if ok then
            cprint("\r${yellow}  => ${clear}install to %s .. ${green}ok", os.programdir())
        else
            raise("install failed!")
        end
    end

    -- do install 
    if option.get("verbose") then
        install_task()
    else
        process.asyncrun(install_task)
    end

    -- show version
    if not is_host("windows") then
        os.exec("xmake --version")
    end
end

-- main
function main()

    -- only uninstall it
    if option.get("uninstall") then

        -- do uninstall
        _uninstall()

        -- trace
        cprint("${bright}uninstall ok!")
        return 
    end

    -- enter environment 
    environment.enter()

    -- sort main urls
    local mainurls = {"https://github.com/tboox/xmake.git", "https://gitlab.com/tboox/xmake.git", "https://gitee.com/tboox/xmake.git"}
    fasturl.add(mainurls)
    mainurls = fasturl.sort(mainurls)

    -- get version
    local version = nil
    for _, url in ipairs(mainurls) do
        local tags, branches = git.refs(url)
        if tags or branches then
            version = semver.select(option.get("xmakever") or "lastest", tags or {}, tags or {}, branches or {})
            break
        end
    end
    if not version then
        version = "master"
    end

    -- has been installed?
    if os.xmakever():eq(version) then
        cprint("${bright}xmake %s has been installed!", version)
        return
    end

    -- cannot support to update dev/master on windows
    if is_host("windows") and not version:find('.', 1, true) then
        raise("not support to update %s on windows!", version)
    else
        mainurls = {format("https://github.com/tboox/xmake/releases/download/%s/xmake-%s.exe", version, version)}
    end

    -- trace
    print("update version: %s ..", version)

    -- the download task
    local sourcedir = path.join(os.tmpdir(), "xmakesrc", version)
    local download_task = function ()
        for idx, url in ipairs(mainurls) do
            cprintf("\r${yellow}  => ${clear}clone %s ..  ", url)
            local ok = try
            {
                function ()
                    os.tryrm(sourcedir)
                    if not git.checkurl(url) then
                        os.mkdir(sourcedir)
                        http.download(url, path.join(sourcedir, path.filename(url)))
                    else
                        if version:find('.', 1, true) then
                            git.clone(url, {outputdir = sourcedir})
                            git.checkout(version, {repodir = sourcedir})
                        else
                            git.clone(url, {depth = 1, branch = version, outputdir = sourcedir})
                        end
                    end
                    return true
                end,
                catch 
                {
                    function (errors)
                        vprint(errors)
                    end
                }
            }
            if ok then
                cprint("\r${yellow}  => ${clear}download %s .. ${green}ok", url)
                break
            else
                cprint("\r${yellow}  => ${clear}download %s .. ${red}failed", url)
            end
            if not ok and idx == #mainurls then
                raise("download failed!")
            end
        end
    end

    -- do download 
    if option.get("verbose") then
        download_task()
    else
        process.asyncrun(download_task)
    end

    -- leave environment 
    environment.leave()

    -- do install
    _install(sourcedir, version)
end

