# devlog-tracker

在專案中維護一份 `.devlog/devlog.md`，把每一輪對話的請求、決策與結果寫成永久紀錄。
參考 [agfnow/agentflow](https://github.com/agfnow/agentflow) 的 devlog 基礎協定做的簡化版，
只保留「逐輪對話紀錄」這一層。

## 特色

- **`/devlog-tracker:start` 明確開啟強制記錄**：建立 `.devlog/.enabled` 開關檔，之後 `Stop` hook 會卡住
  每一輪的結束動作，這一輪沒寫 `devlog.md` 就不能結束——不依賴 Claude 自行判斷「值不值得
  記錄」，也跟任務/plan 是否完成無關。沒下過 `/devlog-tracker:start` 的專案完全不受影響。
- **`/devlog-tracker:pause`**：暫停強制記錄，歷史紀錄不受影響，之後可再用 `/devlog-tracker:start` 重新啟動。
- **自動接續**：`SessionStart` hook，`/clear`、resume、開新 session 時自動讀取
  `.devlog/devlog.md` 最後幾輪並注入 context，不用手動喊指令。
- **`/devlog-tracker:compact`**：手動把已完成的舊輪次搬到 `devlog.archive.md`，避免主檔案無限膨脹。
- **格式固定**：每輪都是 `User Input`（貼近原話，保留彈性）/ `Response` / `Status`（`DONE` / `IN_PROGRESS` / `BLOCKED`）三段式，讀檔案就能還原對話重點，不用翻對話紀錄。

## 安裝

作為 Claude Code plugin 安裝（會自動更新）：

```
/plugin marketplace add <your-github-handle>/devlog-tracker
/plugin install devlog-tracker@devlog-tracker
```

## 使用

在專案裡下一次：

```
/devlog-tracker:start
```

之後正常跟 Claude 對話即可，每一輪結束前都會被強制檢查、補上 `.devlog/devlog.md` 的紀錄。

暫停強制記錄：

```
/devlog-tracker:pause
```

累積輪數變多、檔案太長時：

```
/devlog-tracker:compact
```

（以上都是完整的 namespace 形式，plugin 名稱是 `devlog-tracker`。）

## 目錄結構

```
devlog-tracker/
├── .claude-plugin/
│   ├── plugin.json        # plugin manifest
│   └── marketplace.json   # 讓這個 repo 本身就是一個 marketplace
├── skills/devlog-tracker/SKILL.md
├── hooks/
│   ├── hooks.json                       # SessionStart / UserPromptSubmit / Stop
│   └── scripts/
│       ├── session-start-devlog.sh      # 自動接續
│       ├── round-start.sh               # 記錄每輪開始時 devlog.md 的內容雜湊
│       ├── enforce-devlog.sh            # 強制每輪結束前要寫 devlog
│       └── test-enforce-devlog.sh       # 上面兩支腳本的自我檢查
└── commands/
    ├── start.md            # 開啟強制記錄
    ├── pause.md            # 暫停強制記錄
    └── compact.md          # 壓縮歸檔
```

## License

Apache-2.0
