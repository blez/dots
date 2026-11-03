--- @since 25.5.31
-- Keys of yazi as a file dialog. termfilechooser's yazi-wrapper.sh
-- (~/.config/xdg-desktop-portal-termfilechooser) starts yazi with
-- TERMFILECHOOSER_MODE set (save, dir or open) and TERMFILECHOOSER_CANCEL
-- (a flag file to create when cancelling), plus TERMFILECHOOSER_SAVE_AS
-- (where a typed name goes) and TERMFILECHOOSER_NAME (the suggested name)
-- when saving. Outside a dialog every key keeps its usual meaning.
--
--   plugin chooser -- cancel --fallback=CMD   q, Esc: close the dialog with
--                                      nothing chosen (Esc first leaves visual
--                                      mode or clears a selection, like it
--                                      always does); outside a dialog run CMD
--   plugin chooser -- confirm          Ctrl+S: save here / choose this folder
--   plugin chooser -- name             a: save under a typed name; a name
--                                      ending in / creates that folder instead
--
-- require("chooser"):setup() in init.lua makes a save dialog's placeholder
-- (the file to be saved, see the wrapper) follow the current folder.

local cwd = ya.sync(function()
	return tostring(cx.active.current.cwd)
end)

-- Something Esc would normally act on: visual mode or selected files.
local has_escapable = ya.sync(function()
	if cx.active.mode.is_visual then
		return true
	end
	for _ in pairs(cx.active.selected) do
		return true
	end
	return false
end)

local function in_dialog()
	local mode = os.getenv("TERMFILECHOOSER_MODE")
	return mode ~= nil and mode ~= ""
end

local function notify(content, level)
	ya.notify { title = "File dialog", content = content, level = level or "error", timeout = 5 }
end

-- Tell the wrapper this is a cancel, and quit normally so it still learns the
-- folder yazi ended in (to clean up a placeholder moved there).
local function cancel()
	local flag = os.getenv("TERMFILECHOOSER_CANCEL")
	if flag and flag ~= "" then
		fs.write(Url(flag), "cancel\n")
	end
	ya.emit("quit", {})
end

local function save_as()
	local result = os.getenv("TERMFILECHOOSER_SAVE_AS")
	if not result or result == "" then
		return ya.emit("create", {})
	end

	-- Empty prompt (typing replaces the name); the suggested one is the hint.
	local suggested = os.getenv("TERMFILECHOOSER_NAME") or ""
	local value, event = ya.input {
		title = suggested ~= "" and "Save as (was " .. suggested .. "):" or "Save as:",
		pos = { "center", w = 60 },
	}
	if event ~= 1 or not value or value == "" then
		return
	end

	-- A path is taken as given; a bare name is in the current folder.
	local path
	if value:sub(1, 1) == "/" then
		path = value
	elseif value:sub(1, 2) == "~/" then
		path = (os.getenv("HOME") or "") .. value:sub(2)
	else
		path = cwd() .. "/" .. value
	end

	-- "name/" creates that folder (yazi's convention for `a`) and stays.
	if path:sub(-1) == "/" then
		local status = Command("mkdir"):arg({ "-p", "--", path }):status()
		if not status or not status.success then
			return notify("Could not create " .. path)
		end
		return
	end

	local ok, err = fs.write(Url(result), path .. "\n")
	if not ok then
		return notify(tostring(err))
	end
	ya.emit("quit", { no_cwd_file = true })
end

-- Save dialogs: the placeholder follows the current folder, so the suggested
-- name stays visible and hovered wherever the file is saved. The wrapper
-- passes the placeholder (TERMFILECHOOSER_PLACEHOLDER, empty when it could not
-- make one or the file exists), its folder (TERMFILECHOOSER_DIR) and a state
-- file (TERMFILECHOOSER_STATE) that gets the placeholder's current path ("" if
-- none), then any copies of it, for its cleanup and for Ctrl+S. Runs in
-- yazi's sync context: plain Lua io/os.
local MARKER = "" -- the placeholder's one line, from the wrapper (TERMFILECHOOSER_MARKER)

local function dirname(p) return p:match("^(.*)/[^/]*$") or "/" end
local function basename(p) return p:match("([^/]*)$") end
local function join(dir, name) return (dir == "/" and "" or dir) .. "/" .. name end

-- Anything at P: something that opens (a file or folder, also on a read-only
-- mount), else a broken symlink (renaming a path to itself changes nothing and
-- fails only when there is nothing there, or the folder is read-only).
local function exists(p)
	local f = io.open(p, "r")
	if f then
		f:close()
		return true
	end
	return os.rename(p, p) and true or false
end

