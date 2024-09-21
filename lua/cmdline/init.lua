local M = {}

---@class CmdlineOptions
---@field width?  number
---@field border? string

---@param options? CmdlineOptions
function M.open(options)
    if not options then options = {} end

    local buffer = vim.api.nvim_create_buf(false, true)
    vim.bo[buffer].filetype = 'vim'
    vim.bo[buffer].buftype = 'prompt'
    vim.bo[buffer].bufhidden = 'delete'

    vim.keymap.set('n', '<esc>', '<cmd>bdelete!<cr>', { buffer = buffer, desc = 'Close cmdline' })

    local width = options.width or 0.6
    local window = vim.api.nvim_open_win(buffer, true, {
        relative = 'editor',
        border   = options.border,
        row      = math.floor(vim.o.lines / 2.5),
        col      = math.floor(vim.o.columns * (1 - width) / 2),
        width    = math.floor(vim.o.columns * width),
        height   = 1,
    })
    vim.wo[window].number = false
    vim.wo[window].relativenumber = false
    vim.wo[window].cursorline = false

    vim.fn.prompt_setprompt(buffer, ':')
    vim.fn.prompt_setcallback(buffer, function (command)
        vim.api.nvim_buf_delete(buffer, { force = true })
        vim.schedule(function () vim.cmd(command) end)
    end)

    vim.cmd.startinsert()
end

return M
