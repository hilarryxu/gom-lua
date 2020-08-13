-- LUA�ű�
local mir = require"mir"
local ffi = require"ffi"
local string = require"string"
local table = require"table"
local math = require"math"

local ffi_cast = ffi.cast
local ffi_str = ffi.string
local str_fmt = string.format
local unpack = unpack or table.unpack
local tinsert = table.insert
local iif = mir.iif
-- local _p = mir.printf

local _M = {
  max_record_useritem_nr = 15,
  allow_items_desc = '|250#���꽣�ס��������Ρ����½���',
  allow_item_names = {
    ['����'] = true,
  },
}

local KEY_RECORDED_ITEMS = "recorded_items"
local KEY_RECORDED_ITEM_PICKUP_LOG = "rip_log"

local function item_can_record(item_name, useritem, stditem)
  return _M.allow_item_names[item_name] == true
end

local function res_to_list(res)
  assert(res:is_array())
  local out = {}
  local elem = res:array_next_elem()
  while elem ~= nil do
    if elem:is_null() then
      tinsert(out, nil)
    else
      tinsert(out, elem:to_string())
    end
    elem = res:array_next_elem()
  end
  return out
end

function _M.add_record(params)
  local index = tonumber(params.s3)

  local player = ffi_cast("TPlayObject*", params.player)
  local uid = mir.player_get_uid(params.player)
  local db = mir.vedis_db

  local useritem = player.useritems[index - 1]
  if useritem.make_index > 0 then
    local stditem = mir.get_stditem_by_idx(useritem.index)
    local item_name = ffi_str(stditem.name)
    if item_can_record(item_name, useritem, stditem) then
      db:exec("BEGIN")
      db:execute("HMSET u_uir:%s i%d %d n%d \"%s\"",
                  uid, index, useritem.make_index,
                  index, item_name)
      db:execute("SADD %s %d", KEY_RECORDED_ITEMS, useritem.make_index)
      db:exec("COMMIT")
    end
  end
end

function _M.del_record(params)
  local index = tonumber(params.s3)

  local uid = mir.player_get_uid(params.player)
  local db = mir.vedis_db

  db:exec("BEGIN")
  db:execute("HDEL u_uir:%s i%d n%d", uid, index, index)
  db:exec("COMMIT")
end

function _M.clear_all(params)
  local uid = mir.player_get_uid(params.player)
  local db = mir.vedis_db

  db:exec("BEGIN")
  for index = 1, _M.max_record_useritem_nr do
    db:execute("HDEL u_uir:%s i%d n%d", uid, index, index)
  end
  db:exec("COMMIT")
end

function _M.record_all(params)
  local player = ffi_cast("TPlayObject*", params.player)
  local uid = mir.player_get_uid(params.player)
  local db = mir.vedis_db

  local useritems = player.useritems
  db:exec("BEGIN")
  for index = 1, math.min(mir.C.U_SWEAPON + 1, _M.max_record_useritem_nr) do
    local useritem = useritems[index - 1]
    if useritem.make_index > 0 then
      local stditem = mir.get_stditem_by_idx(useritem.index)
      local item_name = ffi_str(stditem.name)
      if item_can_record(item_name, useritem, stditem) then
        db:execute("HMSET u_uir:%s i%d %d n%d \"%s\"",
                    uid, index, useritem.make_index,
                    index, item_name)
        db:execute("SADD %s %d", KEY_RECORDED_ITEMS, useritem.make_index)
      end
    end
  end
  db:exec("COMMIT")
end

function _M.on_pickup_item(params)
  local arg_make_index = tonumber(params.s3)

  -- local npc = ffi_cast("TNormNpc*", params.npc)
  local uid = mir.player_get_uid(params.player)
  local db = mir.vedis_db
  local res

  db:execute("SISMEBER %s %d", KEY_RECORDED_ITEMS, arg_make_index)
  res = db:exec_result()
  local did_recorded = res:to_bool()
  if not did_recorded then return end

  local found = false
  for i = 1, _M.max_record_useritem_nr do
    db:execute("HMGET u_uir:%s i%d n%d", uid, i, i)
    local make_index, _ = unpack(res_to_list(db:exec_result()))
    if make_index and tonumber(make_index) == arg_make_index then
      found = true
      break
    end
  end
  if found then return end

  local log_msg = [[��־��װ�����֡�<$CURRTEMNAME>�� װ��Idx��<$CURRTEMMAKEINDEX>�� ��ȡ�ˡ�<$USERNAME>�� �л᡾<$GUILDNAME>�� ��ȡ�ص㡾<$MapTitle>(<$X>:<$Y>)�� ��ȡʱ�䡾<$TIME>��]]

  db:exec("BEGIN")
  db:execute("SREM %s %d", KEY_RECORDED_ITEMS, arg_make_index)
  db:execute('HSET %s %d "%s"', KEY_RECORDED_ITEM_PICKUP_LOG,
             arg_make_index, log_msg)
  db:exec("COMMIT")
