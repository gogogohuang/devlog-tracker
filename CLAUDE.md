# CLAUDE.md

## 版號規則

每次有實質變更合併進 `main`（新功能、行為變更、bug fix；純文件/註解修正除外）時，都要 bump 版號，三個檔案同步改成同一個版本字串：

- `.claude-plugin/plugin.json` → `"version"`
- `.claude-plugin/marketplace.json` → `plugins[0].version`
- `README.md` → 開頭的 `**版本** X.Y.Z` 那行

版號規則（semver 精神，實際上幾乎都是 minor bump）：
- 新功能／行為變更 → bump minor（`0.14.0` → `0.15.0`）
- 單純修 CI/測試/typo 等不影響行為的小補丁 → 可以跟下一個 minor bump 一起處理，不必單獨開版號 commit

Bump 用獨立的 commit，訊息格式：

```
chore: bump to X.Y.Z

一句話說明這次 bump 對應的變更。
```

改完用這段驗證三個檔案版號一致再 commit：

```bash
python3 - <<'PY'
import json
from pathlib import Path
v = "X.Y.Z"  # 換成目標版號
p = json.loads(Path(".claude-plugin/plugin.json").read_text())
m = json.loads(Path(".claude-plugin/marketplace.json").read_text())
assert p["version"] == v, p["version"]
assert m["plugins"][0]["version"] == v, m["plugins"][0]["version"]
assert f"**版本** {v}" in Path("README.md").read_text(), "README version line"
print("PASS:", v)
PY
```
