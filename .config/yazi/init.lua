require("full-border"):setup {
    set = "rounded",
}

require("git"):setup {
    order = 1500,
}

-- File dialogs (save): the placeholder of the file to be saved follows the
-- current folder. Does nothing outside a dialog.
require("chooser"):setup()
