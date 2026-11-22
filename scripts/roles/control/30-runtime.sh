#!/usr/bin/env bash
# 阶段 runtime：containerd、kubeadm、kubelet、kubectl（docs/14 修订、docs/16、docs/35）。
# 版本只从 infra/k8s/versions.env 读。下载走 PROXY（如果设了）。
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
need_root
guard_target
need_apt

say "基础包"
apt_get update >/dev/null
apt_get install ca-certificates curl gpg conntrack socat containerd >/dev/null
done_ "containerd $(containerd --version | awk '{print $3}')"

say "Kubernetes 软件源 $K8S_MINOR（pkgs.k8s.io）"
key=/etc/apt/keyrings/kubernetes-apt-keyring.gpg
if [[ ! -s "$key" ]]; then
  install -d -m 0755 /etc/apt/keyrings
  dl "https://pkgs.k8s.io/core:/stable:/$K8S_MINOR/deb/Release.key" | gpg --dearmor -o "$key"
  echo "  ✎ $key"
fi
write_file /etc/apt/sources.list.d/kubernetes.list <<EOF
deb [signed-by=$key] https://pkgs.k8s.io/core:/stable:/$K8S_MINOR/deb/ /
EOF
apt_get update >/dev/null

say "kubeadm、kubelet、kubectl"
want=""
if [[ -n "${K8S_VERSION:-}" ]]; then
  want="$(apt-cache madison kubeadm | awk -v v="${K8S_VERSION#v}" '$3 ~ "^"v"-" {print $3; exit}')"
  [[ -n "$want" ]] || die "软件源里没有 kubeadm ${K8S_VERSION}。versions.env 的 K8S_VERSION 要和 s1 一致（docs/16）。"
fi
have="$(dpkg-query -W -f='${Version}' kubeadm 2>/dev/null || true)"
if [[ -n "$have" && ( -z "$want" || "$have" == "$want" ) ]]; then
  note "已装 $have"
else
  apt-mark unhold kubelet kubeadm kubectl >/dev/null 2>&1 || true
  if [[ -n "$want" ]]; then apt_get install "kubelet=$want" "kubeadm=$want" "kubectl=$want" >/dev/null
  else apt_get install kubelet kubeadm kubectl >/dev/null; fi
fi
apt-mark hold kubelet kubeadm kubectl >/dev/null
done_ "$(kubeadm version -o short)（已锁定，apt upgrade 不会动它们）"
[[ -n "${K8S_VERSION:-}" ]] || note "versions.env 没写 K8S_VERSION，装的是 $K8S_MINOR 的最新补丁。和 s1 的补丁版本对一下（docs/16）。"

say "containerd 配置"
pause="$(kubeadm config images list --kubernetes-version "$(kubeadm version -o short)" \
          --image-repository "$K8S_IMAGE_REPOSITORY" 2>/dev/null | grep '/pause:' | head -1)"
[[ -n "$pause" ]] || die "算不出 pause 镜像（kubeadm config images list 失败）"
tmp="$(mktemp)"
containerd config default >"$tmp"
# cgroup 驱动和 kubelet 一致用 systemd；沙箱镜像和 kubeadm 要的一致。两种配置格式（containerd 1.x 和 2.x）都处理。
sed -i -e 's/SystemdCgroup = false/SystemdCgroup = true/' \
       -e "s#sandbox_image = \".*\"#sandbox_image = \"$pause\"#" \
       -e "s#sandbox = '.*'#sandbox = '$pause'#" \
       -e "s#sandbox = \".*\"#sandbox = \"$pause\"#" "$tmp"
grep -q 'SystemdCgroup = true' "$tmp" || die "containerd 的默认配置里找不到 SystemdCgroup，格式变了，先人工看 containerd config default"
write_file /etc/containerd/config.toml <"$tmp"
rm -f "$tmp"

if [[ -n "${PROXY:-}" ]]; then
  say "containerd 拉镜像走代理 $PROXY"
  # 只影响 containerd 拉镜像。集群建好之前改它没有影响；之后重启 containerd，在跑的容器不会停。
  write_file /etc/systemd/system/containerd.service.d/10-ladder2-proxy.conf <<EOF
# de-ladder2（docs/35）。拉 registry.k8s.io、ghcr.io、docker.io 的镜像用。
[Service]
Environment="HTTP_PROXY=$PROXY" "HTTPS_PROXY=$PROXY" "NO_PROXY=$NO_PROXY_LIST"
EOF
else
  note "没有设 PROXY，containerd 直接连镜像仓库。国内拉不下来时：PROXY=http://127.0.0.1:7788 再跑这个阶段"
fi

say "helm $HELM_VERSION（装网关要用）"
if [[ "$(helm version --short 2>/dev/null)" == "$HELM_VERSION"* ]]; then
  note "已装"
else
  arch="$(dpkg --print-architecture)"; tgz="helm-$HELM_VERSION-linux-$arch.tar.gz"; d="$(mktemp -d)"
  dl -o "$d/$tgz" "https://get.helm.sh/$tgz"
  dl -o "$d/$tgz.sha256sum" "https://get.helm.sh/$tgz.sha256sum"
  ( cd "$d" && echo "$(awk '{print $1; exit}' "$tgz.sha256sum")  $tgz" | sha256sum -c --quiet - ) || die "helm 的校验和对不上"
  tar -C "$d" -xzf "$d/$tgz"
  install -m 0755 "$d/linux-$arch/helm" /usr/local/bin/helm
  rm -rf "$d"
  echo "  ✎ /usr/local/bin/helm"
fi

if (( CHANGED )); then
  systemctl daemon-reload
  systemctl restart containerd
  echo "  ↻ containerd 已重启"
fi
systemctl enable --now containerd >/dev/null 2>&1
systemctl enable kubelet >/dev/null 2>&1
done_ "containerd 在运行；kubelet 已设为开机启动（建集群之后才会正常运行）"

say "buildkit $BUILDKIT_VERSION（deploy 在本机构建镜像用，docs/55）"
# buildkitd 用 containerd 当后端，镜像直接进 k8s.io 命名空间，kubelet 马上能用：不用 docker，不用镜像仓库，也不用 import。
# 它自己的代理只写在自己的 unit 里，不动 containerd 和别的服务。
if [[ "$(buildkitd --version 2>/dev/null | awk '{print $3}')" == "$BUILDKIT_VERSION" ]]; then
  note "已装"
else
  arch="$(dpkg --print-architecture)"; tgz="buildkit-$BUILDKIT_VERSION.linux-$arch.tar.gz"; d="$(mktemp -d)"
  dl -o "$d/$tgz" "https://github.com/moby/buildkit/releases/download/$BUILDKIT_VERSION/$tgz"
  tar -C "$d" -xzf "$d/$tgz"
  install -m 0755 "$d/bin/buildkitd" /usr/local/bin/buildkitd
  install -m 0755 "$d/bin/buildctl" /usr/local/bin/buildctl
  rm -rf "$d"
  echo "  ✎ /usr/local/bin/buildkitd、buildctl"
  CHANGED_BK=1
fi
proxy_env=""
[[ -n "${PROXY:-}" ]] && proxy_env="Environment=\"HTTP_PROXY=$PROXY\" \"HTTPS_PROXY=$PROXY\" \"NO_PROXY=$NO_PROXY_LIST\""
CHANGED=0
write_file /etc/systemd/system/ladder2-buildkitd.service <<UNIT
# de-ladder2（docs/55）。镜像建进 containerd 的 k8s.io；RUN 用宿主机网络，才连得上 127.0.0.1 上的代理。
[Unit]
Description=ladder2 buildkitd (containerd worker, namespace k8s.io)
After=containerd.service
Requires=containerd.service

[Service]
$proxy_env
ExecStart=/usr/local/bin/buildkitd --addr unix:///run/buildkit/buildkitd.sock --oci-worker=false --containerd-worker=true --containerd-worker-addr=/run/containerd/containerd.sock --containerd-worker-namespace=k8s.io --containerd-worker-net=host
Restart=always

[Install]
WantedBy=multi-user.target
UNIT
if (( CHANGED )) || [[ -n "${CHANGED_BK:-}" ]]; then
  systemctl daemon-reload
  systemctl enable ladder2-buildkitd >/dev/null 2>&1
  systemctl restart ladder2-buildkitd
  echo "  ↻ ladder2-buildkitd 已重启"
else
  systemctl enable --now ladder2-buildkitd >/dev/null 2>&1
fi
for _ in 1 2 3 4 5 6 7 8 9 10; do buildctl --addr unix:///run/buildkit/buildkitd.sock debug workers >/dev/null 2>&1 && break; sleep 1; done
buildctl --addr unix:///run/buildkit/buildkitd.sock debug workers 2>/dev/null | grep -q containerd \
  || die "buildkitd 没起来或者没有 containerd worker：journalctl -u ladder2-buildkitd -n 50"
done_ "buildkitd 在运行，镜像建进 containerd 的 k8s.io"
