# 项目规则

- 使用 [开发说明](DEVELOPMENT.md#从源码构建) 中的检查和发布流程。App 改动在本机运行 `./script/check.sh`，GitHub 的 PR 检查负责核对发版信息。
- 向 `main` 提交会改变安装包的 PR 时，以最新的 `main` 和远程标签为准，在同一条 PR 中更新 `script/build_and_run.sh` 的 App 版本号和构建号，并在 `CHANGELOG.md` 添加对应版本的用户可见改动。同一条 PR 的补充提交沿用计划版本。合并后由 Actions 打包并发布。
- 文档、测试和 CI 维护可以在当前 App 版本上合并。App 输入由 `.github/release/plan.py` 检查。
- 本仓库分支提交到 `main` 的正式 PR 通过 `plan` 后由 Actions 自动合并。提交前完成适用的本机验证。草稿在转为正式 PR 后进入这一流程。
