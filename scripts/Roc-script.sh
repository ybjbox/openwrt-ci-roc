#!/usr/bin/env bash
set -Eeuo pipefail

# 修改默认IP & 固件名称 & 编译署名和时间
sed -i 's/192.168.1.1/10.0.0.1/g' package/base-files/files/bin/config_generate
sed -i "s/hostname='.*'/hostname='Athena'/g" package/base-files/files/bin/config_generate
luci_system_js="feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/10_system.js"
firmware_version_anchor="_('Firmware Version'), (L.isObject(boardinfo.release) ? boardinfo.release.description + ' / ' : '') + (luciversion || ''),"
grep -Fq "$firmware_version_anchor" "$luci_system_js" || { echo "Error: LuCI firmware version anchor was not found in $luci_system_js" >&2; exit 1; }
sed -i "s#_('Firmware Version'), (L\.isObject(boardinfo\.release) ? boardinfo\.release\.description + ' / ' : '') + (luciversion || ''),# \
            _('Firmware Version'),\n \
            E('span', {}, [\n \
                (L.isObject(boardinfo.release)\n \
                ? boardinfo.release.description + ' / '\n \
                : '') + (luciversion || '') + ' / ',\n \
            E('a', {\n \
                href: 'https://github.com/ybjbox/openwrt-ci-roc/releases',\n \
                target: '_blank',\n \
                rel: 'noopener noreferrer'\n \
                }, [ 'Built by Ryan $(date "+%Y-%m-%d %H:%M:%S")' ])\n \
            ]),#" "$luci_system_js"

# 调整NSS驱动q6_region内存区域预留大小（ipq6018.dtsi默认预留85MB，ipq6018-512m.dtsi默认预留55MB，带WiFi必须至少预留54MB，以下分别是改成预留16MB、32MB、64MB和96MB）
# sed -i 's/reg = <0x0 0x4ab00000 0x0 0x[0-9a-f]\+>/reg = <0x0 0x4ab00000 0x0 0x01000000>/' target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/ipq6018-512m.dtsi
# sed -i 's/reg = <0x0 0x4ab00000 0x0 0x[0-9a-f]\+>/reg = <0x0 0x4ab00000 0x0 0x02000000>/' target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/ipq6018-512m.dtsi
# sed -i 's/reg = <0x0 0x4ab00000 0x0 0x[0-9a-f]\+>/reg = <0x0 0x4ab00000 0x0 0x04000000>/' target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/ipq6018-512m.dtsi
# sed -i 's/reg = <0x0 0x4ab00000 0x0 0x[0-9a-f]\+>/reg = <0x0 0x4ab00000 0x0 0x06000000>/' target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/ipq6018-512m.dtsi

# 调节IPQ60XX的1.5GHz频率电压(从0.9375V提高到0.95V，过低可能导致不稳定，过高可能增加功耗和发热，具体数值需要根据实际情况调整)
# sed -i 's/opp-microvolt = <937500>;/opp-microvolt = <950000>;/' target/linux/qualcommax/patches-6.12/0038-v6.16-arm64-dts-qcom-ipq6018-add-1.5GHz-CPU-Frequency.patch

# 移除要替换的包
rm -rf feeds/luci/applications/luci-app-argon-config
rm -rf feeds/luci/applications/luci-app-wechatpush
rm -rf feeds/luci/applications/luci-app-appfilter
rm -rf feeds/luci/applications/luci-app-frpc
rm -rf feeds/luci/applications/luci-app-frps
rm -rf feeds/luci/applications/luci-app-upnp
rm -rf feeds/luci/applications/luci-app-wol
rm -rf feeds/luci/themes/luci-theme-argon
rm -rf feeds/luci/applications/luci-app-wrtbwmon
rm -rf feeds/packages/net/wrtbwmon
rm -rf feeds/packages/net/open-app-filter
rm -rf feeds/packages/net/miniupnpd
rm -rf feeds/packages/net/ariang
rm -rf feeds/packages/net/aria2
rm -rf feeds/packages/net/nginx
rm -rf feeds/packages/net/frp
rm -rf feeds/packages/lang/golang
rm -rf feeds/packages/net/smartdns
rm -rf feeds/luci/applications/luci-app-smartdns
rm -rf feeds/packages/net/mosdns
rm -rf feeds/luci/applications/luci-app-mosdns

