# 接口文档同步

- 来源：AiRec-Rec 的 `docs/CLIENT_API.md`。
- 2026-09-12：增加简明速查，完整协议未修改；三份副本一致。
- SHA256：`0f9d234e16688180cf78d7b0b8a7935f58cab714adb28aa205e42c86baab8504`。
- 客户端通过 HTTP 通信，构建不读取服务端仓库。

<details>
<summary>查看历史同步记录</summary>

# HTTP 接口说明同步来源

CLIENT_API.md 是本仓库独立副本，可随鸿蒙工程单独克隆与提交，构建不读取相邻 Android 或 Ubuntu 目录。

- 同步日期：2026-09-08。
- 来源：Ubuntu 服务端仓库 docs/CLIENT_API.md。
- 当前工作区来源位置：C:\Users\pjz\Desktop\rk3399-project\AiRec-Rec\docs\CLIENT_API.md，仅记录来源，不作为构建依赖。
- 权威实现：服务端 web/server.py、core/config.py 与业务模块。
- 接口变化后核对服务端并更新来源文档，再复制至本仓库；同步 Models.ets、JsonCodec.ets、RecorderApi.ets，执行受影响原生逻辑与接口测试。
- 尚未指定远程仓库地址或提交号，不虚构版本来源；独立提交后可补充服务端版本或提交。

本轮同步新增 /api/timeline：完整窗口最多分别 10000 条候选录像/事件、响应最多 2MiB，超限 HTTP422；窗口统一 UTC 回传，录像保留原起点和时长，事件已经裁剪合并。全局原列表的最近 200 条限制保持。完整配置差异合并、媒体同源和缺失遥测语义不变。

- 本轮协议副本 SHA256：affe9eae40ff035ec9ddd7fd20604e0a73fe584a26a10880e196334eea4e3805。

- 2026-09-09：工程迁入 AiRec 系列仓库，仅更新目录名称与本文档摘要，HTTP 协议不变。

</details>
