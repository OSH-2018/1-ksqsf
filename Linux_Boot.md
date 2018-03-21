# Linux 启动过程追踪

该实验追踪 Linux 内核和用户空间的启动过程，并提出若干关键事件。

## 使用工具

操作环境：Debian stretch (amd64)，以下所有工具均为 Debian 自身提供。

* GNU coreutils
* GCC 6.3
* Qemu 2.8
* GDB 7.12
* debootstrap 1.0.89

## 实验环境搭建

实验环境虽然在虚拟机中，但虚拟环境也使用了最小化的 Debian，比较接近实际机器的使用情况。

### Linux 内核编译

为避免工具链问题，使用与 Debian stretch 稳定版内核版本相同的 [4.9.88](http://mirrors.ustc.edu.cn/kernel.org/linux/kernel/v4.x/linux-4.9.88.tar.xz)。

```bash
make defconfig        # 使用默认配置
make -j8 bzImage      # 创建 bzImage
```

一段时间后即完成编译，内核映像创建在 /arch/x86/boot/bzImage 中。

### 创建虚拟硬盘

为了使编译的 Linux 内核正常启动，首先创建一个 1GB 大的虚拟硬盘 `disk.img` 并创建一个 ext2 文件系统。这里使用 debootstrap 创建用户空间。

```bash
qemu-img create disk.img 1g         # 创建虚拟磁盘
mkfs.ext2 disk.img                  # 创建 ext2 文件系统
mkdir mnt                           # 挂载点
mount -o loop disk.img mnt          # 将 disk.img 挂载倒 mnt
debootstrap --arch amd64 jessie mnt # Debian 自举
chroot mnt
passwd                              # 修改 root 密码
umount mnt
rmdir mnt
```

### Qemu 虚拟机设置

使用以下命令启动虚拟机

```bash
qemu-system-x86_64 \                        # 64 位虚拟机
	-kernel bzImage \                       # 使用编译好的内核
	-hda disk.img \                         # 使用创建好的虚拟磁盘
	-append "root=/dev/sda console=ttyS0" \ # 内核参数
	-gdb tcp::1234 \                        # 启动 GDB Server
	-S                                      # 启动时停止执行等待调试器
	--nographic                             # 不使用图形界面
```

### GDB 调试

在调试时发现了 `Remote 'g' packet reply is too long` 问题，OSDev Wiki 指出了[解决方法](https://wiki.osdev.org/QEMU_and_GDB_in_long_mode)，Stack Overflow 给出了如下[简单方法](https://stackoverflow.com/a/49348616/1972246)。

```bash
gdb \
    -ex "add-auto-load-safe-path $(pwd)" \
    -ex "file vmlinux" \
    -ex 'set arch i386:x86-64:intel' \
    -ex 'target remote localhost:1234' \
    -ex 'break start_kernel' \
    -ex 'continue' \
    -ex 'disconnect' \
    -ex 'set arch i386:x86-64' \
    -ex 'target remote localhost:1234'
```

这段命令将在 `start_kernel()` 函数处停止。

### Makefile

编写了一个 Makefile 用于简化用户操作，在仓库根目录下。

## 启动过程追踪

TODO.

## 追踪过程总结

TODO.
