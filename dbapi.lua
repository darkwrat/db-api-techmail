#!/usr/bin/env tarantool

box.cfg {
    log_level = 10,
}

local log = require('log')
local conn = require('mysql').connect({ host = localhost, user = 'root', password = '11', db = 'tempdb' })
local server = require('http.server').new('*', 8081)

-- -- --

local function json_keys_present(json, keys)
    if not json then
        return false
    end
    for key, _ in pairs(keys) do
        if not json[key] then
            return false
        end
    end
    return true
end

local ResponseCode = { Ok = 1, NotFound = 2, BadRequest = 3, MeaninglessRequest = 4, UnknownError = 5, UserExists = 6 }

local function api_response(response_code, response_data)
    return { code = response_code, response = response_data }
end

-- -- --

-- common
local api_common_clear -- https://github.com/andyudina/technopark-db-api/blob/master/doc/clear.md
local api_common_status -- https://github.com/andyudina/technopark-db-api/blob/master/doc/status.md

server:route({ path = '/db/api/clear', method = 'POST' }, api_common_clear)
server:route({ path = '/db/api/status', method = 'GET' }, api_common_status)

-- forum
local api_forum_create -- https://github.com/andyudina/technopark-db-api/blob/master/doc/forum/create.md
local api_forum_details -- https://github.com/andyudina/technopark-db-api/blob/master/doc/forum/details.md
local api_forum_list_posts -- https://github.com/andyudina/technopark-db-api/blob/master/doc/forum/listPosts.md
local api_forum_list_threads -- https://github.com/andyudina/technopark-db-api/blob/master/doc/forum/listThreads.md
local api_forum_list_users -- https://github.com/andyudina/technopark-db-api/blob/master/doc/forum/listUsers.md

api_forum_create = function(json)
    if not json_keys_present(json, { 'name', 'short_name', 'user' }) then
        return api_response(ResponseCode.MeaninglessRequest, {})
    end

    conn:begin()
    local result = conn:execute('insert into forum (name, short_name, user) values (?, ?, ?)',
        json.name, json.short_name, json.user)
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

server:route({ path = '/db/api/forum/create', method = 'POST' }, api_forum_create)
server:route({ path = '/db/api/forum/details', method = 'GET' }, api_forum_details)
server:route({ path = '/db/api/forum/listPosts', method = 'GET' }, api_forum_list_posts)
server:route({ path = '/db/api/forum/listThreads', method = 'GET' }, api_forum_list_threads)
server:route({ path = '/db/api/forum/listUsers', method = 'GET' }, api_forum_list_users)

-- post
local api_post_create -- https://github.com/andyudina/technopark-db-api/blob/master/doc/post/create.md
local api_post_details -- https://github.com/andyudina/technopark-db-api/blob/master/doc/post/details.md
local api_post_list -- https://github.com/andyudina/technopark-db-api/blob/master/doc/post/list.md
local api_post_remove -- https://github.com/andyudina/technopark-db-api/blob/master/doc/post/remove.md
local api_post_restore -- https://github.com/andyudina/technopark-db-api/blob/master/doc/post/restore.md
local api_post_update -- https://github.com/andyudina/technopark-db-api/blob/master/doc/post/update.md
local api_post_vote -- https://github.com/andyudina/technopark-db-api/blob/master/doc/post/vote.md

server:route({ path = '/db/api/post/create', method = 'POST' }, api_post_create)
server:route({ path = '/db/api/post/details', method = 'GET' }, api_post_details)
server:route({ path = '/db/api/post/list', method = 'GET' }, api_post_list)
server:route({ path = '/db/api/post/remove', method = 'POST' }, api_post_remove)
server:route({ path = '/db/api/post/restore', method = 'POST' }, api_post_restore)
server:route({ path = '/db/api/post/update', method = 'POST' }, api_post_update)
server:route({ path = '/db/api/post/vote', method = 'POST' }, api_post_vote)

