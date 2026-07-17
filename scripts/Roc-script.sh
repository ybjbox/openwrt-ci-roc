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
rm -rf feeds/packages/net/open-app-filter
rm -rf feeds/packages/net/miniupnpd
rm -rf feeds/packages/net/ariang
rm -rf feeds/packages/net/aria2
rm -rf feeds/packages/net/nginx
rm -rf feeds/packages/net/frp
rm -rf feeds/packages/lang/golang

# Git稀疏克隆，只克隆指定目录到本地
function git_sparse_clone() {
  local branch="$1"
  local repourl="$2"
  local repodir
  shift 2

  repodir="$(basename "${repourl%.git}")"
  rm -rf "$repodir"
  git clone --depth=1 -b "$branch" --single-branch --filter=blob:none --sparse "$repourl" "$repodir"
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
git clone --depth=1 https://github.com/jerrykuku/luci-theme-argon feeds/luci/themes/luci-theme-argon
git clone --depth=1 https://github.com/jerrykuku/luci-app-argon-config feeds/luci/applications/luci-app-argon-config
git clone --depth=1 https://github.com/eamonxg/luci-theme-aurora feeds/luci/themes/luci-theme-aurora
git clone --depth=1 https://github.com/eamonxg/luci-app-aurora-config feeds/luci/applications/luci-app-aurora-config
git clone --depth=1 https://github.com/laipeng668/luci-app-openlist2 package/openlist2
git clone --depth=1 https://github.com/gdy666/luci-app-lucky package/luci-app-lucky
git clone --depth=1 https://github.com/tty228/luci-app-wechatpush package/luci-app-wechatpush
git clone --depth=1 https://github.com/destan19/OpenAppFilter.git package/OpenAppFilter
git clone --depth=1 https://github.com/laipeng668/luci-app-gecoosac package/luci-app-gecoosac
git clone --depth=1 https://github.com/NONGFAH/luci-app-athena-led package/luci-app-athena-led
chmod +x package/luci-app-athena-led/root/etc/init.d/athena_led package/luci-app-athena-led/root/usr/sbin/athena-led

### PassWall & OpenClash ###

# 移除 OpenWrt Feeds 自带的核心库
rm -rf feeds/packages/net/{xray-core,v2ray-geodata,sing-box,chinadns-ng,dns2socks,hysteria,ipt2socks,microsocks,naiveproxy,shadowsocks-libev,shadowsocks-rust,shadowsocksr-libev,simple-obfs,tcping,trojan-plus,tuic-client,v2ray-plugin,xray-plugin,geoview,shadow-tls}
git clone --depth=1 https://github.com/Openwrt-Passwall/openwrt-passwall-packages package/passwall-packages

# 移除 OpenWrt Feeds 过时的LuCI版本
rm -rf feeds/luci/applications/luci-app-passwall
rm -rf feeds/luci/applications/luci-app-openclash
git clone --depth=1 https://github.com/Openwrt-Passwall/openwrt-passwall package/luci-app-passwall
git clone --depth=1 https://github.com/Openwrt-Passwall/openwrt-passwall2 package/luci-app-passwall2
git clone --depth=1 https://github.com/vernesong/OpenClash package/luci-app-openclash

# 清理 PassWall 的 chnlist 规则文件
echo "baidu.com"  > package/luci-app-passwall/luci-app-passwall/root/usr/share/passwall/rules/chnlist

# 克隆 Bandix 流量监控插件及其后端依赖
git clone --depth=1 https://github.com/timsaya/luci-app-bandix package/luci-app-bandix
git clone --depth=1 https://github.com/timsaya/openwrt-bandix package/openwrt-bandix

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


# ================= 写入首开自定义初始配置 (uci-defaults) =================
mkdir -p package/base-files/files/etc/uci-defaults
cat << EOF > package/base-files/files/etc/uci-defaults/99-custom-settings
#!/bin/sh

# 1. 默认 PPPoE 拨号设置
uci set network.wan.proto='pppoe'
uci set network.wan.username='${MY_PPPOE_USERNAME}'
uci set network.wan.password='${MY_PPPOE_PASSWORD}'

# 2. 默认关闭 IPv6 支持
uci set network.wan6.disabled='1'
uci set network.lan.delegate='0'
uci set network.lan.ipv6='0'
uci set network.wan.ipv6='0'
uci set dhcp.lan.dhcpv6='disabled'
uci -q delete dhcp.lan.ra
uci -q delete dhcp.lan.dhcpv6
/etc/init.d/odhcpd disable

# 3. 默认无线配置 (2.4G 与双5G 独立命名，双5G 名字相同实现自动无缝漫游)
wireless_idx=0
while uci get wireless.@wifi-iface[\$wireless_idx] >/dev/null 2>&1; do
    # 获取该无线接口所绑定的物理网卡设备名 (如 radio0, radio1, radio2)
    dev_name=\$(uci get wireless.@wifi-iface[\$wireless_idx].device)
    
    if [ "\$dev_name" = "radio1" ]; then
        # radio1 对应 2.4G 网卡，使用 2G SSID
        uci set wireless.@wifi-iface[\$wireless_idx].ssid='${MY_WIFI_SSID_2G}'
    else
        # radio0 和 radio2 均为 5G 网卡，共享 5G SSID，实现客户端自适应漫游切换
        uci set wireless.@wifi-iface[\$wireless_idx].ssid='${MY_WIFI_SSID_5G}'
    fi
    
    # 统一无线安全加密协议与 WiFi 密码
    uci set wireless.@wifi-iface[\$wireless_idx].encryption='psk2'
    uci set wireless.@wifi-iface[\$wireless_idx].key='${MY_WIFI_PASSWORD}'
    wireless_idx=\$((\$wireless_idx + 1))
done

# 启用所有无线网卡，并配置自动信道
radio_idx=0
while uci get wireless.radio\$radio_idx >/dev/null 2>&1; do
    uci set wireless.radio\$radio_idx.disabled='0'
    uci set wireless.radio\$radio_idx.channel='auto'   # 将所有物理网卡的信道设置为自动模式
    
    # 2.4G 频段 (radio1 - IPQ 集成)：强锁为 802.11n 信号，且限制在最大 20MHz 频宽
    if [ "\$radio_idx" = "1" ]; then
        uci set wireless.radio1.htmode='HT20'       # 设定为 HT20 (802.11n 20MHz 频宽)
    fi

    radio_idx=\$((\$radio_idx + 1))
done

# 4. 默认主题设置为 Aurora
uci set luci.main.mediaurlbase='/luci-static/aurora'

# 5. 提交并应用所有配置
uci commit network
uci commit dhcp
uci commit wireless
uci commit luci

# 6. 修改默认后台密码（实际不生效）
# echo "root:${MY_ADMIN_PASSWORD}" | chpasswd

# 7. 修改默认软件源为南京大学源（仅适用于 25.12 新版 apk）
if [ -f /etc/apk/repositories.d/distfeeds.list ]; then
    sed -i -e '/istore/!{/nas/!s,https://downloads.immortalwrt.org,https://mirror.nju.edu.cn/immortalwrt,g}' \
           -e 's,https://mirrors.vsean.net/openwrt,https://mirror.nju.edu.cn/immortalwrt,g' \
           /etc/apk/repositories.d/distfeeds.list
fi
exit 0
EOF
chmod +x package/base-files/files/etc/uci-defaults/99-custom-settings

# 8. 升级保留配置时剔除 OpenClash 智能权重大数据(smart_weight_data.csv 及其备份)
#    否则 sysupgrade 打包这几百MB文件会卡死, 导致 LuCI "保留配置升级" 无响应
mkdir -p package/base-files/files/lib/upgrade/keep.d
cat << 'KEEPEOF' > package/base-files/files/lib/upgrade/keep.d/99-trim-openclash
#!/bin/sh
# sysupgrade 收集 conffiles 后、打包前执行(由 /lib/upgrade/keep.d 机制触发)
# 从保留配置清单剔除 OpenClash 运行时大数据, 避免升级卡死
CONF="/tmp/sysupgrade.conffiles"
if [ -f "$CONF" ]; then
    sed -i '/smart_weight_data/d' "$CONF"
fi
KEEPEOF
chmod +x package/base-files/files/lib/upgrade/keep.d/99-trim-openclash
