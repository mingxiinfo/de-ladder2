# 架构图站点：纯静态文件，Nginx 发布。构建上下文是 manage.sh design build 组装出来的 design/.build/。
# 基础镜像版本只写在 infra/k8s/versions.env（DESIGN_NGINX_IMAGE），由 manage.sh 传进来。
# 监听地址在启动时决定（DESIGN_LISTEN），同一个镜像在开发机和服务器上都能用。
ARG NGINX_IMAGE
FROM ${NGINX_IMAGE}
ENV NGINX_ENVSUBST_FILTER=^DESIGN_ \
    DESIGN_LISTEN=127.0.0.1:18310
RUN rm -f /etc/nginx/conf.d/default.conf
COPY default.conf.template /etc/nginx/templates/default.conf.template
COPY html/ /usr/share/nginx/html/
