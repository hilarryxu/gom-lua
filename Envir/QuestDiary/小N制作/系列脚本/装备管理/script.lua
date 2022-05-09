local ffi = require"ffi"
local string = require"string"
local table = require"table"
local math = require"math"

local m2 = require"luamir"
local m2_utils = require"luamir.utils"

local ffi_cast = ffi.cast
local ffi_str = ffi.string
local iif = m2_utils.iif
local str_upper = string.upper
local str_fmt = string.format
local str_trim = m2_utils.str_trim
local str_startswith = m2_utils.str_startswith
local str_explode = m2_utils.str_explode
local tinsert = table.insert
local tconcat = table.concat
local unpack = unpack or table.unpack
local _p = m2.printf

local OKAY = 0
local RC_ERR = 1

local KEY_RECORDED_ITEMS = "recorded_items"
local KEY_RECORDED_ITEM_PICKUP_LOG = "rip_log"

local _M = {}

local cfg = {
  max_record_nr = 17,
  allow_items_desc = '|250#祖玛剑甲、赤月首饰、赤月剑甲',
  allow_item_names = {
    ['屠龙'] = true,
  },
}


local function vdb_result_to_list(res)
  if res:is_null() then return {} end

  assert(res:is_array())
  local out = {}
  local elem = res:array_next_elem()
  while elem ~= nil do
    if elem:is_null() then
      tinsert(out, false)
    else
      tinsert(out, elem:to_string())
    end
    elem = res:array_next_elem()
  end

  return out
end


local function check_item_can_record(item_name, useritem, stditem)
  -- return cfg.allow_item_names[item_name] == true
  return true
end