# 带有 3 次重试机制的 git clone，极大提高 GitHub 网络波动时的编译成功率
function git_clone() {
  local url="$1"
  local dest="$2"
  local max_retries=3
  local count=0
  while [ $count -lt $max_retries ]; do
    if git clone --depth=1 "$url" "$dest"; then
      return 0
    fi
    count=$((count + 1))
    echo "Warning: git clone failed for $url. Retrying ($count/$max_retries)..."
    sleep 3
  done
  echo "Error: git clone failed for $url after $max_retries attempts." >&2
  return 1
}

# Git稀疏克隆，带 3 次重试机制
function git_sparse_clone() {
  local branch="$1"
  local repourl="$2"
  local repodir
  shift 2

  repodir="$(basename "${repourl%.git}")"
  rm -rf "$repodir"

  local max_retries=3
  local count=0
  local success=1
  while [ $count -lt $max_retries ]; do
    if git clone --depth=1 -b "$branch" --single-branch --filter=blob:none --sparse "$repourl" "$repodir"; then
      success=0
      break
    fi
    count=$((count + 1))
    echo "Warning: git sparse clone failed for $repourl. Retrying ($count/$max_retries)..."
    sleep 3
  done

  if [ $success -ne 0 ]; then
    echo "Error: git sparse clone failed for $repourl after $max_retries attempts." >&2
    return 1
  fi

  (
    cd "$repodir"
    git sparse-checkout set "$@"
    mv -f "$@" ../package
  )
  rm -rf "$repodir"
}

#  & nginx & Go & frp & UPnP & Wol & Argon & Aurora & OpenList & Lucky & wechatpush & OpenAppFilter & 集客无线AC控制器 & 雅典娜LED控制
git_sparse_clone aria2 https://github.com/laipeng668/packages net/aria2
mv -f package/aria2 feeds/packages/net/aria2
git_sparse_clone nginx https://github.com/laipeng668/packages net/nginx
mv -f package/nginx feeds/packages/net/nginx
git_sparse_clone ariang https://github.com/laipeng668/packages net/ariang
mv -f package/ariang feeds/packages/net/ariang
git_sparse_clone master https://github.com/laipeng668/packages lang/golang
mv -f package/golang feeds/packages/lang/golang
git_sparse_clone frp-binary-toml https://github.com/laipeng668/packages net/frp
mv -f package/frp feeds/packages/net/frp
git_sparse_clone frp-toml https://github.com/laipeng668/luci applications/luci-app-frpc applications/luci-app-frps
mv -f package/luci-app-frpc feeds/luci/applications/luci-app-frpc
mv -f package/luci-app-frps feeds/luci/applications/luci-app-frps
git_sparse_clone master https://github.com/immortalwrt/packages net/miniupnpd
mv -f package/miniupnpd feeds/packages/net/miniupnpd
git_sparse_clone master https://github.com/immortalwrt/luci applications/luci-app-upnp
mv -f package/luci-app-upnp feeds/luci/applications/luci-app-upnp
git_sparse_clone master https://github.com/immortalwrt/luci applications/luci-app-wol
mv -f package/luci-app-wol feeds/luci/applications/luci-app-wol
git_clone https://github.com/jerrykuku/luci-theme-argon feeds/luci/themes/luci-theme-argon
git_clone https://github.com/jerrykuku/luci-app-argon-config feeds/luci/applications/luci-app-argon-config
git_clone https://github.com/eamonxg/luci-theme-aurora feeds/luci/themes/luci-theme-aurora
git_clone https://github.com/eamonxg/luci-app-aurora-config feeds/luci/applications/luci-app-aurora-config
git_clone https://github.com/laipeng668/luci-app-openlist2 package/openlist2
git_clone https://github.com/gdy666/luci-app-lucky package/luci-app-lucky
git_clone https://github.com/tty228/luci-app-wechatpush package/luci-app-wechatpush
git_clone https://github.com/destan19/OpenAppFilter.git package/OpenAppFilter
git_clone https://github.com/laipeng668/luci-app-gecoosac package/luci-app-gecoosac
git_clone https://github.com/NONGFAH/luci-app-athena-led package/luci-app-athena-led
chmod +x package/luci-app-athena-led/root/etc/init.d/athena_led package/luci-app-athena-led/root/usr/sbin/athena-led

# 克隆个人自定义插件包仓库 (包含 DHCP 中文备注插件 luci-app-dhcp-comment)
git_clone https://github.com/ybjbox/openwrt-packages package/openwrt-packages

# 移除 wrtbwmon 克隆以规避旧版 iptables 拦截链
# git_clone https://github.com/brvphoenix/wrtbwmon.git package/wrtbwmon
# git_clone https://github.com/brvphoenix/luci-app-wrtbwmon.git package/luci-app-wrtbwmon

# 克隆 sbwml 的 quickfile 极速网页文件管理器
git_clone https://github.com/sbwml/luci-app-quickfile.git package/luci-app-quickfile

