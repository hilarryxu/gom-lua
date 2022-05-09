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
  allow_items_desc = '|250#���꽣�ס��������Ρ����½���',
  allow_item_names = {
    ['����'] = true,
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
    s = [[<  %02d��/FCOLOR=249> %s������<װ�����֣�/FCOLOR=250>%-14s  <װ��Idx��/FCOLOR=254>%10s  %s \\]]
    tinsert(form, str_fmt(s,
      i,
      iif(make_index,
          str_fmt("<�����¼/@LBL_�����¼(%d)>", i),
          str_fmt("<ȷ�ϼ�¼/@LBL_ȷ�ϼ�¼(%d)>", i)),
      name or "",
      make_index or "",
      iif(make_index,
          str_fmt("����<�����Ʒ/@LBL_�����Ʒ(%d,%s)>", i, make_index or "0"),
          "")
    ))
  end

  local _, _, N20 = npc:get_var(params.player, "N20")
  tinsert(form, [[\\]])
  tinsert(form, [[������������������<1. /FCOLOR=239><װ����������ͨ������¼װ����[/FCOLOR=95><Idx/FCOLOR=249><]�������ѯ��˭������ (������һع�)/FCOLOR=95> \\]])
  tinsert(form, [[������������������<2. /FCOLOR=239><��Ҫ��¼��װ���������[/FCOLOR=95><װ����/FCOLOR=249><]�У�Ȼ�����Ϸ���Ӧλ�õ�[/FCOLOR=95><ȷ�ϼ�¼/FCOLOR=249><]��ť/FCOLOR=95> \\]])
  tinsert(form, [[������������������<3. /FCOLOR=239><ע�⣺/FCOLOR=249><װ�������,��ͨ������;��ȡ�غ��������[/FCOLOR=253><ȷ�ϼ�¼/FCOLOR=249><]һ��,������Ч!/FCOLOR=253>\\]])
  tinsert(form, [[\\]])
  tinsert(form, str_fmt([[������������������<�����¼�б�/FCOLOR=250> �� <�鿴�б�%s/FCOLOR=125>����<װ��Idx��/FCOLOR=70> %s\\]],
      cfg.allow_items_desc,
      iif(N20 > 0, N20, "")
  ))
  tinsert(form, [[\\]])
  tinsert(form, str_fmt([[��������������<��ѯ/@LBL_��ѯ>         %s         <һ����¼/@LBL_һ����¼>         <��ռ�¼/@LBL_��ռ�¼>\\]],
      iif(N20 > 0, "<��ѯ��װ��/FCOLOR=10>", "<������Idx/@@InPutInteger20(��������Ҫ��ѯ��װ��Idx...)>")
  ))
  tinsert(form, [[<ITEMBOX:0:21:141:10:-122:70:70:*:250#�����Ҫ��¼��װ��^254#Ȼ�����Ϸ���Ӧλ��^254#���[ȷ�ϼ�¼]��ť^151#��������Ϣ,ֱ���滻>\\]])

  npc:set_var(params.player, saved_var_name, tconcat(form, line_prefix))
  npc:set_var(params.player, "N70", OKAY)
end


-- add_record(λ��, װ��Idx, װ������)
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


-- del_record(λ��)
function _M.del_record(params)
  assert(params.argc == 3)
  local index = tonumber(params.s3)

  local uid = m2.player_get_uid(params.player)
  local db = m2.vedis_db

  db:exec("BEGIN")
  db:execute("HDEL u_uir:%s midx_%d name_%d", uid, index, index)
  db:exec("COMMIT")
end


-- check_allow_item(װ������, ����ֵ)
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

  local useritems = player.useritems  -- ���ϵ�װ���б�
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


-- search_record(װ��Idx, rc, err_msg)
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
    err_msg = str_fmt("װ��Idx���к�[%d]��δ�Ǽǣ��޷���ѯ", make_index)
    npc:set_var(params.player, var_err_msg, err_msg)
    return
  end

  db:execute("HGET %s %d", KEY_RECORDED_ITEM_PICKUP_LOG, make_index)
  res = db:exec_result()
  if res:is_null() then
    npc:set_var(params.player, var_rc, 2)
    err_msg = str_fmt("װ��Idx���к�[%d]�����κ����ݼ�¼���޷���ѯ", make_index)
    npc:set_var(params.player, var_err_msg, err_msg)
    return
  end

  err_msg = res:to_string()
  npc:set_var(params.player, var_rc, OKAY)
  npc:set_var(params.player, var_err_msg, err_msg)
end


-- on_pickup_item(װ��Idx)
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
  -- ������δ��¼����װ��
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
  -- ���Լ���¼����װ����ֱ�������������ظ���¼
  if found then return end
  --]]

  local log_msg = [[��־��װ�����֡�<$CURRTEMNAME>����װ��Idx��<$CURRTEMMAKEINDEX>������ȡ�ˡ�<$USERNAME>�����л᡾<$GUILDNAME>������ȡ�ص㡾<$MapTitle>(<$X>:<$Y>)������ȡʱ�䡾<$NN_DATETIME>��]]
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
