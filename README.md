# GitSync

Mac 上的 Git 可视化工具。本机已安装 Xcode 后，不需要打开 Xcode 窗口，在终端里就能编译并启动。
demo-2分支
## 直接运行

在仓库根目录执行：

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

应用已经在运行时，先退出再重新 `open`，否则可能仍是上一次的进程。

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
