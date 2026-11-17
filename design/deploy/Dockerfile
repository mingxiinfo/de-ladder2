# 架构图站点：纯静态文件，Nginx 发布。构建上下文是 manage.sh design build 组装出来的 design/.build/。
# 基础镜像版本只写在 infra/k8s/versions.env（DESIGN_NGINX_IMAGE），由 manage.sh 传进来。
ARG NGINX_IMAGE
FROM ${NGINX_IMAGE}
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY html/ /usr/share/nginx/html/
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s CMD wget -qO- http://127.0.0.1:8080/healthz >/dev/null || exit 1
