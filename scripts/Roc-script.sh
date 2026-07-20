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


# ================= 写入首开自定义初始配置 (uci-defaults) =================
mkdir -p package/base-files/files/etc/uci-defaults
cat << EOF > package/base-files/files/etc/uci-defaults/99-custom-settings
#!/bin/sh

# 1. 默认 PPPoE 拨号设置 (仅在凭据不为空时配置，否则保留默认 DHCP 模式)
if [ -n "${MY_PPPOE_USERNAME}" ] && [ -n "${MY_PPPOE_PASSWORD}" ]; then
    uci set network.wan.proto='pppoe'
    uci set network.wan.username='${MY_PPPOE_USERNAME}'
    uci set network.wan.password='${MY_PPPOE_PASSWORD}'
fi

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
    
    # 动态获取该物理网卡的频段 (2G 或 5G)
    hw_band=\$(uci -q get wireless.\$dev_name.band)
    hw_mode=\$(uci -q get wireless.\$dev_name.hwmode)
    
    if [ "\$hw_band" = "2g" ] || [ "\$hw_mode" = "11g" ]; then
        # 判定为 2.4G 网卡，使用 2G SSID
        uci set wireless.@wifi-iface[\$wireless_idx].ssid='${MY_WIFI_SSID_2G}'
    else
        # 判定为 5G 网卡，使用 5G SSID，实现漫游切换
        uci set wireless.@wifi-iface[\$wireless_idx].ssid='${MY_WIFI_SSID_5G}'
    fi
    
    # 统一无线安全加密协议与 WiFi 密码
    uci set wireless.@wifi-iface[\$wireless_idx].encryption='psk2'
    uci set wireless.@wifi-iface[\$wireless_idx].key='${MY_WIFI_PASSWORD}'
    wireless_idx=\$((\$wireless_idx + 1))
done

# 启用所有无线网卡，并根据频段自适应配置信道与频宽
radio_idx=0
while uci get wireless.radio\$radio_idx >/dev/null 2>&1; do
    uci set wireless.radio\$radio_idx.disabled='0'
    
    hw_band=\$(uci -q get wireless.radio\$radio_idx.band)
    hw_mode=\$(uci -q get wireless.radio\$radio_idx.hwmode)
    
    # 2.4G 频段：强锁为 11 信道，且限制在最大 20MHz 频宽以减少同频干扰
    if [ "\$hw_band" = "2g" ] || [ "\$hw_mode" = "11g" ]; then
        uci set wireless.radio\$radio_idx.channel='11'
        uci set wireless.radio\$radio_idx.htmode='HT20'
    else
        # 5G 频段：保留自动信道
        uci set wireless.radio\$radio_idx.channel='auto'
    fi

    radio_idx=\$((\$radio_idx + 1))
done

# 4. 默认主题设置为 Aurora
uci set luci.main.mediaurlbase='/luci-static/aurora'

# 4.5 适配 QuickFile 文件管理器的 Nginx 监听与 SSL 重定向设置（避免 HTTP 重定向到 SSL 导致 x509 证书校验失败）
if [ -f /etc/config/nginx ]; then
    uci set nginx.global.uci_enable='true'
    uci del nginx._lan 2>/dev/null || true
    uci del nginx._redirect2ssl 2>/dev/null || true
    uci add nginx server >/dev/null 2>&1 || true
    uci rename nginx.@server[0]='_lan' 2>/dev/null || true
    uci set nginx._lan.server_name='_lan'
    uci add_list nginx._lan.listen='80 default_server'
    uci add_list nginx._lan.listen='[::]:80 default_server'
    uci add_list nginx._lan.include='conf.d/*.locations'
    uci set nginx._lan.access_log='off; # logd openwrt'
    uci commit nginx
fi

