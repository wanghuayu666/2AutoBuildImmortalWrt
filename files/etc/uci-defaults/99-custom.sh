#!/bin/sh
# 99-custom.sh 是 immortalwrt 固件首次启动时运行的脚本，位于 /etc/uci-defaults/99-custom.sh
# Log file for debugging
LOGFILE="/tmp/uci-defaults-log.txt"
echo "Starting 99-custom.sh at $(date)" >> $LOGFILE

# 设置默认防火墙规则，方便虚拟机首次访问 WebUI
uci set firewall.@zone[1].input='ACCEPT'

# 设置主机名映射，解决安卓原生 TV 无法联网的问题
uci add dhcp domain
uci set "dhcp.@domain[-1].name=time.android.com"
uci set "dhcp.@domain[-1].ip=203.107.6.88"

# 读取 PPPoE 账号配置文件
SETTINGS_FILE="/etc/config/pppoe-settings"
if [ -f "$SETTINGS_FILE" ]; then
    . "$SETTINGS_FILE"
else
    echo "PPPoE settings file not found. Skipping." >> $LOGFILE
fi

# 初始化变量
lan_ifnames=""
wan_ifname="eth1"
wan1_ifname="eth2"

# 遍历所有网卡
for iface in /sys/class/net/*; do
  iface_name=$(basename "$iface")
  # 过滤回环接口
  if [ "$iface_name" != "lo" ]; then
    # eth1 和 eth2 作为 WAN 口
    if [ "$iface_name" != "$wan_ifname" ] && [ "$iface_name" != "$wan1_ifname" ]; then
      lan_ifnames="$lan_ifnames $iface_name"
    fi
  fi
done
# 删除多余空格
lan_ifnames=$(echo "$lan_ifnames" | awk '{$1=$1};1')

# 配置 WAN 口 (eth1)
uci set network.wan=interface
uci set network.wan.device="$wan_ifname"
uci set network.wan.proto='pppoe'
uci set network.wan.username="${pppoe_account:-'default_user'}"
uci set network.wan.password="${pppoe_password:-'default_pass'}"
uci set network.wan.peerdns='1'
uci set network.wan.auto='1'

# 配置 WAN1 口 (eth2)
uci set network.wan1=interface
uci set network.wan1.device="$wan1_ifname"
uci set network.wan1.proto='pppoe'
uci set network.wan1.username="${pppoe_account:-'default_user'}"
uci set network.wan1.password="${pppoe_password:-'default_pass'}"
uci set network.wan1.peerdns='1'
uci set network.wan1.auto='1'

echo "WAN and WAN1 configured as PPPoE at $(date)" >> $LOGFILE

# 配置 LAN 口为静态 IP
uci set network.lan.proto='static'
uci set network.lan.device='br-lan'
uci set network.lan.ipaddr='192.168.99.1'
uci set network.lan.netmask='255.255.255.0'
uci set network.lan.gateway='192.168.99.1'
uci set network.lan.dns='223.5.5.5 8.8.8.8'

# 查找 `br-lan` 设备的 section
section=$(uci show network | awk -F '[.=]' '/\.@?device\[\d+\]\.name=.br-lan.$/ {print $2; exit}')
if [ -z "$section" ]; then
   echo "error: cannot find device 'br-lan'." >> $LOGFILE
else
   # 清空 `br-lan` 绑定的网口
   uci -q delete "network.$section.ports"
   # 绑定所有 LAN 口
   for port in $lan_ifnames; do
      uci add_list "network.$section.ports"="$port"
   done
   echo "LAN ports ($lan_ifnames) have been assigned to 'br-lan'." >> $LOGFILE
fi

# 设置所有网口可访问网页终端
uci delete ttyd.@ttyd[0].interface

# 设置所有网口可连接 SSH
uci set dropbear.@dropbear[0].Interface=''
uci commit

# 设置编译作者信息
FILE_PATH="/etc/openwrt_release"
NEW_DESCRIPTION="Compiled by 半岛饭盒"
sed -i "s/DISTRIB_DESCRIPTION='[^']*'/DISTRIB_DESCRIPTION='$NEW_DESCRIPTION'/" "$FILE_PATH"

exit 0
