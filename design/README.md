# design：架构图和站点

日期：2026-11-17。状态：开发机上构建和运行通过，没在服务器上部署过。说明在 `docs/31`。

| 目录 | 内容 |
|---|---|
| `architecture/` | Archify 源文件和生成的图 |
| `site/` | 首页和演变时间线 `timeline.json` |
| `deploy/` | Dockerfile、容器里的 Nginx、compose、host-nginx 样板 |

```bash
./scripts/manage.sh design serve     # 本机预览
./scripts/manage.sh design build     # 打镜像
./scripts/manage.sh design up        # 启动，http://127.0.0.1:18310/
```