# 4.6 解除 uWSGI 进程的虚拟内存上限 (limit-as = 1000)，防止 Go 语言二进制（如 Lucky）在堆内存分配时抛出 SIGSEGV 崩溃导致界面显示“未安装”
sed -i 's/limit-as = 1000/; limit-as = 1000/g' /etc/uwsgi/vassals/*.ini 2>/dev/null || true
/etc/init.d/uwsgi restart 2>/dev/null || true

# 5. 提交并应用所有配置
uci commit network
uci commit dhcp
uci commit wireless
uci commit luci

# 6. 修改默认后台密码（使用 passwd 管道替代不支持的 chpasswd）
if [ -n "${MY_ADMIN_PASSWORD}" ]; then
    echo -e "${MY_ADMIN_PASSWORD}\n${MY_ADMIN_PASSWORD}" | passwd root
fi

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
#    注: keep.d 目录文件仅作为备份白名单(cat 并作为 find 参数)，不可作为脚本执行。
#    此处直接在编译期通过 sed 修改 sysupgrade 脚本，在打包前动态过滤 conffiles 列表。
if [ -f package/base-files/files/sbin/sysupgrade ]; then
    python3 -c '
path = "package/base-files/files/sbin/sysupgrade"
try:
    with open(path, "r", encoding="utf-8") as f: content = f.read()
    if "smart_weight_data" not in content:
        content = content.replace("s,^/", "sed -i \"/smart_weight_data/d\" \"$CONFFILES\"\ns,^/")
        with open(path, "w", encoding="utf-8") as f: f.write(content)
except Exception: pass
'
fi

# 在 LuCI DHCP 静态地址分配界面添加中文备注 (Comment) 控件，并在活动租约列表中同步显示备注
dhcp_src="feeds/luci/modules/luci-mod-network/htdocs/luci-static/resources/view/network/dhcp.js"
if [ -f "$dhcp_src" ]; then
    python3 -c '
path = "feeds/luci/modules/luci-mod-network/htdocs/luci-static/resources/view/network/dhcp.js"
try:
    with open(path, "r", encoding="utf-8") as f: code = f.read()

    # 1. 静态分配编辑弹窗中插入单行注释框控件 (使用独立变量 co, 避开重复与属性继承 bug)
    if "var co = ss.option" not in code:
        target1 = "so = ss.option(form.Value, \x27leasetime\x27,"
        replacement1 = "var co = ss.option(form.Value, \x27comment\x27, _(\x27Comment\x27));\n\t\tco.rmempty = true;\n\n\t\t" + target1
        code = code.replace(target1, replacement1)

    # 2. 在 poll.add 内部并行异步加载 callDHCPLeases() 与 uci.load("dhcp") (不干扰 render 参数解构)
    if "mac_comments" not in code:
        target2 = "return callDHCPLeases().then(function(leaseinfo) {"
        replacement2 = "return Promise.all([ callDHCPLeases(), L.resolveDefault(uci.load(\x27dhcp\x27)) ]).then(function(res) {\n\t\t\t\t\tconst leaseinfo = res[0] || {};\n\t\t\t\t\tconst mac_comments = {}; uci.sections(\x27dhcp\x27, \x27host\x27).forEach(function(s) { L.toArray(s.mac).forEach(function(m) { if (s.comment) mac_comments[m.toLowerCase()] = s.comment; }); });"
        code = code.replace(target2, replacement2)

        # 3. 替换 IPv4 活动租约的 host 拼接与 %s (优化格式避免嵌套冗长)
        code = code.replace(
            "const columns = [\n\t\t\t\t\t\t\t\t\x27%h\x27.format(host || \x27-\x27),",
            "let cmt = lease.macaddr ? mac_comments[lease.macaddr.toLowerCase()] : null;\n\t\t\t\t\t\t\tif (cmt) { let raw_h = lease.hostname || name; host = raw_h ? (cmt + \x27 (\x27 + raw_h + \x27)\x27) : cmt; }\n\n\t\t\t\t\t\t\tconst columns = [\n\t\t\t\t\t\t\t\t\x27%s\x27.format(host || \x27-\x27),"
        )

        # 4. 替换 IPv6 活动租约的 host 拼接与 %s
        code = code.replace(
            "const columns = [\n\t\t\t\t\t\t\t\t\x27%h\x27.format(host || \x27-\x27),\n\t\t\t\t\t\t\t\tlease.ip6addrs",
            "let cmt6 = lease.macaddr ? mac_comments[lease.macaddr.toLowerCase()] : null;\n\t\t\t\t\t\t\tif (cmt6) { let raw_h = lease.hostname || name; host = raw_h ? (cmt6 + \x27 (\x27 + raw_h + \x27)\x27) : cmt6; }\n\n\t\t\t\t\t\t\tconst columns = [\n\t\t\t\t\t\t\t\t\x27%s\x27.format(host || \x27-\x27),\n\t\t\t\t\t\t\t\tlease.ip6addrs"
        )

    with open(path, "w", encoding="utf-8") as f: f.write(code)
except Exception as e:
    print("dhcp patch error:", e)
'
fi

# 在“状态 - 概览” (Status Overview) 页面的 DHCP 活动租约列表中同步显示中文备注
dhcp_status_src="feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/40_dhcp.js"
if [ -f "$dhcp_status_src" ]; then
    python3 -c '
path = "feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/40_dhcp.js"
try:
    with open(path, "r", encoding="utf-8") as f: code = f.read()

    if "uci.load(\x27dhcp\x27)" not in code:
        code = code.replace("network.getHostHints()", "network.getHostHints(),\n\t\t\tuci.load(\x27dhcp\x27)")

    if "mac_comments" not in code:
        target = "var leases = Array.isArray(leaseinfo.dhcp_leases)"
        helper = "var mac_comments = {}; uci.sections(\x27dhcp\x27, \x27host\x27).forEach(function(s) { L.toArray(s.mac).forEach(function(m) { if (s.comment) mac_comments[m.toLowerCase()] = s.comment; }); });\n\t\t"
        code = code.replace(target, helper + target)

        code = code.replace(
            "\x27%h\x27.format(host || \x27-\x27)",
            "let cmt = lease.macaddr ? mac_comments[lease.macaddr.toLowerCase()] : null;\n\t\t\tif (cmt) { let raw_h = lease.hostname || name; host = raw_h ? (cmt + \x27 (\x27 + raw_h + \x27)\x27) : cmt; }\n\t\t\treturn \x27%s\x27.format(host || \x27-\x27)"
        )

    with open(path, "w", encoding="utf-8") as f: f.write(code)
except Exception as e:
    print("40_dhcp patch error:", e)
'
fi

