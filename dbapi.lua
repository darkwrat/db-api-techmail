#!/usb/bin/env tarantool

box.cfg {
    log_level = 10,
}

local log = require('log')
local conn = require('mysql').connect({ host = localhost, user = 'root', password = '11', db = 'tempdb' })

--

local function api_response(response_code, response_data)
    return { code = response_code, response = response_data }
end

--

local function create_forum(json)
    local inserted_item = nil

    conn:begin()
    local result = conn:execute('insert into forum (name, short_name, user) values (?, ?, ?)', json.name, json.short_name, json.user)
    if result ~= nil then
        inserted_item = conn:execute('select * from forum where id = last_insert_id()')
        conn:commit()
    else
        conn:rollback()
    end

    return api_response(0, inserted_item)
end

--

local server = require('http.server').new('*', 8081)

server:route({ path = '/db/api/', method = 'POST' }, create_forum)

server:hook('before_dispatch', function(self, request)
    local json = nil
    local status, err = pcall(function() json = request:json() end)
    -- todo
    return json
end)
server:hook('after_dispatch', function(self, request, request_override, response_data)
    return request:render({ json = response_data })
end)

server:start()