end

function _M.search_record(params)
  local make_index, var_code, var_msg = tonumber(params.s3), params.raw_s4, params.raw_s5

  local npc = ffi_cast("TNormNpc*", params.npc)
  local db = mir.vedis_db
  local res, msg

  db:execute("SISMEBER %s %d", KEY_RECORDED_ITEMS, make_index)
  res = db:exec_result()
  local did_recorded = res:to_bool()
  if not did_recorded then
    npc:set_var(params.player, var_code, 1)
    msg = str_fmt("װ��Idx���к�[%d]��δ�Ǽǣ��޷���ѯ", make_index)
    npc:set_var(params.player, var_msg, msg)
    return
  end

  db:execute("HGET %s %d", KEY_RECORDED_ITEM_PICKUP_LOG, make_index)
  res = db:exec_result()
  if res:is_null() then
    npc:set_var(params.player, var_code, 2)
    msg = str_fmt("װ��Idx���к�[%d]�����κ����ݼ�¼���޷���ѯ", make_index)
    npc:set_var(params.player, var_msg, msg)
    return
  end

  msg = res:to_string()
  npc:set_var(params.player, var_code, 0)
  npc:set_var(params.player, var_msg, msg)
end

function _M.build_form(params)
  local var_name = params.raw_s3 or "S0"

  local npc = ffi_cast("TNormNpc*", params.npc)
  local uid = mir.player_get_uid(params.player)
  local db = mir.vedis_db

  local form = { [[ \]] }
  local s
  for i = 1, _M.max_record_useritem_nr do
    db:execute("HMGET u_uir:%s i%d n%d", uid, i, i)
    local make_index, name = unpack(res_to_list(db:exec_result()))
    s = [[<  %02d��/FCOLOR=249> %s������<װ�����֣�/FCOLOR=250>%-14s  <װ��Idx��/FCOLOR=254>%10s  %s\]]
    tinsert(form, str_fmt(s,
      i,
      iif(make_index,
          str_fmt("<�����¼/@LB_�����¼(%d)>", i),
          str_fmt("<ȷ�ϼ�¼/@LB_ȷ�ϼ�¼(%d)>", i)),
      name or "",
      make_index or "",
      iif(make_index,
          str_fmt("<�����Ʒ/@LB_�����Ʒ(%d,%s)>", i, make_index or "0"))
    ))
  end

  local _, _, N0 = npc:get_var(params.player, "N0")
  tinsert(form, str_fmt([[ \
������������������<1. /FCOLOR=239>װ���������ͨ������¼װ����[<Idx/FCOLOR=249>]�������ѯ��˭��ȡ (������ҹ���)\
������������������<2. /FCOLOR=239>��Ҫ��¼��װ���������[<װ����/FCOLOR=249>]�У�Ȼ�����Ϸ���Ӧλ�õ�[<ȷ�ϼ�¼/FCOLOR=249>]��ť\
������������������<3. /FCOLOR=239><ע�⣺/FCOLOR=249><װ�������,��ͨ������;��ȡ�غ��������[/FCOLOR=253><ȷ�ϼ�¼/FCOLOR=249><]һ��,������Ч!/FCOLOR=253>\
 \
������������������<�����¼�б�/FCOLOR=250> �� <�鿴�б�%s>/FCOLOR=125>����<װ��Idx��/FCOLOR=70> %s\
 \
��<��ѯ/@LB_��ѯ>         %s         <һ����¼/@LB_һ����¼>         <��ռ�¼/@LB_��ռ�¼>\
<ITEMBOX:0:21:160:10:-122:70:70:*:250#�����Ҫ��¼��װ��^254#Ȼ�����Ϸ���Ӧλ��^254#���[ȷ�ϼ�¼]��ť^151#������Ϣ,ֱ���滻>\
]],
      _M.allow_items_desc,
      iif(N0 > 0, N0),
      iif(N0 > 0, "<��ѯ��װ��/FCOLOR=10>", "<������Idx/@@InPutInteger0(��������Ҫ��ѯ��װ��Idx...)>")
  ))

  npc:set_var(params.player, var_name, table.concat(form))
end

return _M

-- vim: set et fenc=cp936 ff=dos sts=2 sw=2 ts=2 :