-- user
local api_user_create -- https://github.com/andyudina/technopark-db-api/blob/master/doc/user/create.md
local api_user_details -- https://github.com/andyudina/technopark-db-api/blob/master/doc/user/details.md
local api_user_follow -- https://github.com/andyudina/technopark-db-api/blob/master/doc/user/follow.md
local api_user_list_followers -- https://github.com/andyudina/technopark-db-api/blob/master/doc/user/listFollowers.md
local api_user_list_following -- https://github.com/andyudina/technopark-db-api/blob/master/doc/user/listFollowing.md
local api_user_list_posts -- https://github.com/andyudina/technopark-db-api/blob/master/doc/user/listPosts.md
local api_user_unfollow -- https://github.com/andyudina/technopark-db-api/blob/master/doc/user/unfollow.md
local api_user_update_profile -- https://github.com/andyudina/technopark-db-api/blob/master/doc/user/updateProfile.md

server:route({ path = '/db/api/user/create', method = 'POST' }, api_user_create)
server:route({ path = '/db/api/user/details', method = 'GET' }, api_user_details)
server:route({ path = '/db/api/user/follow', method = 'POST' }, api_user_follow)
server:route({ path = '/db/api/user/listFollowers', method = 'GET' }, api_user_list_followers)
server:route({ path = '/db/api/user/listFollowing', method = 'GET' }, api_user_list_following)
server:route({ path = '/db/api/user/listPosts', method = 'GET' }, api_user_list_posts)
server:route({ path = '/db/api/user/unfollow', method = 'POST' }, api_user_unfollow)
server:route({ path = '/db/api/user/updateProfile', method = 'POST' }, api_user_update_profile)

-- thread
local api_thread_close -- https://github.com/andyudina/technopark-db-api/blob/master/doc/thread/close.md
local api_thread_create -- https://github.com/andyudina/technopark-db-api/blob/master/doc/thread/create.md
local api_thread_details -- https://github.com/andyudina/technopark-db-api/blob/master/doc/thread/details.md
local api_thread_list -- https://github.com/andyudina/technopark-db-api/blob/master/doc/thread/list.md
local api_thread_list_posts -- https://github.com/andyudina/technopark-db-api/blob/master/doc/thread/listPosts.md
local api_thread_open -- https://github.com/andyudina/technopark-db-api/blob/master/doc/thread/open.md
local api_thread_remove -- https://github.com/andyudina/technopark-db-api/blob/master/doc/thread/remove.md
local api_thread_restore -- https://github.com/andyudina/technopark-db-api/blob/master/doc/thread/restore.md
local api_thread_subscribe -- https://github.com/andyudina/technopark-db-api/blob/master/doc/thread/subscribe.md
local api_thread_unsubscribe -- https://github.com/andyudina/technopark-db-api/blob/master/doc/thread/unsubscribe.md
local api_thread_update -- https://github.com/andyudina/technopark-db-api/blob/master/doc/thread/update.md
local api_thread_vote -- https://github.com/andyudina/technopark-db-api/blob/master/doc/thread/vote.md

server:route({ path = '/db/api/thread/close', method = 'POST' }, api_thread_close)
server:route({ path = '/db/api/thread/create', method = 'POST' }, api_thread_create)
server:route({ path = '/db/api/thread/details', method = 'GET' }, api_thread_details)
server:route({ path = '/db/api/thread/list', method = 'GET' }, api_thread_list)
server:route({ path = '/db/api/thread/listPosts', method = 'GET' }, api_thread_list_posts)
server:route({ path = '/db/api/thread/open', method = 'POST' }, api_thread_open)
server:route({ path = '/db/api/thread/remove', method = 'POST' }, api_thread_remove)
server:route({ path = '/db/api/thread/restore', method = 'POST' }, api_thread_restore)
server:route({ path = '/db/api/thread/subscribe', method = 'POST' }, api_thread_subscribe)
server:route({ path = '/db/api/thread/unsubscribe', method = 'POST' }, api_thread_unsubscribe)
server:route({ path = '/db/api/thread/update', method = 'POST' }, api_thread_update)
server:route({ path = '/db/api/thread/vote', method = 'POST' }, api_thread_vote)

-- -- --

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
