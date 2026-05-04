#!/bin/bash

set -e

# 检查依赖
for cmd in nvidia-settings nvidia-smi Xorg; do
    if ! command -v $cmd >/dev/null 2>&1; then
        echo "❌ 缺少依赖: $cmd，请先安装！"
        exit 1
    fi
done

# ==================== 配置区（可自定义）====================
# 温度回差（解决抖动核心：避免阈值附近反复切换）
HYSTERESIS=2
# 转速曲线（℃ → %）
IDLE_SPEED=30     # 低温默认转速
# ==========================================================

export DISPLAY=:1


# 启动稳定的虚拟X服务器
if ! pgrep -x "Xorg" > /dev/null; then
    echo "启动虚拟显示器..."
    sudo Xorg :1 -config /etc/X11/xorg.conf -noreset -nolisten tcp -background none &
    sleep 3
fi


# 检查sudo权限（建议配置免密）
if ! sudo -n true 2>/dev/null; then
    echo "❌ 需要sudo权限，请配置免密sudo或提前输入一次密码。"
    sudo true || exit 1
fi

# 启用手动风扇控制
echo "启用手动风扇控制..."
sudo nvidia-settings -a "[gpu:0]/GPUFanControlState=1" > /dev/null 2>&1
sleep 1


# 上一次转速（用于防抖）
LAST_SPEED=$IDLE_SPEED

echo "✅ 风扇控制已启动（带滞回防抖）"
echo "----------------------------------------"

# 主监控循环
while true; do

    # 获取GPU当前温度
    TEMP=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>/dev/null)
    if ! [[ $TEMP =~ ^[0-9]+$ ]]; then
        echo "⚠️ 读取温度失败，nvidia-smi输出: $TEMP"
        sleep 5
        continue
    fi

    # 温度-转速逻辑（带滞回，彻底解决抖动）
    if [ "$TEMP" -lt $((50 - HYSTERESIS)) ]; then
        SPEED=$IDLE_SPEED
    elif [ "$TEMP" -lt $((55 - HYSTERESIS)) ]; then
        SPEED=40
    elif [ "$TEMP" -lt $((60 - HYSTERESIS)) ]; then
        SPEED=50
    elif [ "$TEMP" -lt $((65 - HYSTERESIS)) ]; then
        SPEED=60
    elif [ "$TEMP" -lt $((70 - HYSTERESIS)) ]; then
        SPEED=70
    elif [ "$TEMP" -lt $((75 - HYSTERESIS)) ]; then
        SPEED=80
    elif [ "$TEMP" -lt $((80 - HYSTERESIS)) ]; then
        SPEED=100
    else
        SPEED=100
    fi

    # 只有转速变化时才设置（减少系统调用，更安静）
    if [ "$SPEED" -ne "$LAST_SPEED" ]; then
        sudo nvidia-settings -a "[fan:0]/GPUTargetFanSpeed=$SPEED" > /dev/null 2>&1
        echo "温度: $TEMP℃ | 转速: $SPEED%"
        LAST_SPEED=$SPEED
    fi

    sleep 2
done
