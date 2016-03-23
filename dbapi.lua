#!/usr/bin/env tarantool

box.cfg {
    log_level = 10,
}

local log = require('log')
local conn = require('mysql').connect({ host = localhost, user = 'root', password = '11', db = 'tempdb', raise = true })
local server = require('http.server').new('*', 8081)

-- -- --

local function keys_present(obj, keys)
    if not obj then
        return false
    end
    for _, key in pairs(keys) do
        if not obj[key] then
            return false
        end
    end
    return true
end

local ResultCode = { Ok = 1, NotFound = 2, BadRequest = 3, MeaninglessRequest = 4, UnknownError = 5, UserExists = 6 }

local function create_response(response_code, response_data)
    return { code = response_code, response = response_data }
end

local function single_value(obj)
    if type(obj) ~= 'table' or table.getn(obj) ~= 1 then
        return nil
    end
    return obj[1]
end

-- -- --

-- common
local api_common_clear -- https://github.com/andyudina/technopark-db-api/blob/master/doc/clear.md
local api_common_status -- https://github.com/andyudina/technopark-db-api/blob/master/doc/status.md

api_common_clear = function(args)
    conn:begin()
    for _, v in pairs({ 'userfollow', 'usersubscription', 'post', 'thread', 'forum', 'user' }) do
        conn:execute('truncate table ' .. v)
    end
    conn:commit()
    return create_response(ResultCode.Ok, 'OK')
end

-- todo: избавиться от count(*)
api_common_status = function(args)
    local result = {}
    for _, v in pairs({ 'post', 'thread', 'forum', 'user' }) do
        result[v] = single_value(conn:execute('select count(*) as nrows from ' .. v)).nrows
    end
    return create_response(ResultCode.Ok, result)
end

server:route({ path = '/db/api/clear', method = 'POST' }, api_common_clear)
server:route({ path = '/db/api/status', method = 'GET' }, api_common_status)

-- user
local api_user_create -- https://github.com/andyudina/technopark-db-api/blob/master/doc/user/create.md
local api_user_details -- https://github.com/andyudina/technopark-db-api/blob/master/doc/user/details.md
local api_user_follow -- https://github.com/andyudina/technopark-db-api/blob/master/doc/user/follow.md
local api_user_list_followers -- https://github.com/andyudina/technopark-db-api/blob/master/doc/user/listFollowers.md
local api_user_list_following -- https://github.com/andyudina/technopark-db-api/blob/master/doc/user/listFollowing.md
local api_user_list_posts -- https://github.com/andyudina/technopark-db-api/blob/master/doc/user/listPosts.md
local api_user_unfollow -- https://github.com/andyudina/technopark-db-api/blob/master/doc/user/unfollow.md
local api_user_update_profile -- https://github.com/andyudina/technopark-db-api/blob/master/doc/user/updateProfile.md

-- fixme: isAnonymous
api_user_create = function(args)
    if not keys_present(args.json, { 'username', 'about', 'name', 'email' }) then
        return create_response(ResultCode.MeaninglessRequest, {})
    end

    conn:begin()
    if single_value(conn:execute('select 1 from user where email = ? limit 1', args.json.email)) then
        return create_response(ResultCode.UserExists, {})
    end
    conn:execute('insert into user(username, about, name, email) values (?, ?, ?, ?)',
        args.json.username, args.json.about, args.json.name, args.json.email)
    local inserted_id = single_value(conn:execute('select last_insert_id() as x')).x
    conn:commit()
    if args.json.isAnonymous then
        conn:execute('update user set isAnonymous = 1 where id = ?',
            args.json.isAnonymous, inserted_id)
    end
    return create_response(ResultCode.Ok, single_value(conn:execute('select * from user where id = ?', inserted_id)))
end

api_user_details = function(args)
    if not keys_present(args.query_string, { 'user' }) then
        return create_response(ResultCode.MeaninglessRequest, {})
    end

    local result = single_value(conn:execute('select * from user where email = ?', args.query_string.user))
    if not result then
        return create_response(ResultCode.NotFound, {})
    end
    local query = 'select u.email from userfollow uf join user u on uf.followed_user_id = u.id where 1 '
    result.following = {}
    for _, v in pairs(conn:execute(query .. ' and uf.follower_user_id = ?', result.id)) do
        table.insert(result.following, v)
    end
    result.followers = {}
    for _, v in pairs(conn:execute(query .. ' and uf.followed_user_id = ?', result.id)) do
        table.insert(result.following, v)
    end
    result.subscriptions = {} -- todo: index
    for _, v in pairs(conn:execute('select thread_id from usersubscription where user_id = ?', result.id)) do
        table.insert(result.subscriptions, v)
    end
    return result
end

server:route({ path = '/db/api/user/create', method = 'POST' }, api_user_create)
server:route({ path = '/db/api/user/details', method = 'GET' }, api_user_details)
--server:route({ path = '/db/api/user/follow', method = 'POST' }, api_user_follow)
--server:route({ path = '/db/api/user/listFollowers', method = 'GET' }, api_user_list_followers)
--server:route({ path = '/db/api/user/listFollowing', method = 'GET' }, api_user_list_following)
--server:route({ path = '/db/api/user/listPosts', method = 'GET' }, api_user_list_posts)
--server:route({ path = '/db/api/user/unfollow', method = 'POST' }, api_user_unfollow)
--server:route({ path = '/db/api/user/updateProfile', method = 'POST' }, api_user_update_profile)

