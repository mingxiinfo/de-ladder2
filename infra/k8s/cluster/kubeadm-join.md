# 加入节点

没有实测。join 命令里有 token，不写进 Git，现用现生成。

## 工作节点（阶段 B 的 s1、以后的内网服务器）

```bash
# 在 s2 上生成（token 24 小时过期）
kubeadm token create --print-join-command
# 在新节点上：先把 k8s-api.ladder2.internal 写进 /etc/hosts 指向 s2，再执行上面打印的命令
```

GPU 节点加入后打标签：`kubectl label node <名字> ladder2/gpu=true`。

## 控制面（阶段 C，凑够三个时）

```bash
# 在 s2 上
kubeadm init phase upload-certs --upload-certs       # 打印 certificate key，2 小时过期
kubeadm token create --print-join-command
# 在新控制面上：上面的 join 命令后面加
#   --control-plane --certificate-key <key>
```

控制面总数保持奇数。两个控制面比一个更脆弱（docs/16）。
