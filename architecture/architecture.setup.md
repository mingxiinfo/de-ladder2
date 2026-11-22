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
```