-- forum
local api_forum_create -- https://github.com/andyudina/technopark-db-api/blob/master/doc/forum/create.md
local api_forum_details -- https://github.com/andyudina/technopark-db-api/blob/master/doc/forum/details.md
local api_forum_list_posts -- https://github.com/andyudina/technopark-db-api/blob/master/doc/forum/listPosts.md
local api_forum_list_threads -- https://github.com/andyudina/technopark-db-api/blob/master/doc/forum/listThreads.md
local api_forum_list_users -- https://github.com/andyudina/technopark-db-api/blob/master/doc/forum/listUsers.md

--api_forum_create = function(r)
--    if not keys_present(r.json, { 'name', 'short_name', 'user' }) then
--        return create_response(ResultCode.MeaninglessRequest, {})
--    end
--
--    local forum =
--
--    conn:begin()
--    local result = conn:execute('insert into forum (name, short_name, user) values (?, ?, ?)',
--        r.json.name, r.json.short_name, r.json.user)
--    if not result then
--        local inserted_item = conn:execute('select * from forum where id = last_insert_id()')
--        conn:commit()
--        if inserted_item then
--            return create_response(ResultCode.Ok, inserted_item)
--        end
--    end
--
--    conn:rollback()
--    return create_response(ResultCode.UnknownError, {})
--end

--server:route({ path = '/db/api/forum/create', method = 'POST' }, api_forum_create)
--server:route({ path = '/db/api/forum/details', method = 'GET' }, api_forum_details)
--server:route({ path = '/db/api/forum/listPosts', method = 'GET' }, api_forum_list_posts)
--server:route({ path = '/db/api/forum/listThreads', method = 'GET' }, api_forum_list_threads)
--server:route({ path = '/db/api/forum/listUsers', method = 'GET' }, api_forum_list_users)

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

--server:route({ path = '/db/api/thread/close', method = 'POST' }, api_thread_close)
--server:route({ path = '/db/api/thread/create', method = 'POST' }, api_thread_create)
--server:route({ path = '/db/api/thread/details', method = 'GET' }, api_thread_details)
--server:route({ path = '/db/api/thread/list', method = 'GET' }, api_thread_list)
--server:route({ path = '/db/api/thread/listPosts', method = 'GET' }, api_thread_list_posts)
--server:route({ path = '/db/api/thread/open', method = 'POST' }, api_thread_open)
--server:route({ path = '/db/api/thread/remove', method = 'POST' }, api_thread_remove)
--server:route({ path = '/db/api/thread/restore', method = 'POST' }, api_thread_restore)
--server:route({ path = '/db/api/thread/subscribe', method = 'POST' }, api_thread_subscribe)
--server:route({ path = '/db/api/thread/unsubscribe', method = 'POST' }, api_thread_unsubscribe)
--server:route({ path = '/db/api/thread/update', method = 'POST' }, api_thread_update)
--server:route({ path = '/db/api/thread/vote', method = 'POST' }, api_thread_vote)

-- post
local api_post_create -- https://github.com/andyudina/technopark-db-api/blob/master/doc/post/create.md
local api_post_details -- https://github.com/andyudina/technopark-db-api/blob/master/doc/post/details.md
local api_post_list -- https://github.com/andyudina/technopark-db-api/blob/master/doc/post/list.md
local api_post_remove -- https://github.com/andyudina/technopark-db-api/blob/master/doc/post/remove.md
local api_post_restore -- https://github.com/andyudina/technopark-db-api/blob/master/doc/post/restore.md
local api_post_update -- https://github.com/andyudina/technopark-db-api/blob/master/doc/post/update.md
local api_post_vote -- https://github.com/andyudina/technopark-db-api/blob/master/doc/post/vote.md

--server:route({ path = '/db/api/post/create', method = 'POST' }, api_post_create)
--server:route({ path = '/db/api/post/details', method = 'GET' }, api_post_details)
--server:route({ path = '/db/api/post/list', method = 'GET' }, api_post_list)
--server:route({ path = '/db/api/post/remove', method = 'POST' }, api_post_remove)
--server:route({ path = '/db/api/post/restore', method = 'POST' }, api_post_restore)
--server:route({ path = '/db/api/post/update', method = 'POST' }, api_post_update)
--server:route({ path = '/db/api/post/vote', method = 'POST' }, api_post_vote)

-- -- --

server:hook('before_dispatch', function(self, request)
    local obj = {}
    if request.method ~= 'GET' then
        local status, err = pcall(function() obj.json = request:json() end)
        if not obj.json then
            obj.response = create_response(ResultCode.BadRequest, err)
        end
    else
        obj.query_params = request:query_param(nil)
    end
    return obj
end)
server:hook('after_handler_error', function(self, request, request_override, err)
    return create_response(ResultCode.UnknownError, err)
end)
server:hook('after_dispatch', function(self, request, request_override, response_data)
    return request:render({ json = response_data })
end)

server:start()
