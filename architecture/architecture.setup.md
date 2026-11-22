```bash
./scripts/manage.sh node plan s2
./scripts/manage.sh node verify s2

./scripts/manage.sh node prepare s2 host
PROXY=http://127.0.0.1:7788 ./scripts/manage.sh node prepare s2 runtime
./scripts/manage.sh node prepare s2 cluster

PROXY=http://127.0.0.1:7788 ./scripts/manage.sh node prepare s2 network --context ladder2

PROXY=http://127.0.0.1:7788 ./scripts/manage.sh node prepare s2 gateway --context ladder2

PROXY=http://127.0.0.1:7788 ./scripts/manage.sh node prepare s2 postgres --context ladder2

PROXY=http://127.0.0.1:7788 ./scripts/manage.sh node prepare s2 host-nginx
# 验证
./scripts/manage.sh node verify s2 postgres --context ladder2


# init
PROXY=http://127.0.0.1:7788 ./scripts/manage.sh init s2
# ladder2
PROXY=http://127.0.0.1:7788 ./scripts/manage.sh deploy mx-launcher --context ladder2

# prepare
PROXY=http://127.0.0.1:7788 ./scripts/manage.sh deploy mx-launcher --context ladder2
HTTPS_PROXY=http://127.0.0.1:7788 ctr -n k8s.io images pull docker.io/library/node:22-alpine
PROXY=http://127.0.0.1:7788 ./scripts/manage.sh node prepare s2 runtime

# deploy admin
# http://192.168.0.117:18090/admin/
# 3775a34acbfb498ccc7e15a79fb839baf505b1680862b8d916f85492c6cb218b
```

```bash
# 1. 阿里云安全组放行 TCP 443、TCP 80（签证书要用）、UDP 51280。
# 2. 生成站点、推到 domestic02，同时把你的公网 IP 登记进后台白名单：
./scripts/manage.sh relay domestic02 site --admin-allow <你的公网IP>
# 3. 签证书。--agree-tos 表示你同意 Let's Encrypt 的用户协议；--email 可选，填了会收到到期提醒：
# PROXY=http://127.0.0.1:7788 ./scripts/manage.sh relay domestic02 cert --agree-tos --email <你的邮箱>

# 证书在 s2 上签，签好后放进边缘工具的配置目录，推到 domestic02。这条命令还会在 s2 上装一个每天检查的定时任务，快到期时自动续签并推过去。

# 4. 打开 https://mincave.minsight-ai.com/admin/，用 Internal Ops Token 登录。
# 5. 在 Config Center → Domestic Runtime Config 设 bootstrap：站点 domestic02，Protocol https，Bootstrap Host mincave.minsight-ai.com，Port 443，点 Save Config。上一轮部署后，站点和域名默认就是这两个。
# 6. 客户端的 .env 用 architecture/mx-launcher/scripts/manage.sh client-env 生成，域名默认就是这个。
```