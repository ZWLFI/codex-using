# GPT 用量

原生 macOS 菜单栏 Codex / ChatGPT 用量仪表盘。通过本地 `codex app-server` 读取官方配额与每日 token 数据，不读取 cookie、OAuth token 或 API key。

## 功能

- 多配额桶、剩余百分比、重置倒计时和重置券
- 官方日 token 趋势、7/30/90 日历史和汇总指标
- 消耗速率、耗尽预测和风险状态
- 阈值、重置、预测和读取失败通知
- 离线缓存、CSV/JSON 导出、脱敏诊断和开机启动
- 不裁剪的双行菜单栏读数、原生毛玻璃弹窗和自适应深浅色

## 构建与安装

```bash
./build.sh
./install.sh
```

`install.sh` 会在覆盖 `/Applications/GPT 用量.app` 前备份旧应用和偏好数据。

