# 适用于 Debian 的 XanMod 内核自动化管理系统

这是一个为 Debian 及衍生发行版（如 Ubuntu）设计的全自动内核管理系统，专为 [XanMod](https://xanmod.org/) 内核优化。它解决了在每次内核升级后，旧内核版本会不断累积并占用磁盘空间的问题。

本系统通过一个简单的安装脚本，实现“一劳永逸”的自动化管理。

## ✨ 主要特性

- **一键安装**：只需运行一个安装脚本，即可部署整个自动化系统。
- **一键升级**：提供一个便捷的 `xupdate` 命令，用于启动系统升级和内核更新。
- **全自动清理**：在您升级并成功重启进入新内核后，系统会自动清理掉所有过时的旧内核版本。
- **安全可靠**：清理操作只会在您成功启动并登录到新系统后触发，确保您总有一个可以正常工作的内核。如果新内核无法启动，旧内核依然可用。
- **保留备份**：默认情况下，系统会保留当前正在运行的内核和最新的一个备用内核，提供双重安全保障。
- **原生集成**：使用 `systemd` 服务来管理后台任务，这是现代 Linux 系统中最健壮、最原生的方式。
- **日志记录**：所有后台清理操作都会被记录到系统日志（syslog）中，方便排查问题。

## ⚙️ 工作原理

本系统由三个核心组件构成，协同工作以实现自动化：

1.  **`xupdate` (或 `manage-kernel.sh`)**
    - 这是您唯一需要手动交互的命令。
    - 当您运行 `sudo xupdate` 时，它会执行 `apt update` 和 `apt full-upgrade` 来安装最新的系统更新，包括新的 XanMod 内核。
    - 升级完成后，它会**启用**一次性的 `systemd` 清理服务，使其在下次系统启动时运行。

2.  **`kernel-cleanup.service`**
    - 这是一个 `systemd` 服务文件。
    - 它被设置为在系统成功启动并连接到网络后自动运行。
    - 它的唯一任务就是执行下面的 `kernel-cleaner` 脚本，并且在任务完成后**自动禁用**自身，以防止重复运行。

3.  **`kernel-cleaner`**
    - 这是实际执行清理工作的后台脚本。
    - 它会智能地识别出所有已安装的 XanMod 内核，并保留当前正在运行的内核和最新的一个备用内核。
    - 然后，它会使用 `apt purge` 彻底卸载所有其他旧内核及其头文件，并运行 `autoremove` 和 `update-grub` 来完成最后的清理工作。

**整个流程如下：**
`sudo xupdate` → 系统升级 → `sudo reboot` → 成功登录 → `systemd` 自动触发 `kernel-cleaner` → 旧内核被清理 → `systemd` 服务自动禁用 → 等待下一次循环。

## 🚀 安装

安装过程非常简单，只需要运行一个脚本即可。

1.  **下载安装脚本**
    将安装脚本 `setup-kernel-management.sh` 下载到您的系统中。

2.  **授予执行权限**
    ```bash
    chmod +x setup-kernel-management.sh
    ```

3.  **运行安装程序**
    使用 `sudo` 运行此脚本。它会自动创建所有必需的文件、设置权限并配置 `systemd`。
    ```bash
    sudo ./setup-kernel-management.sh
    ```

安装完成后，安装脚本本身就不再需要了。

## 🕹️ 日常使用

安装后，您只需要记住一个命令。

当您想要更新系统和 XanMod 内核时，只需在终端中运行：
```bash
sudo xupdate
```
脚本会完成升级工作，然后提示您重启。请按照提示重启系统，剩下的清理工作将会在后台自动完成。

## 🔧 高级选项

#### 查看清理日志

您可以使用 `journalctl` 命令来查看后台清理任务的执行日志：
```bash
# 查看特定服务的日志
journalctl -u kernel-cleanup.service

# 或者查看由清理脚本生成的特定日志
journalctl -t KERNEL_CLEANER
```

#### 自定义保留内核数量

如果您想保留更多或更少的备用内核，可以编辑后台清理脚本：
```bash
sudo nano /usr/local/bin/kernel-cleaner
```
在文件顶部找到 `EXTRA_KERNELS_TO_KEEP=1` 这一行，将数字 `1` 修改为您希望保留的备用内核数量。

## 🗑️ 卸载

如果您想完全移除此系统，可以运行以下命令：
```bash
# 停止并禁用 systemd 服务
sudo systemctl stop kernel-cleanup.service
sudo systemctl disable kernel-cleanup.service

# 删除脚本和 systemd 文件
sudo rm /usr/local/bin/xupdate
sudo rm /usr/local/bin/manage-kernel.sh
sudo rm /usr/local/bin/kernel-cleaner
sudo rm /etc/systemd/system/kernel-cleanup.service

# 重载 systemd 配置使更改生效
sudo systemctl daemon-reload

echo "内核管理系统已成功卸载。"
```

---
