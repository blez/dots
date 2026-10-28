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

return {
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
