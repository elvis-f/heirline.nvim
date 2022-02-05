local M = {}

function M.get_highlight(hlname)
    local hl = vim.api.nvim_get_hl_by_name(hlname, true)
    local t = {}
    local hex = function(n)
        if n then
            return string.format("#%06x", n)
        end
    end
    t.fg = hex(hl.foreground)
    t.bg = hex(hl.background)
    t.sp = hex(hl.special)
    t.style = "none,"
    if hl.underline then
        t.style = t.style .. "underline"
    end
    if hl.undercurl then
        t.style = t.style .. "undercurl"
    end
    if hl.bold then
        t.style = t.style .. "bold"
    end
    if hl.italic then
        t.style = t.style .. "italic"
    end
    if hl.reverse then
        t.style = t.style .. "reverse"
    end
    if hl.nocombine then
        t.style = t.style .. "nocombine"
    end
    return t
end

function M.clone(block, with)
    return vim.tbl_deep_extend("force", block, with or {})
end

function M.surround(delimiters, color, component)
    component = M.clone(component)

    local surround_color = function(self)
        if type(color) == "function" then
            return color(self)
        else
            return color
        end
    end

    return {
        {
            provider = delimiters[1],
            hl = function(self)
                local s_color = surround_color(self)
                if s_color then
                    return { fg = s_color }
                end
            end,
        },
        {
            hl = function(self)
                local s_color = surround_color(self)
                if s_color then
                    return { bg = s_color }
                end
            end,
            component,
        },
        {
            provider = delimiters[2],
            hl = function(self)
                local s_color = surround_color(self)
                if s_color then
                    return { fg = s_color }
                end
            end,
        },
    }
end

function M.insert(destination, ...)
    local children = { ... }
    local new = M.clone(destination)
    for _, child in ipairs(children) do
        local new_child = M.clone(child)
        table.insert(new, new_child)
    end
    return new
end

function M.count_chars(str)
    return vim.api.nvim_eval_statusline(str, { winid = 0, maxwidth = 0 }).width
end

function M.make_elastic_component(priority, ...)
    local new = M.insert({}, ...)

    new.static = {
        priority = priority,
    }
    new.init = function(self)
        if not vim.tbl_contains(self.elastic_ids, self.id) then
            table.insert(self.elastic_ids, self.id)
        end
        self:set_win_attr("win_child_index", nil, 1)
        self.pick_child = { self:get_win_attr("win_child_index") }
    end
    new.restrict = { win_child_index = true }

    return new
end

local function next_child(self)
    local pi = self:get_win_attr("win_child_index") + 1
    if pi > #self then
        return false
    end
    self:set_win_attr("win_child_index", pi)
    return true
end

local function prev_child(self)
    local pi = self:get_win_attr("win_child_index") - 1
    if pi < 1 then
        return false
    end
    self:set_win_attr("win_child_index", pi)
    return true
end

function M.elastic_before(statusline, prev_out)
    statusline.elastic_ids = {}
end

local function is_child(child, parent) -- ids
    if not (child and parent) then
        return false
    end
    if #child <= #parent then
        return false
    end
    for i, v in ipairs(parent) do
        if child[i] ~= v then
            return false
        end
    end
    return true
end

local function group_elastic_ids(statusline, mode)
    local priority_groups = {}
    local priorities = {}
    local cur_priority
    local prev_component

    for _, id in ipairs(statusline.elastic_ids) do
        local ec = statusline:get(id)

        local priority
        if prev_component and is_child(ec.id, prev_component.id) then
            priority = cur_priority + mode
            -- if mode == -1 then
            --     priority = ec.priority < cur_priority + mode and ec.priority or cur_priority + mode
            -- elseif mode == 1 then
            --     priority = ec.priority > cur_priority + mode and ec.priority or cur_priority + mode
            -- end
        else
            priority = ec.priority
        end

        prev_component = ec
        cur_priority = priority

        priority_groups[priority] = priority_groups[priority] or {}
        table.insert(priority_groups[priority], id)
        if not priorities[priority] then
            table.insert(priorities, priority)
        end
    end
    return priority_groups, priorities
end


function M.elastic_after(statusline, out)
    local winw = vim.api.nvim_win_get_width(0)

    local stl_len = M.count_chars(out)

    if stl_len > winw then
        local priority_groups, priorities = group_elastic_ids(statusline, -1)

        table.sort(priorities, function(a, b)
            return a < b
        end)

        local saved_chars = 0

        for _, p in ipairs(priorities) do
            local ids = priority_groups[p]
            for _, id in ipairs(ids) do
                local ec = statusline:get(id)
                -- try increasing the child index and return success
                if next_child(ec) then
                    local prev_len = M.count_chars(ec.stl)
                    local cur_len = M.count_chars(ec:eval())
                    saved_chars = saved_chars + (prev_len - cur_len)
                end
            end
            if stl_len - saved_chars <= winw then
                break
            end
        end
    elseif stl_len < winw then
        local gained_chars = 0

        local priority_groups, priorities = group_elastic_ids(statusline, 1)
        table.sort(priorities, function(a, b)
            return a > b
        end)

        for _, p in ipairs(priorities) do
            local ids = priority_groups[p]
            for _, id in ipairs(ids) do
                local ec = statusline:get(id)

                if prev_child(ec) then
                    local prev_len = M.count_chars(ec.stl)
                    local cur_len = M.count_chars(ec:eval())
                    gained_chars = gained_chars + (cur_len - prev_len)
                end
            end

            if stl_len + gained_chars > winw then
                for _, id in ipairs(ids) do
                    local ec = statusline:get(id)
                    next_child(ec)
                end
                break
            end
        end
    end
    return out
end

return M
