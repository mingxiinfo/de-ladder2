# L2 的 Launcher 镜像（docs/46、docs/47）。构建上下文是 architecture/mx-launcher/。
# 由 ./scripts/manage.sh image build mx-launcher 调用。
#
# 和 L1 的区别：L1 先在宿主机上跑 shadow_image_admin_assets、shadow_image_artifacts
# 把管理界面和 site-slot 产物拷进 server/artifacts，再用 server/Dockerfile 构建。
# 这里两样都放进镜像的构建阶段，不依赖宿主机上的 node_modules 和 L1 仓库的目录布局。

ARG NODE_IMAGE=node:22-alpine

# ── 0. site-slot 产物：照 L1 的 shadow_image_artifacts ──
# 用 MX_SITE_SLOT_ALLOW_DEGRADED_QP_TUNNEL_CLI=1：完整的 qp-tunnel-cli 要 L1 仓库里的 electron-plugin，
# 这里没有；降级版够 host-runner 装 service peer 用（L1 也这么构建镜像）。
# 生成的 WireGuard 配置里是占位，不是真密钥（docs/47 实测）。
FROM ${NODE_IMAGE} AS artifacts
RUN apk add --no-cache tar
WORKDIR /mx
COPY server/package.json ./server/package.json
COPY server/scripts/ ./server/scripts/
COPY site-slots/ ./site-slots/
RUN MX_LAUNCHER_ROOT=/mx MX_SITE_SLOT_ALLOW_DEGRADED_QP_TUNNEL_CLI=1 \
    node server/scripts/site-slot-artifact-materializer.mjs all --out-dir /mx/out/site-slots --no-preserve-runtime-secrets >/dev/null \
 && test -f /mx/out/site-slots/domestic/mx-domestic-qp-tunnel-cli-fallback.tar.gz

# ── 1. 管理界面：照 L1 scripts/manage.sh 的 shadow_image_admin_assets 拷文件 ──
FROM ${NODE_IMAGE} AS admin
ARG NPM_REGISTRY=https://registry.npmmirror.com
WORKDIR /src
COPY desktop/ ./desktop/
COPY ui-design/src/ ./ui-design/src/
# three 的版本和 desktop/pnpm-lock.yaml 锁定的一致
RUN npm install --no-save --no-audit --no-fund --registry "$NPM_REGISTRY" --prefix /tmp/three three@0.179.1
RUN set -eu; out=/admin; mkdir -p "$out/node_modules/three/build" "$out/ui-design"; \
    for f in index.html renderer.js theme.js service-operations.js identity-applications.js identity-applications.css \
             admin-session.js registration.js service-operations-catalog.js styles.css neon-void.css; do \
      cp "desktop/$f" "$out/$f"; \
    done; \
    for f in styles.css tokens.css select.css select.js; do cp "ui-design/src/$f" "$out/ui-design/$f"; done; \
    cp /tmp/three/node_modules/three/build/*.js "$out/node_modules/three/build/"

# ── 2. 服务端：和 L1 server/Dockerfile 的 build 阶段相同 ──
FROM ${NODE_IMAGE} AS build
ARG NPM_REGISTRY=https://registry.npmmirror.com
ENV COREPACK_NPM_REGISTRY=${NPM_REGISTRY} \
    NPM_CONFIG_REGISTRY=${NPM_REGISTRY}
WORKDIR /app
RUN corepack enable && corepack prepare pnpm@9.15.4 --activate
COPY server/package.json server/pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile=false
COPY server/ ./
RUN mkdir -p artifacts/site-slots
RUN pnpm build
RUN pnpm prune --prod

# ── 3. 运行：和 L1 server/Dockerfile 的 runtime 阶段相同，多拷一份管理界面 ──
FROM ${NODE_IMAGE} AS runtime
WORKDIR /app
LABEL dev.qpjoy.mx-launcher.project="mx-launcher" \
      dev.qpjoy.mx-launcher.component="server" \
      dev.qpjoy.ladder2.source="architecture/mx-launcher"
ENV NODE_ENV=production
ENV HOST=0.0.0.0
ENV PORT=18090
RUN apk add --no-cache bash iproute2 iputils kmod openssh-client openresolv rsync sshpass sudo wireguard-tools wireguard-tools-wg-quick
COPY --from=build /app/dist ./dist
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/package.json ./package.json
COPY --from=build /app/scripts ./scripts
COPY --from=build /app/scripts ./server/scripts
COPY --from=build /app/artifacts ./artifacts
COPY --from=artifacts /mx/out/site-slots ./artifacts/site-slots
COPY --from=admin /admin ./artifacts/admin
EXPOSE 18090
HEALTHCHECK --interval=30s --timeout=4s --retries=3 \
  CMD wget -qO- http://127.0.0.1:18090/healthz || exit 1
CMD ["node", "dist/src/index.js"]
