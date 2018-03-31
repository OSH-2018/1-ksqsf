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
qemu-system-x86_64 \                                    # 64 位虚拟机
	-kernel bzImage \                               # 使用编译好的内核
	-hda disk.img \                                 # 使用创建好的虚拟磁盘
	-append "root=/dev/sda console=ttyS0 nokaslr" \ # 内核参数
	-gdb tcp::1234 \                                # 启动 GDB Server
	-S                                              # 启动时停止执行等待调试器
	--nographic                                     # 不使用 qemu 图形界面
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

### x86 系统启动引导

GDB 调试的起点是 `start_kernel()` 函数，因此该部分是直接通过读源码注释获知的，只保留了一部分主要步骤。

实际上我的电脑安装了 GRUB 引导器，因此启动时将直接转到 `/arch/x86/kernel/head.S` 的 `_start`；qemu 直接加载并跳转到这个入口。

在 `/arch/x86/kernel/head_64.S` 中完成内核启动前的一系列步骤：

1. 第一阶段：验证 CPU （`verify_cpu`），检查内存，修复页表。
2. 第二阶段：验证 CPU，启用 PAE（Physical Address Extension）和 PSE（Page Size Extension），切换到新的用于 64 位模式的 GDT，初始化段寄存器，

`start_of_setup` 将设置段寄存器、堆栈和 BSS 段，并跳转到 `main` 函数。

### 内核启动

在 `/boot/main.c` 的 `main` 函数中

1. 拷贝内核参数
2. 控制台初始化（实际上是串口）
3. 堆初始化
4. 检测 CPU 类型
5. 内存分布检测
6. 键盘初始化
7. 查询 Intel SpeedStep 信息
8. 设置视频模式
9. 进入保护模式

`go_to_protected_mode` 为跳转到保护模式做准备（初始化 IDT/GDT 并禁用中断），调用 `protected_mode_jump` 转入 32 位代码 `head_64.S` 准备进入 64 位模式。

在 `/arch/x86/boot/compressed/head_64.S` 中完成内核启动前的一系列步骤：

1. 第一阶段：验证 CPU （`verify_cpu`），检查内存，修复页表。
2. 第二阶段：验证 CPU，启用 PAE（Physical Address Extension）和 PSE（Page Size Extension），切换到新的用于 64 位模式的 GDT，初始化段寄存器，

此后将内核解压缩并跳转到 `start_kernel`，终于进入了内核。

1. 内核在每个 CPU 上创建了 idle 进程（PID=0），并在启动时设置 idle 进程的栈顶指针。
2. 设置处理器 ID
3. 初始化对象 tracker（初始化散列表并将静态对象池对象放到轮询列表中）
4. 初始化 stack canary 以增强安全性
5. 初始化 cgroup
6. 禁止本地中断请求
7. 激活第一个（引导）处理器 CPU（标记为 online, present, active, present, possible）
8. 初始化页表（散列表的表头和自旋锁）
9. 打印 Linux 信息（版本、编译主机等信息）
10. 与架构有关的引导时初始化（利用命令行参数），主要在此进行早期硬件初始化，并判断是否是 EFI 启动（并使用 EFI 的数据结构）
11. 清除 CPU 掩码
12. 保存解析过和未解析过的命令行
13. 设置 `nr_cpu_ids`
14. 设置每个 CPU 的（栈？）内存区域
15. 设置每个 CPU 都 online
16. 与架构有关的准备引导 CPU
17. 构建 zonelist，作为虚拟内存准备
18. 初始化页分配
19. 解析内核参数
20. 初始化跳转标签（通过自修改代码生成动态分支）
21. 初始化日志缓冲区
22. 初始化 PID 散列表
23. 初始化 VFS 缓存（dcache 和 inode 的早期初始化）
24. 排序内核内建的异常表
25. 初始化内核陷入
26. 初始化 Micro Memory PCI 块设备驱动
27. 初始化调度器（在启动任何中断之前）
28. 禁止抢占
29. 初始化 idr 缓存
30. 初始化互斥体的 Read-Copy Update 机制
31. 初始化 trace
32. 初始化上下文追踪
33. 初始化 radix tree
34. 初始化早期中断请求
35. 初始化中断请求（在每个 CPU 上都启用中断）
36. 初始化 tick 系统（计时相关）
37. 初始化计时器和高精度计时器
38. 初始化软中断 softirq 系统
39. 初始化 timekeeping 时钟源和计时数值
40. 初始化硬件计时器
41. 启动高精度计时器
42. 初始化 NMI 环境下的 `printk`
43. 初始化性能事件
44. 初始化 Profile
45. 初始化函数调用
46. 启用本地中断请求
47. 初始化 kmem cache（第二阶段）
48. 在 PCI 设置之前就启用控制台，以输出调试信息

截至此处，最基本的硬件初始化完成，内核可以正常响应中断请求。

