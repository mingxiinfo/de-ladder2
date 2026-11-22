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