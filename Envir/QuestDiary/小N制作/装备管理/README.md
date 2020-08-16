## 安装

```lua
-- MerChant.txt 中添加一个NPC
小N制作\装备管理 3 341 330 装备管理 0 208 0

-- Market_Def\小N制作\装备管理-3.txt
#CALL [\小N制作\装备管理\npc.txt] @NPC

-- QFunction-0.txt 中添加拾取触发
[@PickUpItemEx]
#CALL [\小N制作\装备管理\npc.txt] @捡取触发
```