# 替换为最新官方版 SmartDNS 核心与 LuCI
git_clone https://github.com/pymumu/openwrt-smartdns package/smartdns
git_clone https://github.com/pymumu/luci-app-smartdns package/luci-app-smartdns

# 修复 GCC 14 / Musl 环境下严苛 Warning 导致 SmartDNS 编译中断的问题并跳过 Hash 校验
if [ -f package/smartdns/Makefile ]; then
    sed -i 's/PKG_MIRROR_HASH:=.*/PKG_MIRROR_HASH:=skip/g' package/smartdns/Makefile
    sed -i 's/PKG_HASH:=.*/PKG_HASH:=skip/g' package/smartdns/Makefile
    echo 'TARGET_CFLAGS += -Wno-error -Wno-format-security' >> package/smartdns/Makefile
fi

# 替换为最新社区版 MosDNS 核心与 LuCI
git_clone https://github.com/sbwml/luci-app-mosdns package/luci-app-mosdns

### PassWall & OpenClash ###

# 移除 OpenWrt Feeds 自带的核心库
rm -rf feeds/packages/net/{xray-core,v2ray-geodata,sing-box,chinadns-ng,dns2socks,hysteria,ipt2socks,microsocks,naiveproxy,shadowsocks-libev,shadowsocks-rust,shadowsocksr-libev,simple-obfs,tcping,trojan-plus,tuic-client,v2ray-plugin,xray-plugin,geoview,shadow-tls}
git_clone https://github.com/Openwrt-Passwall/openwrt-passwall-packages package/passwall-packages

# 移除 OpenWrt Feeds 过时的LuCI版本
rm -rf feeds/luci/applications/luci-app-passwall
rm -rf feeds/luci/applications/luci-app-openclash
git_clone https://github.com/Openwrt-Passwall/openwrt-passwall package/luci-app-passwall
git_clone https://github.com/Openwrt-Passwall/openwrt-passwall2 package/luci-app-passwall2
git_clone https://github.com/vernesong/OpenClash package/luci-app-openclash

# 清理 PassWall 的 chnlist 规则文件
echo "baidu.com"  > package/luci-app-passwall/luci-app-passwall/root/usr/share/passwall/rules/chnlist

# 克隆 Bandix 流量监控插件及其后端依赖
git_clone https://github.com/timsaya/luci-app-bandix package/luci-app-bandix
git_clone https://github.com/timsaya/openwrt-bandix package/openwrt-bandix

# 将 bandix 移动到“服务”选项里
if [ -d package/luci-app-bandix ]; then
    find package/luci-app-bandix -type f -exec sed -i 's/admin\/network\/bandix/admin\/services\/bandix/g' {} +
    find package/luci-app-bandix -type f -exec sed -i 's/{"admin", "network", "bandix"}/{"admin", "services", "bandix"}/g' {} +
fi

# 自动注入易有云官方订阅源，完美解决 quickstart、istorex 与 iStore 商店的所有编译依赖
# echo 'src-git nas https://github.com/linkease/nas-packages.git;master' >> feeds.conf.default
# echo 'src-git nas_luci https://github.com/linkease/nas-packages-luci.git;main' >> feeds.conf.default
# echo 'src-git istore https://github.com/linkease/istore;main' >> feeds.conf.default

./scripts/feeds update -i -a
./scripts/feeds install -a


# 动态注入 GitHub Secrets 敏感变量至 athena-custom 插件包中
athena_settings="package/openwrt-packages/athena-custom/files/etc/uci-defaults/99-athena-custom-settings"
if [ -f "$athena_settings" ]; then
    echo "Injecting secrets into $athena_settings..."
    sed -i "s/__MY_PPPOE_USERNAME__/${MY_PPPOE_USERNAME:-}/g" "$athena_settings"
    sed -i "s/__MY_PPPOE_PASSWORD__/${MY_PPPOE_PASSWORD:-}/g" "$athena_settings"
    sed -i "s/__MY_WIFI_SSID_2G__/${MY_WIFI_SSID_2G:-}/g" "$athena_settings"
    sed -i "s/__MY_WIFI_SSID_5G__/${MY_WIFI_SSID_5G:-}/g" "$athena_settings"
    sed -i "s/__MY_WIFI_PASSWORD__/${MY_WIFI_PASSWORD:-}/g" "$athena_settings"
    sed -i "s/__MY_ADMIN_PASSWORD__/${MY_ADMIN_PASSWORD:-}/g" "$athena_settings"
    echo "Secrets injection completed for athena-custom."
fi





