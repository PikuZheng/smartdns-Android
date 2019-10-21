#!/system/bin/sh

[[ "$#" -eq 0 ]] && { echo "! Null input !"; exit 1; }
[[ $(id -u) -ne 0 ]] && { echo "! Need root !"; exit 1; }

LPORT=6453
ipt_block_IPv6_OUTPUT=true

MODDIR="/data/adb/modules/smartdns"
source $MODDIR/constant.sh



## 防火墙
# 主控
function iptrules_on()
{
	iptrules_load $IPTABLES -I
	ip6trules_load -A OUTPUT
}

function iptrules_off()
{
	while iptrules_check; do
		iptrules_load $IPTABLES -D
		ip6trules_load -D OUTPUT
	done
}

function ip6trules_load()
{
	if [ "$ipt_block_IPv6_OUTPUT" == 'true' ]; then
		block_load $IP6TABLES $1 $2
	else
		iptrules_load $IP6TABLES $1
	fi
}

# 初始化
function iptrules_set()
{
	echo "$1 Set up $2"
	$1 -t nat -N DNS_LOCAL
	$1 -t nat -N DNS_EXTERNAL

	$1 -t nat -A DNS_LOCAL -m owner --uid-owner $UID -j RETURN
	for IPP in 'udp' 'tcp'
	do
		$1 -t nat -A DNS_LOCAL -p $IPP ! --dport 53 -j RETURN
		$1 -t nat -A DNS_LOCAL -p $IPP -j DNAT --to-destination $2:$LPORT

		$1 -t nat -A DNS_EXTERNAL -p $IPP ! --dport 53 -j RETURN
		$1 -t nat -A DNS_EXTERNAL -p $IPP -j DNAT --to-destination $2:$LPORT
	done
}

# 清除规则
function iptrules_reset()
{
	echo "Reset $1"
	$1 -t nat -F DNS_LOCAL
	$1 -t nat -X DNS_LOCAL

	$1 -t nat -F DNS_EXTERNAL
	$1 -t nat -X DNS_EXTERNAL
}

# 加载
function iptrules_load()
{
	echo "$1 $2"
	for IPP in 'udp' 'tcp'
	do
		$1 -t nat $2 OUTPUT -p $IPP -j DNS_LOCAL
		$1 -t nat $2 PREROUTING -p $IPP -j DNS_EXTERNAL
	done
}

function block_load()
{
	$1 -t filter $2 $3 -p udp --dport 53 -j DROP
	$1 -t filter $2 $3 -p tcp --dport 53 -j REJECT --reject-with tcp-reset
}



## 检查
# 防火墙规则
function iptrules_check()
{
	[ -n "`$IPTABLES -n -t nat -L OUTPUT | grep "DNS_LOCAL"`" ] && return 0
}

# 核心进程
function core_check()
{
	[ -n "`pgrep $CORE_BINARY`" ] && return 0
}



## 其他
# (重)启动核心
function core_start()
{
	core_check && killall $CORE_BINARY
	sleep 1
	echo "- Starting [$(date +'%d/%r')]"
	$CORE_BOOT &
	sleep 1
	if [ ! core_check ]; then
		echo '(!) Fails: Core not working'; exit 1
	fi
}




### 命令
case $1 in
	# 启动
	-start)
		iptrules_off
		core_start
		if core_check; then
			iptrules_on
		fi
	;;
	# 停止
	-stop)
		iptrules_off
		killall $CORE_BINARY
	;;
	# 检查状态
	-status)
		i=0;
		core_check && { echo '< Core Online >'; }||{ echo '! Core Offline !'; i=`expr $i + 2`; }
		iptrules_check && { echo '< iprules Enabled >'; }||{ echo '! iprules Disabled !'; i=`expr $i + 1`; }
	case $i in
	3)
	exit 11 ;;
	2)
	exit 01 ;;
	1)
	exit 10 ;;
	0)
	exit 00 ;;
	esac
	;;
	# 仅启动核心
	-start-core)
		core_start
	;;
	# 帮助信息
	-usage)
cat <<EOD
Usage:
 -start
   Start Service
 -stop
   Stop Service
 -status
   Service Status
 -start-core
   Boot core only
 -set
   Set up iptables
 -reset
   Reset iptables
EOD
	;;
####
	# 初始化规则
	-set)
		iptrules_set $IPTABLES '127.0.0.1'
		iptrules_set $IP6TABLES '[::1]'
	;;
	# 清空规则
	-reset)
		iptrules_load $IPTABLES -D
		ip6trules_load -D OUTPUT

		iptrules_reset $IPTABLES
		iptrules_reset $IP6TABLES
		killall $CORE_BINARY
	;;
	# 命令透传
	*)
		$CORE_PATH $*
	;;
esac
exit 0