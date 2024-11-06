+++
title = 'sing-box 的全局透明代理'
date = 2024-11-05T17:18:27+08:00
draft = false
+++
> 背景：近期迁移办公区，工作区附近的 wifi 时灵时不灵，找 IT 来看也无果。虽然平时基本不用 wifi，但我有一台 Dell 主机是连接在 wifi 的局域网内，也就导致了那台主机间歇性不能访问公网。尽管不影响远程开发访问，但时不时断开公网十分影响开发体验。在与公网断开期间，该机器可正常访问本地机房的开发主机（不在同一个局域网网段），而开发主机的网络一直是正常的，便产生 Dell 主机通过机房的开发主机来访问公网的代理思路。

# 方案调研

***Dell 主机简称机器 A，机房的开发主机简称机器 B***

## 常规方案

1. nginx http proxy
在机器 B 上部署 nginx 作为 http 代理，这种方案最简单，但有很多不足的地方。需要在机器 A 上设置诸如`http_proxy`，`https_proxy`等环境变量来显式地配置环境变量来访问机器 B 上的 nginx 代理，另外其代理方式对不仅对 https 的支持一般，而且仅支持 http 这种 L7 协议。

2. iptables + iproute2 + sing-box/v2ray/xray
在机器 A 上配置路由策略以及通过 iptables 进行数据包转发可以实现透明代理的效果，再在机器 B 上部署 sing-box/v2ray/xray 等代理服务以实现公网出口的效果。此方案难点在于机器 A 配置复杂，不仅需要处理好机器 A 本身的出口流量，还要处理好通过经过 A 代理的流量，另外内网流量不走机器 B 也需要进行额外配置；总的算下来，配置条目多，极容易出错。

3. sing-box
这套方案也是实际实行的方案，在机器 A 和机器 B 上各部署一套 sing-box。其中机器 A 作为客户端通过`shadowrocks`协议（这里的协议可以任意选择）与机器 B 进行通信，机器 A 采用 `tun` 虚拟网卡方案处理入口流量。这套方案等同于方案 2 的升级版，通过配置 sing-box 来间接处理主机的路由规则，下面给出两个机器的 sing-box 配置。

* 机器 A: `config.json`

```json
{
 "log": {
    "level": "info"
  },
  "dns": {
    "servers": [
      {
        "address": "tls://8.8.8.8"
      }
    ]
  },
  "inbounds": [
    {
      "type": "tun",
      "tag": "tun-in",
      "interface_name": "sing-box-tun0",
      "address": ["10.225.0.1/30"],
      "auto_route": true,
      "strict_route": false,
      "route_exclude_address": [
        "10.0.0.0/8",
        "172.16.0.0/12",
        "192.168.0.0/16"
      ]
    }
  ],
  "outbounds": [
    {
      "type": "shadowsocks",
      "tag": "ss-out",
      "server": "10.199.1.30",
      "server_port": 8080,
      "method": "2022-blake3-aes-128-gcm",
      "password": "JJJJ",
      "multiplex": {
        "enabled": true
      }
    }
  ],
  "route": {
    "rules": [
      {
        "inbound": "tun-in",
        "outbound":"ss-out"
      }
    ]
  }
}
```

机器 A 的配置比较重要，重点在于 `inbounds` 模块，这里采用的是 `tun` 模式，即虚拟网卡模式，`address` 表示虚拟网卡的虚拟网段地址，这里尽量不与真实局域网望断产生冲突，`route_exclude_address` 即配置某些目的地址不走 `tun` 网卡，这里设置为几个内网的固定网段，防止内网之间的访问仍然走机器 B。

* 机器 B: `config.json`

```json
{
"log": {
    "level": "info"
  },
  "dns": {
    "servers": [
      {
        "address": "tls://8.8.8.8"
      }
    ]
  },
  "inbounds": [
    {
      "type": "shadowsocks",
      "tag": "ss-in",
      "listen": "::",
      "listen_port": 8080,
      "sniff": true,
      "network": "tcp",
      "method": "2022-blake3-aes-128-gcm",
      "multiplex": {
        "enabled": true
      },
      "password": "JJJJ"
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    },
    {
      "type": "dns",
      "tag": "dns-out"
    }
  ],
  "route": {
    "rules": [
      {
        "protocol": "dns",
        "outbound": "dns-out"
      },
      {
        "inbound": "ss-in",
        "outbound": "direct"
      }
    ]
  }
}

```

机器 B 的配置并不重要，只要保证 `outbounds` 模块能被机器 A 的 sing-box 服务访问即可，至于具体应该是什么协议也不重要，毕竟目的是在一个局域网内借助机器 B 访问公网，而不是翻墙。

***NOTES:***

1. 上述的配置中机器 A 的 DNS 请求也转发到了 B，机器 B 上必须配置 DNS 相关的路有规则
2. 机器之间的时间戳相差不能超过 60s
3. 本质上和通过 `tunnel` 设备 + 路由规则劫持请求，大体思路和 `wireguard` 相差不多。
