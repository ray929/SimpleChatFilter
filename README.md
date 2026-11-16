# SimpleChatFilter

## English

**SimpleChatFilter hides chat lines that contain keywords you blacklist, and keeps a record of what it hid.**

### Features

- Keyword blacklist: add a line, tick or untick it, delete it. Matching ignores spaces and ASCII symbols, so `LFG` also catches `L F G`, `L-F-G` and `L.F.G`. Separate words with spaces to require all of them, in any order: `Panda exp` catches a line that contains both panda and exp.
- Per-channel ticks: say, yell and custom channels are ticked by default; whispers, party, raid, instance, guild, officer, battleground and emotes are off by default. System and loot lines are not offered at all — they share strings with drops, errors and invites.
- Custom channels are listed by name, so you can filter one public channel and leave another alone. City channels (General, Trade) are filtered by the custom-channel switch but are not listed.
- A blocked-message log page inside the game settings: newest first, paged, one line per message with time, channel, sender, matched keyword and the original text.
- Clearing: a two-step "clear all" button, plus automatic cleanup by age (default one month) and by count (default 2000 entries), each switchable on its own.
- A minimap button: left click opens the options page, right click opens the blocked log, middle click toggles filtering. Drag it around the minimap; it snaps to the ring and remembers where you put it. It can be hidden in the options page.
- A master switch and a "log only, do not hide" mode for trying keywords out.
- Works on top of chat-replacement addons that respect the standard chat message filter chain.
- English, Simplified Chinese and Traditional Chinese interface, following the client language. The language is a drop-down; picking a different one asks whether to reload the UI right away.

## 简体中文

**SimpleChatFilter 把含有你设定关键词的聊天行屏蔽掉，并且留下一份"屏蔽了什么"的记录。**

### 功能

- 关键词黑名单：加一行、逐条启停、删除。匹配时忽略空格与 ASCII 符号，所以写 `打手` 也能拦住 `打 手`、`打~手`、`打.手`。用空格隔开多个词表示“同时包含”，顺序不限：`Panda exp` 会拦住同时出现 panda 与 exp 的行。
- 按频道勾选：默认勾说话、大喊、自建频道；密语、小队、团队、副本、公会、官员、战场、表情默认不勾。系统与拾取这类行不提供勾选项——它们与掉落、错误、邀请提示共用同一套字符串。
- 自建频道按名字列出，可以只过滤某个公共频道、放过另一个。城市/区域频道（综合、交易）照旧受「自建频道」总开关过滤，但不会列进明细。
- 游戏设置里有一个「屏蔽日志」页：按时间倒序分页显示，每条包含时间、频道（自建频道带具体频道名）、发言人、命中的关键词和原文。
- 清理：两步确认的「全部清理」，以及按时间（默认一个月）和按条数（默认 2000 条）的自动清理，两个开关各自独立。
- 小地图按钮：左键打开选项页，右键打开屏蔽日志，中键切换总开关；按住左键可绕小地图拖动，松手吸附到圆环并记住位置，可在选项页隐藏。
- 总开关、「仅记录不屏蔽」试用模式。
- 在尊重标准聊天消息过滤器链的聊天美化/替换插件上正常工作。
- 英文、简体中文、正体中文界面，跟随客户端语言；语言是下拉菜单，选了与当前不同的一项会问要不要立刻重载界面。

## 正体中文

**SimpleChatFilter 會把含有你設定關鍵字的聊天行遮蔽掉，並留下一份「遮蔽了什麼」的紀錄。**

### 功能

- 關鍵字黑名單：新增一行、逐條啟停、刪除。比對時忽略空白與 ASCII 符號，所以寫 `打手` 也能攔下 `打 手`、`打~手`、`打.手`。用空白隔開多個詞表示「同時包含」，順序不限：`Panda exp` 會攔下同時出現 panda 與 exp 的列。
- 依頻道勾選：預設勾說話、大喊、自建頻道；密語、小隊、團隊、副本、公會、幹部、戰場、表情預設不勾。系統與拾取這類行不提供勾選項——它們與掉落、錯誤、邀請提示共用同一套字串。
- 自建頻道依名稱列出，可以只過濾某個公共頻道、放過另一個。城市／區域頻道（綜合、交易）照舊受「自建頻道」總開關過濾，但不會列進明細。
- 遊戲設定裡有一個「遮蔽紀錄」頁：依時間倒序分頁顯示，每筆包含時間、頻道（自建頻道帶具體頻道名）、發言人、命中的關鍵字與原文。
- 清理：兩步確認的「全部清理」，以及依時間（預設一個月）與依筆數（預設 2000 筆）的自動清理，兩個開關各自獨立。
- 小地圖按鈕：左鍵開啟選項頁，右鍵開啟遮蔽紀錄，中鍵切換總開關；按住左鍵可繞小地圖拖動，放開後吸附到圓環並記住位置，可在選項頁隱藏。
- 總開關、「僅記錄不遮蔽」試用模式。
- 在尊重標準聊天訊息過濾器鏈的聊天美化／替換插件上正常工作。
- 英文、簡體中文、正體中文介面，跟隨客戶端語言；語言是下拉選單，選了與目前不同的一項會問要不要立刻重新載入介面。
