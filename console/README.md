# console：L2 控制台

日期：2026-11-17。状态：只有界面库，控制台页面还没有建。设计见 `docs/26`。

## 现在有什么

| 目录 | 内容 |
|---|---|
| `ui-design/` | Neon Void 界面库（`@qpjoy/ui-design-neon-void` 2.3.19） |

## ui-design 的来源

2026-11-17 从 L1 的 `de-llaaddddeerr/electron-dock/mx-launcher/ui-design/` 拷贝，没有拷 `node_modules`，内容没有改动。用户要求拷过来随本工程演变，所以以后在这里直接改，不回头和 L1 同步。要对照 L1 的后续改动时，以这个日期和版本号为起点比较。

构建（需要 pnpm 和 TypeScript，本工程里没有跑过）：

```bash
cd console/ui-design && pnpm install && pnpm build
```

`dist/` 是拷贝时 L1 已经构建好的产物，可以直接引用：

```html
<link rel="stylesheet" href="ui-design/dist/styles.css">
<main class="qp-app qp-theme-neon-void qp-density--medium">…</main>
```

## 控制台的约定

- 界面只是 `./scripts/manage.sh` 的外壳。每个按钮对应一条命令，并把命令显示出来。
- 不存自己的状态。机器和项目的事实只在 `inventory/`。
- 用户、身份、产品网络、Oversea 节点属于 Launcher Admin，这里只放链接。
