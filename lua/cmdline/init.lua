local M = {}

---@class CmdlineOptions
---@field position?    number Between 0.0 and 1.0
---@field width?       number Between 0.0 and 1.0
---@field border?      string Border around the cmdline window.
---@field on_window?   fun(window: integer) Invoked on the cmdline window.
---@field on_buffer?   fun(buffer: integer) Invoked on the cmdline buffer.
---@field completeopt? string[] Local value for 'completeopt'.

---@type CmdlineOptions
M.default_options = {}

---@class Cmdline
---@field omnifunc_lead   string
---@field working_command string
---@field history_index   integer
---@field prompt_buffer   integer
---@field return_window   integer
local Cmdline = {}

---@type table<integer, Cmdline>
M.instances = {}

---@type integer?
M.current_instance_buffer = nil

---@return Cmdline
function Cmdline.current()
    return M.instances[assert(M.current_instance_buffer)]
end

---@type fun(prompt_buffer: integer, return_window: integer): Cmdline
function Cmdline.new(prompt_buffer, return_window)
    return setmetatable({
        omnifunc_lead   = '',
        working_command = '',
        history_index   = vim.fn.histnr('cmd'),
        prompt_buffer   = prompt_buffer,
        return_window   = return_window,
    }, { __index = Cmdline })
end

---@return string
function Cmdline:prompt()
    return vim.fn.prompt_getprompt(self.prompt_buffer)
end

---@return string
function Cmdline:current_line()
    return vim.api.nvim_buf_call(self.prompt_buffer, vim.api.nvim_get_current_line)
end

---@return string
function Cmdline:command()
    return self:current_line():sub(#self:prompt() + 1)
end

---@param command string
function Cmdline:set_command(command)
    vim.api.nvim_buf_call(self.prompt_buffer, function ()
        vim.api.nvim_set_current_line(self:prompt() .. command)
    end)
end

---@param index integer
function Cmdline:set_history_index(index)
    local max = vim.fn.histnr('cmd')
    if self.history_index == max then
        self.working_command = self:command()
    end
    if index > max then
        self.history_index = max
    elseif index < 0 then
        self.history_index = 0
    else
        self.history_index = index
    end
    if self.history_index == max then
        self:set_command(self.working_command)
    else
        self:set_command(vim.fn.histget('cmd', self.history_index + 1))
    end
end

function M.history_up()
    Cmdline.current():set_history_index(Cmdline.current().history_index - vim.v.count1)
end

function M.history_down()
    Cmdline.current():set_history_index(Cmdline.current().history_index + vim.v.count1)
end

function M.history_top()
    Cmdline.current():set_history_index(0)
end

function M.history_bottom()
    Cmdline.current():set_history_index(vim.fn.histnr('cmd'))
end

---@type fun(findstart: integer): integer|string[]
function vim.g.nvim_cmdline_omnifunc(findstart)
    local instance = Cmdline.current()
    if findstart == 1 then
        local cursor = vim.fn.col('.') - 1
        instance.omnifunc_lead = instance:current_line():sub(#instance:prompt() + 1, cursor)
        return cursor - #instance.omnifunc_lead:match('([a-zA-Z_]*)$')
    else
        return vim.fn.getcompletion(instance.omnifunc_lead, 'cmdline')
    end
end

---@type fun(options: CmdlineOptions): vim.api.keyset.win_config
local function cmdline_window_config(options)
    local width = options.width or 0.6
    local position = options.position or 0.4
    return {
        relative = 'editor',
        border   = options.border or 'rounded',
        row      = math.floor(vim.o.lines * position),
        col      = math.floor(vim.o.columns * (1 - width) / 2),
        width    = math.floor(vim.o.columns * width),
        height   = 1,
    }
end

---@param options CmdlineOptions
---@return integer buffer, integer window
local function create_cmdline_buffer_and_window(options)
    local buffer = vim.api.nvim_create_buf(false --[[listed]], true --[[scratch]])
    vim.bo[buffer].filetype  = 'vim'
    vim.bo[buffer].buftype   = 'prompt'
    vim.bo[buffer].bufhidden = 'delete'
    vim.bo[buffer].omnifunc  = 'v:lua.vim.g.nvim_cmdline_omnifunc'

    local window = vim.api.nvim_open_win(buffer, false --[[enter]], cmdline_window_config(options))
    vim.wo[window].number         = false
    vim.wo[window].relativenumber = false
    vim.wo[window].cursorline     = false

    vim.fn.prompt_setprompt(buffer, ':')
    vim.fn.prompt_setcallback(buffer, function (command)
        vim.api.nvim_buf_delete(buffer, { force = true })
        vim.fn.histadd('cmd', command)
        vim.schedule(function () vim.cmd(command) end)
    end)
    return buffer, window
end

---@param options? CmdlineOptions
function M.open(options)
    if not options then options = M.default_options end

    local buffer, window = create_cmdline_buffer_and_window(options)
    M.instances[buffer] = Cmdline.new(buffer, vim.api.nvim_get_current_win())

    ---@type fun(description: string, override?: vim.keymap.set.Opts): vim.keymap.set.Opts
    local function opts(description, override)
        return vim.tbl_deep_extend('force', { buffer = buffer, desc = 'nvim-cmdline: ' .. description }, override or {})
    end
    vim.keymap.set('n', 'gg', M.history_top, opts('History top'))
    vim.keymap.set('n', 'G', M.history_bottom, opts('History bottom'))
    vim.keymap.set('n', 'k', M.history_up, opts('History up'))
    vim.keymap.set('n', 'j', M.history_down, opts('History down'))
    vim.keymap.set({ 'n', 'i' }, '<up>', M.history_up, opts('History up'))
    vim.keymap.set({ 'n', 'i' }, '<down>', M.history_down, opts('History down'))
    vim.keymap.set('n', ':', ':', opts('Backup native cmdline'))
    vim.keymap.set('n', '<esc>', '<cmd>bwipeout!<cr>', opts('Close'))
    vim.keymap.set('i', '<tab>', 'pumvisible() ? "<c-n>" : "<c-x><c-o>"', opts('Next completion', { expr = true }))
    vim.keymap.set('i', '<s-tab>', 'pumvisible() ? "<c-p>" : "<s-tab>"', opts('Previous completion', { expr = true }))

    ---@type fun(event: string, description: string, callback: fun())
    local function autocmd(event, description, callback)
        vim.api.nvim_create_autocmd(event, {
            callback = callback,
            buffer   = buffer,
            desc     = 'nvim-cmdline: ' .. description,
        })
    end
    local previous_completeopt = vim.opt.completeopt
    autocmd('BufEnter', 'Set cmdline instance', function ()
        M.current_instance_buffer = buffer
        if options.completeopt then vim.opt.completeopt = options.completeopt end
    end)
    autocmd('BufLeave', 'Reset cmdline instance', function ()
        M.current_instance_buffer = nil
        if options.completeopt then vim.opt.completeopt = previous_completeopt end
    end)
    autocmd('BufWipeout', 'Clean up cmdline instance', function ()
        vim.api.nvim_set_current_win(M.instances[buffer].return_window)
        M.instances[buffer] = nil
    end)
    autocmd('VimResized', 'Resize cmdline window', function ()
        vim.api.nvim_win_set_config(window, cmdline_window_config(options))
    end)

    if options.on_buffer then options.on_buffer(buffer) end
    if options.on_window then options.on_window(window) end

    vim.api.nvim_set_current_win(window)
    vim.cmd.startinsert()
end

return M
