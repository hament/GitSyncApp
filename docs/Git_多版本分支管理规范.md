# Git 多版本分支管理规范

> 适用场景：项目同时维护旧版本（1.x）、当前版本（2.x）和后续新版本，各版本可以独立修复、测试、发布，不希望旧版本代码自动进入最新主分支。

## 1. 核心原则

1. **分支不会因为 `push` 而自动合并。** 推送只更新指定远程分支。
2. **创建 Pull Request（PR）不等于合并。** GitHub 的 `Can't automatically merge` 只表示当前 PR 的源分支与目标分支有无法自动解决的冲突，不代表已发生合并。
3. **维护分支独立演进。** `release/1.x`、`release/2.x` 不需要定期互相合并，也无需定期合并到 `main`。
4. **按需传播修复。** 同一修复需要进入多个版本时，优先对特定修复提交执行 `cherry-pick`，并分别测试、提交 PR。
5. **PR 的 `base` 是目标分支，`compare` 是来源分支。** 应当明确选择目标分支，不要默认所有 PR 都指向 `main`。
6. **保护正式发布记录。** 建议使用 Git Tag 标记不可变的发布快照，例如 `v1.0.0`、`v2.0.0`；使用 `release/1.x` 这样的分支承载长期维护。

## 2. 推荐分支结构

```text
main                         # 最新开发主线，未来可进入 3.0 等版本
├── release/1.x              # 1.x 长期维护分支（对应现有 v1.0.0）
│   └── hotfix/1.x-login     # 从 release/1.x 拉出的临时修复分支
├── release/2.x              # 2.x 长期维护分支（对应现有 v2.0）
│   └── hotfix/2.x-crash     # 从 release/2.x 拉出的临时修复分支
└── feature/new-feature      # 从 main 拉出的新功能分支
```

> 上图是**维护关系的示意图**，并不要求历史必须如此分叉。对于已经合并 `v2.0` 的 `main`，无需回滚或重建 Git 历史。

| 分支 | 作用 | 常见 PR 目标 | 是否需定期合并至 main |
| --- | --- | --- | --- |
| `main` | 最新功能及未来版本的开发主线 | `main` | 不适用 |
| `release/1.x` | 维护 1.x、发布 1.x 修订版 | `release/1.x` | 否 |
| `release/2.x` | 维护 2.x、发布 2.x 修订版 | `release/2.x` | 否 |
| `feature/*` | 新功能开发 | 创建时确定的目标分支 | 否，由 PR 决定 |
| `hotfix/*` | 针对指定版本的修复 | 对应的 `release/*` 或 `main` | 否，由 PR 决定 |

## 3. 常见工作流

### 3.1 修复旧版本 1.x（不影响 main）

```bash
# 获取远程更新
git fetch origin

# 切换到维护分支并更新
git switch release/1.x
git pull --ff-only origin release/1.x

# 创建独立的修复分支
git switch -c hotfix/1.x-login

# 修改并提交
git add .
git commit -m "fix: 修复 1.x 登录问题"

# 推送修复分支
git push -u origin hotfix/1.x-login
```

在 GitHub 中创建 PR：

```text
base:    release/1.x
compare: hotfix/1.x-login
```

经过代码评审、测试后合并；`main` 和 `release/2.x` 不受该 PR 影响。

### 3.2 同一个修复也需要应用到 main

假设 1.x 的修复提交哈希为 `abc1234`，先以最新 `main` 为基础创建独立分支：

```bash
git fetch origin
git switch main
git pull --ff-only origin main
git switch -c hotfix/main-login

# 只提取特定修复，而不是整体合并旧分支
git cherry-pick abc1234

# 本地测试通过后推送
git push -u origin hotfix/main-login
```

然后创建 PR：

```text
base:    main
compare: hotfix/main-login
```

如果 `cherry-pick` 出现冲突：

```bash
# 手工修复冲突文件后
git add <已解决冲突的文件>
git cherry-pick --continue

# 如果决定取消整个 cherry-pick
git cherry-pick --abort
```

**注意：** `cherry-pick` 仍可能冲突，尤其是新旧版本的架构或文件结构不同。不要未经测试直接推送至受保护主分支。若修复有多个依赖提交，应一起选择所需提交或重新实现修复。

### 3.3 开发新功能

```bash
git switch main
git pull --ff-only origin main
git switch -c feature/branch-display

# 开发、测试、提交后
git add .
git commit -m "feat: 新增分支展示功能"
git push -u origin feature/branch-display
```

创建 PR：`feature/branch-display` → `main`。

### 3.4 发布一个维护版本

当 `release/1.x` 测试通过并准备发布 1.0.1：

```bash
git switch release/1.x
git pull --ff-only origin release/1.x

# 在最终确认的发布提交上创建附注标签
git tag -a v1.0.1 -m "Release v1.0.1"
git push origin v1.0.1
```

推荐通过 GitHub Release 关联对应 Tag 和构建产物。Tag 用于标记发布快照，不应随意移动；需要后续修复则继续更新 `release/1.x`，再发布新 Tag。

## 4. GitHub PR 提示说明

| 提示或操作 | 实际含义 | 是否改变目标分支 |
| --- | --- | --- |
| `Compare & pull request` | 建议发起 PR 对比 | 否 |
| `Open a pull request` | 填写并创建 PR | 否 |
| `Can't automatically merge` | 当前分支组合存在自动合并冲突 | 否 |
| 创建 PR | 发起代码评审请求 | 否 |
| `Merge pull request` | 在满足权限与检查要求后执行合并 | **是** |
| `git push origin release/1.x` | 推送旧版本分支提交 | 否，不改变 `main` |

你的情况：如果只是修改旧版本 `v1.0.0`，**正常提交并 `git push origin v1.0.0` 即可，无需创建指向 `main` 的 PR。**

## 5. 从现有分支迁移（可选）

如果当前远程已存在 `v1.0.0` 和 `v2.0` 分支，可以沿用旧名称；重命名只是为了统一规范，不是解决冲突的必要操作。

如希望保留旧分支并额外创建规范命名的维护分支：

```bash
git fetch origin

# 基于现有远程分支建立新的本地维护分支
git switch -c release/1.x origin/v1.0.0
git push -u origin release/1.x

git switch -c release/2.x origin/v2.0
git push -u origin release/2.x
```

确认 GitHub 仓库保护规则、CI、部署脚本和 PR 目标均已适配之后，再决定是否删除旧分支。**不要仅因创建新命名分支就立即删除旧分支。**

> **名称冲突提醒：** 如果仓库里已有名为 `v1.0.0` 的**分支**，建议将该版本的 Tag 与分支命名区分开；Git 允许部分情况下同名 ref 并存，但命令和工具中容易产生歧义。迁移和创建 Tag 前先检查现有 refs。

## 6. 推荐仓库配置

- 为 `main`、`release/1.x`、`release/2.x` 配置分支保护规则。
- 要求核心分支变更通过 PR 及 CI 测试，避免直接推送造成意外修改。
- PR 模板要求填写：**目标版本、改动目的、测试情况、是否需要跨版本同步**。
- 每次发布使用版本 Tag；维护分支始终指向该系列最新维护状态。
- 对已结束维护的旧版本可标注 EOL（停止维护），保留历史分支与 Tag 供追溯。

## 7. 一句话结论

**`main` 负责新版本，`release/*` 负责各自旧版本；修复在哪个版本发生，就把 PR 指向哪个维护分支。只有确实需要同步的修复才通过 `cherry-pick` 等方式有选择地迁移。**
