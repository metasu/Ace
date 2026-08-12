# Obsidian Git 同步冲突解决教程

当 Obsidian 与 GitHub 同步时出现冲突，按照以下步骤解决。

---

## 一、常见错误信息

```
error: Committing is not possible because you have unmerged files.
fatal: Exiting because of an unresolved conflict.
```

---

## 二、解决步骤

### 2.1 进入 Obsidian vault 目录

```bash
cd D:\notes
```

### 2.2 查看 Git 状态

```bash
git status
```

冲突文件会显示为 `both modified`。

### 2.3 解决冲突 — 选择版本

> `.obsidian/workspace.json` 只记录界面状态（打开的文件、标签页等），不是实际内容，建议直接接受本地版本。

```bash
# 接受本地版本
git checkout --ours .obsidian/workspace.json

# 或接受远程版本
git checkout --theirs .obsidian/workspace.json
```

### 2.4 标记冲突已解决

```bash
git add .obsidian/workspace.json
```

### 2.5 提交合并

```bash
git commit -m "Resolve merge conflict in workspace.json"
```

### 2.6 添加其他待提交文件（如有）

```bash
git add .
git commit -m "Update notes"
```

### 2.7 推送到 GitHub

```bash
git push
```

---

## 三、其他常见情况

**多个文件冲突：** 对每个冲突文件重复步骤 2.3-2.4。

**放弃合并：**

```bash
git merge --abort
```

**手动编辑冲突文件：** 打开文件后会看到：

```
<<<<<<< HEAD
本地版本的内容
=======
远程版本的内容
>>>>>>> origin/main
```

编辑文件，删除标记，保留需要的内容，然后执行步骤 2.4-2.7。

---

## 四、验证解决成功

```bash
git status
```

显示 `working tree clean` 或 `nothing to commit` 即为成功。

---

## 五、预防建议

- 多设备使用 Obsidian 时，确保每次使用前先 `git pull` 同步
- 避免同时在两个设备上编辑同一个文件
- 将 `.obsidian/workspace.json` 添加到 `.gitignore` 可避免此类冲突（但会失去工作区状态同步）

---

## 六、快速参考命令

```bash
# 完整解决流程（PowerShell）
cd D:\notes
git status
git checkout --ours .obsidian/workspace.json
git add .obsidian/workspace.json
git commit -m "Resolve merge conflict"
git add .
git commit -m "Update notes"
git push
```
