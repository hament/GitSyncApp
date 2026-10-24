# GitSync

[English](README.en.md) | [中文](README.md)

A native Git app for Mac, written in Swift. It stays light and fast. Open a local repository to review file changes, browse commit history and tags, and handle everyday remote sync. If GitHub Desktop feels heavy and slow, try this app.

## Highlights

- **Basics**: Clone a repository, and Fetch, Pull, or Push the current one.
- **Branches**: Search local and remote branches, compare any two branches side by side, or merge another branch into the current one.
- **Multiple windows**: Each window holds one project, so you can work on several repositories at once.
- **Theme colors**: Each project can have its own theme color.
- **Languages**: The interface supports Simplified Chinese and English.
- **Fast response**: The branch list still appears within a second even with tens of thousands of branches. Memory use and responsiveness are both well ahead of GitHub Desktop.

## Interface

The four screenshots below come from different project windows, each with its own theme color.

### File changes

On Changes, check the files to commit, review the working tree diff on the right in Unified or Split mode, and write the message at the bottom. The toolbar switches projects, clones a repository, and runs Refresh, Fetch, Pull, and Push.

![File changes](images/1.文件变更.png)

### Commit history

Open History to browse commits on the current branch, the main line, or all branches. Select a commit to see its message and changed files, then compare that commit's diff on the right. The first screenshot is Unified. The second is Split, with the old file and the new file side by side.

![Current branch history, Unified](images/2.分支管理.png)

![History, Split](images/3.历史变更-split.png)

### Tags

Search local tags on Tags. Select one to see its annotation, the commit it points to, and the changed files. Compare the content on the right in Unified or Split mode.

![Tags](images/4.tags设置.png)

## Build

With Xcode installed, build from the repository root without opening the Xcode window:

```bash
xcodebuild \
  -project GitSync/GitSync.xcodeproj \
  -scheme GitSync \
  -destination 'platform=macOS' \
  -configuration Debug \
  -derivedDataPath .build \
  build
```

The first build creates the compiler cache and takes longer.

## Run

```bash
open .build/Build/Products/Debug/GitSync.app
```

The app is written to `.build/Build/Products/Debug/GitSync.app`. That directory is only for local builds and does not need to be committed.

Quit a running copy before opening it again, or the previous process may stay open. After changing the code, rebuild first. Running `open` alone launches the last built app.