-- A regular file (a folder opens too, but can't be read).
local function is_file(p)
	local f = io.open(p, "rb")
	if not f then
		return false
	end
	local _, err = f:read(0) -- nil, nil at the end of a file; nil, err for a folder
	f:close()
	return err == nil
end

local function is_placeholder(p)
	local f = io.open(p, "rb")
	if not f then
		return false
	end
	local content = f:read(200) or ""
	f:close()
	return content:gsub("\n$", "") == MARKER
end

-- DIR/NAME, or DIR/NAME_1, DIR/NAME_2, ... (extension last), as the wrapper.
local function unique(dir, name)
	local p = join(dir, name)
	if not exists(p) then
		return p
	end
	local stem, ext = name:match("^(.+)(%.[^.]*)$")
	if not stem then
		stem, ext = name, ""
	end
	local i = 1
	while exists(join(dir, stem .. "_" .. i .. ext)) do
		i = i + 1
	end
	return join(dir, stem .. "_" .. i .. ext)
end

local function follow_setup()
	local state = os.getenv("TERMFILECHOOSER_STATE") or ""
	local name = os.getenv("TERMFILECHOOSER_NAME") or ""
	MARKER = os.getenv("TERMFILECHOOSER_MARKER") or ""
	if os.getenv("TERMFILECHOOSER_MODE") ~= "save" or state == "" or name == "" or MARKER == "" then
		return
	end
	local current = os.getenv("TERMFILECHOOSER_PLACEHOLDER") or "" -- "" = none yet
	local dir = os.getenv("TERMFILECHOOSER_DIR") or "" -- the folder it is in
	local start_dir, suggested = dir, name
	local copies = {} -- duplicates made with y/p, removed by the wrapper
	local warned = false -- the read-only notice, once per dialog

	-- Saving over an existing file: the dialog starts on that file (o saves
	-- over it), with no placeholder; back in its folder, it is that again.
	local existing = current == "" and is_file(join(start_dir, name)) and join(start_dir, name) or ""

	-- State file: the placeholder first ("" for none), then its copies.
	local function write_state()
		local f = io.open(state, "w")
		if f then
			f:write(current, "\n")
			for _, c in ipairs(copies) do
				f:write(c, "\n")
			end
			f:close()
		end
	end
	local function record(p)
		current = p
		if p ~= "" then
			dir = dirname(p)
		end
		write_state()
	end

	-- Renamed (r) or moved (x, p) by hand: keep following it, under its new name.
	local function moved(from, to)
		if current ~= "" and tostring(from) == current then
			name = basename(tostring(to))
			record(tostring(to))
		end
	end
	ps.sub("rename", function(body) moved(body.from, body.to) end)
	ps.sub("move", function(body)
		for _, item in ipairs(body.items) do
			moved(item.from, item.to)
		end
	end)
	ps.sub("bulk-rename", function(body) -- { [from] = to, ... }
		for from, to in pairs(body) do
			moved(from, to)
		end
	end)
	ps.sub("duplicate", function(body)
		for _, item in ipairs(body.items) do
			if current ~= "" and tostring(item.from) == current then
				copies[#copies + 1] = tostring(item.to)
				write_state()
			end
		end
	end)

	-- Being moved by hand (cut, not pasted yet): leave it where it is.
	local function is_cut()
		if current == "" or not cx.yanked.is_cut then
			return false
		end
		for _, file in pairs(cx.yanked) do -- File objects
			if tostring(file.url) == current then
				return true
			end
		end
		return false
	end

	local function follow()
		local new = tostring(cx.active.current.cwd)
		-- Only real folders: not search results (search://...), archives or
		-- remote ones, which have a scheme in front.
		if new:sub(1, 1) ~= "/" or new == dir or is_cut() then
			return
		end

		-- Back in the folder of the existing file: hover that file again.
		if existing ~= "" and new == start_dir and name == suggested then
			if current ~= "" and is_placeholder(current) then
				os.remove(current)
			end
			record("")
			dir = start_dir
			ya.emit("reveal", { existing })
			return
		end

		local target = unique(new, name)
		local f = io.open(target, "w")
		if not f then
			if not warned then
				warned = true
				notify("Can't show " .. name .. " in a read-only folder.", "warn")
			end
			return
		end
		f:write(MARKER, "\n")
		f:close()

		if current ~= "" and current ~= target and is_placeholder(current) then
			os.remove(current)
		end
		record(target)
		ya.emit("reveal", { target }) -- hovered, also after going up
	end
	ps.sub("cd", function(body)
		if body.tab == cx.active.id.value then -- not a cd in a tab in the background
			follow()
		end
	end)
	ps.sub("tab", follow) -- another tab, another folder (no cd event)
end

return {
	setup = follow_setup,
	entry = function(_, job)
		local action = job.args[1]
		if action == "cancel" then
			local fallback = job.args.fallback or "quit"
			if not in_dialog() then
				ya.emit(fallback, {})
			elseif fallback == "escape" and has_escapable() then
				ya.emit("escape", {})
			else
				cancel()
			end
		elseif action == "confirm" then
			if in_dialog() then
				ya.emit("quit", {}) -- the wrapper reads the folder from the cwd file
			else
				ya.emit("escape", { search = true }) -- yazi's default for Ctrl+S
			end
		elseif action == "name" then
			save_as()
		end
	end,
}