1. 输出锁依赖信息
2. 锁自检
3. 页扩展初始化
4. 调试对象内存初始化
5. 初始化内核内存泄漏检查
6. 分配每个 CPU 的页集
7. 初始化 NUMA 内存策略
8. 初始化调度器时钟
9. 计算一秒可以跑多少个循环
10. 初始化 PID 映射表
11. 反向映射初始化
12. ACPI 早期初始化
13. 在 X86 机器上检查是否使用了 EFI，若是则进入虚拟模式
14. 初始化线程栈缓存
15. 初始化用户认证
16. 初始化 fork
17. 初始化进程缓存
18. 初始化文件系统缓冲区
19. 初始化键管理
20. 初始化安全性框架
21. 调试支持晚期初始化
22. 初始化 VFS 缓存
23. 初始化信号
24. 初始化页 writeback 机制
25. 初始化procfs
26. 初始化 nsfs
27. 初始化 cpuset
28. 初始化 cgroup
29. 任务统计早期初始化
30. 初始化延迟记账
31. 检查 CPU bug （在 x86 上检查 Spectre 等 CPU bug 和 FPU bug）
32. 初始化 ACPI 子系统
33. 初始化 Simple Firmware Interface
34. 检查 EFI 的运行时服务，并释放 EFI 资源
35. 初始化 ftrace

至此，内核中比较重要的服务已经全部初始化完成。接下来转入系统中重要的守护进程的创建。

1. 启动 RCU 调度器
2. 创建 init（PID = 1）
3. 创建 kthreadd（PID = 2）并等待创建完成
4. 执行调度
5. 初始化 `idle` 的启动任务
6. 禁止抢占式地调用 `schedule`，从而使得进程可以执行
7. 转入 `cpu_idle`，将在 `cpu_idle_loop()` 中无限循环

由于已经创建了 `init` 和 `kthreadd` 两个进程，那么 `schedule` 将有机会调度这两个进程。`kthreadd` 用于管理内核线程，与启动没什么直接关系，此处从略。

`init` 进程将执行 `kernel_init` 代码，做下面的事情：

1. 若提供 `init` 进程名，则直接执行之；若失败，则 `panic`
2. 否则，依次尝试 `/sbin/init` `/etc/init` `/bin/init` `/bin/sh`
3. 若以上尝试全部失败，则 `panic`

在真正执行起 `init` 程序时，将该进程将失去内核权限。

### 用户空间启动

此时，`init` 处于用户空间。Debian 9 的 `init` 为 `systemd`，`/sbin/init` 为 `/lib/systemd/systemd` 的一个符号链接。 systemd 围绕着 service 展开，并提供若干个 target 将服务连接起来（类似 SysVInit 的 runlevel，但更灵活）。

图形界面启动的主要 target 依赖关系为：

1. graphical.target -- 启动 display-manager.service
2. multi-user.target
3. basic.target -- 初始化套接字、计时器、路径和 slice 管理
4. sysinit.target -- 挂载本地文件系统和交换分区

在此过程中，将启动一系列服务（守护进程）。这里的 `display-manager.service` 将启动 GDM (GNOME Display Manager)。

1. 取代 tty1 上的 `getty`
2. 启动 Plymouth（启动动画）
3. 启动 user sessions（远程文件系统、NSS 用户查询、网络）
4. 执行 `/usr/sbin/gdm3`

显示管理器(display manager)将初始化显示功能，如启动 GNOME 桌面环境。GDM 的启动过程大致为

1. 显示登录界面，在此输入用户名和密码
2. 在一个 X 服务器上启动一个 X 会话（并启动 `gnome-session` 之类的守护进程），设置相关环境变量（语言、区域、输入法、显示等），启动窗口管理器、合成器、图形界面外壳（如 `gnome-shell`）等等

至此，整个系统对用户可用。

此外用户空间还可能有用户自行设置的用户级别 systemd 服务、自启动程序等。

## 追踪过程总结

1. 进入保护模式（16 位切换到 32 位）
2. 进入长模式（进入 64 位模式）

## 其他

我在 `_do_fork` 开头加了一句 `printk` 来研究启动过程中究竟创建了多少进程，以下是一些观察结果：

1. 在 init 启动之前，就有大量 968 次调用
2. 在 init 启动服务过程中有 640 次调用
3. 出现登录提示到实际登录过程中竟然也有 11 次调用
4. 登录后到 shell 启动有 5 次
5. 输入 `poweroff` 到关机有 49 次

仅仅一次开机到只输入 `poweroff` 命令关机，一共就创建了进程 1673 次！可见 UNIX 文化是多么喜欢创建进程……

实验中比较意外的是 init 启动之前创建的进程最多，比 init 启动服务和启动过程中创建的临时进程还多，说实话有点意外。但是考虑到 systemd 大幅消除了 shell 脚本的使用，而是直接解析 `.service`，想必进程创建不会像 SysVInit 那么多。
