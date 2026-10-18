# GitSync

Mac 上的原生 Git 可视化工具App, 采用Swift开发。打开本机仓库后，可以查看文件变更、管理分支、浏览提交历史，并直接 Fetch、Pull、Push。

## 功能

### 文件变更

勾选要提交的文件，右侧对照查看 diff，在底部写说明后提交。

![文件变更](images/1.文件变更.png)

### 分支管理

搜索并切换本地和远程分支，也可以新建分支，或把其他分支合并到当前分支。

![分支管理](images/2.分支管理.png)

### 提交历史

按当前分支、主线或所有分支查看提交图。选中一条提交后，中间列出改动文件，右侧用 Split 或 Unified 对照内容。

![历史变更 Split](images/3.历史变更-split.png)

![历史变更 Unified](images/4.历史变更-unified.png)

## 直接运行

本机已安装 Xcode 后，不需要打开 Xcode 窗口，在仓库根目录执行：

```bash
xcodebuild \
  -project GitSync/GitSync.xcodeproj \
  -scheme GitSync \
  -destination 'platform=macOS' \
  -configuration Debug \
  -derivedDataPath .build \
  build

open .build/Build/Products/Debug/GitSync.app
```

第一次编译会下载或生成编译缓存，时间会长一些。之后重复上面两条命令即可。

应用已经在运行时，先退出再重新 `open`，否则可能仍是上一次的进程。修改代码后需要重新编译，只执行 `open` 会启动上一次编出来的应用。

## 只编译

```bash
xcodebuild \
  -project GitSync/GitSync.xcodeproj \
  -scheme GitSync \
  -destination 'platform=macOS' \
  -configuration Debug \
  -derivedDataPath .build \
  build
```

编译结果在 `.build/Build/Products/Debug/GitSync.app`。这个目录只用于本地编译，不需要提交。