-- build_form()
function _M.build_form(params)
  assert(params.argc >= 3)
  local saved_var_name = params.raw_s3
  local line_prefix = params.s4 or ""

  local npc = ffi_cast("TNormNpc*", params.npc)
  local uid = m2.player_get_uid(params.player)
  local db = m2.vedis_db

  local form = { [[\\]] }
  local s
  for i = 1, cfg.max_record_nr do
    db:execute("HMGET u_uir:%s midx_%d name_%d", uid, i, i)
    local make_index, name = unpack(vdb_result_to_list(db:exec_result()))
    s = [[<  %02d、/FCOLOR=249> %s　→　<装备名字：/FCOLOR=250>%-14s  <装备Idx：/FCOLOR=254>%10s  %s \\]]
    tinsert(form, str_fmt(s,
      i,
      iif(make_index,
          str_fmt("<清除记录/@LBL_清除记录(%d)>", i),
          str_fmt("<确认记录/@LBL_确认记录(%d)>", i)),
      name or "",
      make_index or "",
      iif(make_index,
          str_fmt("　　<查此物品/@LBL_查此物品(%d,%s)>", i, make_index or "0"),
          "")
    ))
  end

  local _, _, N20 = npc:get_var(params.player, "N20")
  tinsert(form, [[\\]])
  tinsert(form, [[　　　　　　　　　<1. /FCOLOR=239><装备掉落后可以通过所记录装备的[/FCOLOR=95><Idx/FCOLOR=249><]编号来查询被谁捡走了 (便于玩家回购)/FCOLOR=95> \\]])
  tinsert(form, [[　　　　　　　　　<2. /FCOLOR=239><将要记录的装备放入左边[/FCOLOR=95><装备框/FCOLOR=249><]中，然后点击上方对应位置的[/FCOLOR=95><确认记录/FCOLOR=249><]按钮/FCOLOR=95> \\]])
  tinsert(form, [[　　　　　　　　　<3. /FCOLOR=239><注意：/FCOLOR=249><装备掉落后,再通过其他途径取回后必须重新[/FCOLOR=253><确认记录/FCOLOR=249><]一次,否则无效!/FCOLOR=253>\\]])
  tinsert(form, [[\\]])
  tinsert(form, str_fmt([[　　　　　　　　　<允许记录列表/FCOLOR=250> → <查看列表%s/FCOLOR=125>　　<装备Idx：/FCOLOR=70> %s\\]],
      cfg.allow_items_desc,
      iif(N20 > 0, N20, "")
  ))
  tinsert(form, [[\\]])
  tinsert(form, str_fmt([[　　　　　　　<查询/@LBL_查询>         %s         <一键记录/@LBL_一键记录>         <清空记录/@LBL_清空记录>\\]],
      iif(N20 > 0, "<查询的装备/FCOLOR=10>", "<请输入Idx/@@InPutInteger20(请输入您要查询的装备Idx...)>")
  ))
  tinsert(form, [[<ITEMBOX:0:21:141:10:-122:70:70:*:250#请放入要记录的装备^254#然后在上方对应位置^254#点击[确认记录]按钮^151#如已有信息,直接替换>\\]])

  npc:set_var(params.player, saved_var_name, tconcat(form, line_prefix))
  npc:set_var(params.player, "N70", OKAY)
end


-- add_record(位置, 装备Idx, 装备名称)
function _M.add_record(params)
  assert(params.argc >= 5)
  local index, make_index, item_name = tonumber(params.s3), tonumber(params.s4), params.s5

  -- local npc = ffi_cast("TNormNpc*", params.npc)
  local uid = m2.player_get_uid(params.player)
  local db = m2.vedis_db

  if make_index ~= nil and make_index > 0 then
    -- local stditem = m2.get_stditem_by_name(item_name)
    if check_item_can_record(item_name) then
      db:exec("BEGIN")
      db:execute("HMSET u_uir:%s midx_%d %d name_%d %q",
                  uid, index, make_index,
                  index, item_name)
      db:execute("SADD %s %d", KEY_RECORDED_ITEMS, make_index)
      db:exec("COMMIT")
    end
  end
end


-- del_record(位置)
function _M.del_record(params)
  assert(params.argc == 3)
  local index = tonumber(params.s3)

  local uid = m2.player_get_uid(params.player)
  local db = m2.vedis_db

  db:exec("BEGIN")
  db:execute("HDEL u_uir:%s midx_%d name_%d", uid, index, index)
  db:exec("COMMIT")
end


-- check_allow_item(装备名称, 返回值)
function _M.check_allow_item(params)
  assert(params.argc == 4)
  local item_name, var_rc = params.s3, params.raw_s4

  local npc = ffi_cast("TNormNpc*", params.npc)
  if check_item_can_record(item_name) then
    npc:set_var(params.player, var_rc, OKAY)
  else
    npc:set_var(params.player, var_rc, RC_ERR)
  end
end

-- record_all()
function _M.record_all(params)
  local player = ffi_cast("TPlayObject*", params.player)

  local uid = m2.player_get_uid(params.player)
  local db = m2.vedis_db

  local useritems = player.useritems  -- 身上的装备列表
  db:exec("BEGIN")
  for index = 1, math.min(m2.C.U_SWEAPON + 1, cfg.max_record_nr) do
    local useritem = useritems[index - 1]
    local make_index = useritem.make_index
    local idx = useritem.idx
    if make_index > 0 and idx > 0 then
      local stditem = m2.get_stditem_by_idx(useritem.idx)
      local item_name = ffi_str(stditem.name, stditem.name_len)
      if check_item_can_record(item_name, useritem, stditem) then
        db:execute("HMSET u_uir:%s midx_%d %d name_%d %q",
                    uid, index, make_index,
                    index, item_name)
        db:execute("SADD %s %d", KEY_RECORDED_ITEMS, make_index)
      end
    end
  end
  db:exec("COMMIT")
end


-- clear_all()
function _M.clear_all(params)
  local uid = m2.player_get_uid(params.player)
  local db = m2.vedis_db

  db:exec("BEGIN")
  for index = 1, cfg.max_record_nr do
    db:execute("HDEL u_uir:%s midx_%d name_%d", uid, index, index)
  end
  db:exec("COMMIT")
end


-- search_record(装备Idx, rc, err_msg)
function _M.search_record(params)
  assert(params.argc == 5)
  local make_index, var_rc, var_err_msg = tonumber(params.s3), params.raw_s4, params.raw_s5

  local npc = ffi_cast("TNormNpc*", params.npc)
  local db = m2.vedis_db
  local res, err_msg

  db:execute("SISMEBER %s %d", KEY_RECORDED_ITEMS, make_index)
  res = db:exec_result()
  local did_recorded = res:to_bool()
  if not did_recorded then
    npc:set_var(params.player, var_rc, 1)
    err_msg = str_fmt("装备Idx序列号[%d]并未登记，无法查询", make_index)
    npc:set_var(params.player, var_err_msg, err_msg)
    return
  end

  db:execute("HGET %s %d", KEY_RECORDED_ITEM_PICKUP_LOG, make_index)
  res = db:exec_result()
  if res:is_null() then
    npc:set_var(params.player, var_rc, 2)
    err_msg = str_fmt("装备Idx序列号[%d]并无任何数据记录，无法查询", make_index)
    npc:set_var(params.player, var_err_msg, err_msg)
    return
  end

  err_msg = res:to_string()
  npc:set_var(params.player, var_rc, OKAY)
  npc:set_var(params.player, var_err_msg, err_msg)
end


-- on_pickup_item(装备Idx)
function _M.on_pickup_item(params)
  assert(params.argc == 3)
  local arg_make_index = tonumber(params.s3)
  -- _p("on_pickup_item(%s)", arg_make_index)

  local npc = ffi_cast("TNormNpc*", params.npc)
  local uid = m2.player_get_uid(params.player)
  local db = m2.vedis_db
  local res

  db:execute("SISMEBER %s %d", KEY_RECORDED_ITEMS, arg_make_index)
  res = db:exec_result()
  local did_recorded = res:to_bool()
  -- 不处理未记录过的装备
  if not did_recorded then return end

  --[[
  local found = false
  for i = 1, cfg.max_record_nr do
    db:execute("HMGET u_uir:%s midx_%d name_%d", uid, i, i)
    local make_index, _ = unpack(vdb_result_to_list(db:exec_result()))
    if make_index and tonumber(make_index) == arg_make_index then
      found = true
      break
    end
  end
  -- 捡到自己记录过的装备，直接跳过，避免重复记录
  if found then return end
  --]]

  local log_msg = [[日志：装备名字【<$CURRTEMNAME>】　装备Idx【<$CURRTEMMAKEINDEX>】　捡取人【<$USERNAME>】　行会【<$GUILDNAME>】　捡取地点【<$MapTitle>(<$X>:<$Y>)】　捡取时间【<$NN_DATETIME>】]]
  log_msg = log_msg:gsub("(<%$[%w_]+>)", function (name)
    return npc:get_line_variable_text(params.player, name) or ""
  end)

  db:exec("BEGIN")
  -- db:execute("SREM %s %d", KEY_RECORDED_ITEMS, arg_make_index)
  db:execute("HSET %s %d %q", KEY_RECORDED_ITEM_PICKUP_LOG,
             arg_make_index, log_msg)
  db:exec("COMMIT")
end


return _M
