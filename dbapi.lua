#!/usr/bin/env tarantool

box.cfg {
    log_level = 10,
}

local log = require('log')
local conn = require('mysql').connect({ host = localhost, user = 'root', password = '11', db = 'tempdb' })

--
local ResponseCode = {
    Ok = 1,
    NotFound = 2,
    BadRequest = 3,
    MeaninglessRequest = 4,
    UnknownError = 5,
    UserExists = 6
}

local function api_response(response_code, response_data)
    return { code = response_code, response = response_data }
end

local function json_keys_present(json, keys)
    if not json then
        return false
    end
    for key, _ in pairs(keys) do
        log.info(key)
        if not json[key] then
            return false
        end
    end
    return true
end

--

local function create_forum(json)
    if not json_keys_present(json, { 'name', 'short_name', 'user' }) then
        return api_response(ResponseCode.MeaninglessRequest, {})
    end

    conn:begin()
    local result = conn:execute('insert into forum (name, short_name, user) values (?, ?, ?)', json.name, json.short_name, json.user)
    if result then
        local inserted_item = conn:execute('select * from forum where id = last_insert_id()')
        conn:commit()
        if inserted_item then
            return api_response(ResponseCode.Ok, inserted_item)
        end
    end

    conn:rollback()
    return api_response(ResponseCode.UnknownError, {})
end

--

local server = require('http.server').new('*', 8081)

server:route({ path = '/db/api/', method = 'POST' }, create_forum)

server:hook('before_dispatch', function(self, request)
    local json
    local status, err = pcall(function() json = request:json() end)
    if not json and request.method ~= 'GET' then
        return { response = api_response(ResponseCode.BadRequest, err) }
    end
    return json
end)
server:hook('after_dispatch', function(self, request, request_override, response_data)
    return request:render({ json = response_data })
end)

server:start()
