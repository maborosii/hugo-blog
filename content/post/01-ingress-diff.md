+++
title = '关于三种控制器授权策略配置梳理（kubernetes ingress controller）'
date = 2023-12-26T13:18:27+08:00
draft = false
+++
# 背景

因各种 ingress controller 支持的场景各有不同，导致目前在业务项目中使用了两种入口控制器，分别是 k8s 官方维护的 ingress nginx controller (注意：nginx ingress controller 是 nginx 维护的，并非 k8s 官方维护，一般说的都是指 k8s 维护的入口控制器)，该控制器承担业务侧 http/https 流量，后因该入口控制器不支持在入口处进行四层代理中的 tls 终结，导致最终采用 traefik 作为第二款入口控制器，其承担业务侧 tls 加密的 tcp 流量。

随着业务的发展，金丝雀发布逐渐进入了视野。在 k8s 中使用金丝雀发布必然绕不开服务网格，目前选用的 istio 作为网格组件。当然若只是因为需要金丝雀发布才引入 istio，着实有些大材小用，但因这样的契机引入服务网格，从而反向推动业务侧精细化流量管理也不失为一种所得。在灰度方案测试中，仅使用 istio 的网格功能，对于进出集群的南北流量没有使用 istio 原生的 ingress gateway 以及 egress gateway，仍然由原本的入口控制器承担原来的两种流量。

而我对于运维侧流量与业务侧流量混用业务侧统一入口控制器一直抱有芥蒂，始终觉得非业务流量应与业务侧流量拆开。正是基于这样的背景下，遂试采用第三款入口控制器 istio ingress gateway 来承担运维侧流量，目的有二，一是拆分流量，二是为日后的完全网格化铺路，最终的入口控制器必然会被纳入到 istio 生态之中。

以上介绍的是目前使用的三款入口控制器分别承担的角色，在使用过程中，有些业务系统并不允许对公网开放，仅放行固定的几个公网 IP。目前所有的入口控制器均绑定有公有云厂商的负载均衡器，那么将负载均衡器加入一个既定的安全组，通过安全组策略来进行授权管理即可，但现实情况是在 Azure 中存量的负载均衡器已经绑定有固定的安全组，且该安全组在每次入口控制器进行变更时会将开放的端口重置为默认公网访问；而在 AWS 中，由入口控制器自动创建的存量负载均衡器则不允许绑定安全组。那么将授权措施前置到负载均衡器就显得**十分有限**，只能另辟蹊径在流量通过负载均衡器达到入口控制器的时候进行授权管理，而不同的入口控制器在授权管理方面配置大不相同，这也是本次文章讨论的主题。

# 部署要求

在 K8S 中，由于存在多层网络间的路由和 nat，若需要在入口控制器层根据源 IP 来进行授权管理，则需要确保能在入口控制器里拿到客户端 IP 信息，有如下几点要求：

1. 入口控制器中的 LoadBalancer 类型的 Service 中的`ExternalTrafficPolicy` 参数必须为`Local`，其默认值为`Cluster`，参数背后的原因具体参见 [负载均衡器原理](https://cloud.tencent.com/developer/article/2242345)。
2. istio ingress gateway 中需要确定云厂商托管 K8S 集群默认支持的负载均衡器类型，具体参见 [isto ingress 网关](https://istio.io/latest/zh/docs/tasks/security/authorization/authz-ingress/)以及 [istio 配置 Gateway 网络拓扑](https://istio.io/latest/zh/docs/ops/configuration/traffic-management/network-topologies/)这两篇文章（注：目前 AWS EKS 可通过注解的方式`service.beta.kubernetes.io/aws-load-balancer-type: nlb`指定默认的负载均衡器类型，一般使用 nlb 即网络负载均衡器）。

# 详细配置

> 三种控制器配置明细均适用于 AWS 与 Azure，严格来说这种配置本身只与控制组件有关，平台中立。

## ingress nginx controller

K8S 官方的入口控制器使用白名单注解来实现源 IP 授权管理，在 ingress 规则使用注解 `nginx.ingress.kubernetes.io/whitelist-source-range: "8.8.8.8"` 即可完成白名单配置

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ingress
  namespace: default
  annotations: 
    kubernetes.io/ingress.class: "nginx"
    nginx.ingress.kubernetes.io/whitelist-source-range: "8.8.8.8"
spec:
  rules:
  - host: xxxx.xxxx.com
    http:
      paths:
        - path: /app/
          pathType: Prefix
          backend:
            service:
              name: service-a 
              port:
                number: 80
```

## traefik

当 traefik 作为入口控制器时，推荐使用它自定义的 CR 来完成流量入口规则控制。在其`2.10`版本中其 CRD 所属的 API 资源组有两种，分别为`traefik.containo.us/v1alpha1`以及`traefik.io/v1alpha1`，若查询使用的资源 kind 为短写（不是简写，是指不带 API 前缀的完全名称），则默认指向前者资源组，但目前在其`3.0 alpha`版本中前者资源组已经被废弃，已完全迁移至后者中，其 CRD 对照表如下：

| cr name | apiversion | namespaced | kind |     |
| ------- | ---------- | ---------- | ---- | --- |
| ingressroutes | traefik.containo.us/v1alpha1 | true | IngressRoute |
| ingressroutetcps | traefik.containo.us/v1alpha1 | true | IngressRouteTCP |
| ingressrouteudps | traefik.containo.us/v1alpha1 | true | IngressRouteUDP |
| middlewares | traefik.containo.us/v1alpha1 | true | Middleware |
| middlewaretcps | traefik.containo.us/v1alpha1 | true | MiddlewareTCP |
| serverstransports | traefik.containo.us/v1alpha1 | true | ServersTransport |
| tlsoptions | traefik.containo.us/v1alpha1 | true | TLSOption |
| tlsstores | traefik.containo.us/v1alpha1 | true | TLSStore |
| traefikservices | traefik.containo.us/v1alpha1 | true | TraefikService |
| ingressroutes | traefik.io/v1alpha1 | true | IngressRoute |
| ingressroutetcps | traefik.io/v1alpha1 | true | IngressRouteTCP |
| ingressrouteudps | traefik.io/v1alpha1 | true | IngressRouteUDP |
| middlewares | traefik.io/v1alpha1 | true | Middleware |
| middlewaretcps | traefik.io/v1alpha1 | true | MiddlewareTCP |
| serverstransports | traefik.io/v1alpha1 | true | ServersTransport |
| serverstransporttcps | traefik.io/v1alpha1 | true | ServersTransportTCP |
| tlsoptions | traefik.io/v1alpha1 | true | TLSOption |
| tlsstores | traefik.io/v1alpha1 | true | TLSStore |
| traefikservices | traefik.io/v1alpha1 | true | TraefikService |

仅给出 tcp 服务的配置明细，http 服务基本相同；traefik 中使用 middlewaretcp（tcp 服务）以及 middleware（http 服务）来添加源 IP 授权管理，最后并将 ingressroutetcp 与该 middlewaretcp 进行关联，其中：

tcp 服务：`ingressroutetcp --> middlewaretcp`

http 服务：`ingressroute --> middleware`

配置逻辑基本相同，仅需要更换资源类型即可

```yaml
---
apiVersion: traefik.io/v1alpha1
kind: MiddlewareTCP
metadata:
  name: source-ip
  namespace: default
spec:
  ipWhiteList:
    sourceRange:
      - 8.8.8.8/32
---
apiVersion: traefik.io/v1alpha1
kind: IngressRouteTCP
metadata:
  name: test-tcp
  namespace: default
spec:
  entryPoints:
  - tcp-entry
  routes:
  - match: HostSNI(`*`)
    middlewares:
    - name: source-ip 
   # 这个参数不是指 k8s 中的命名空间，是指 traefik 中的
      namespace: test
    services:
    - name: service-a
      port: 80
```

配置中需要注意在 ingressroutetcp 在关联 middlewaretcp 中有个配置项为`namespace`，它是指 traefik 自身的命名空间，官方说明如下：

> As Kubernetes also has its own notion of namespace, one should not confuse the kubernetes namespace of a resource (in the reference to the middleware) with the [provider namespace](https://doc.traefik.io/traefik/providers/overview/#provider-namespace), when the definition of the TCP middleware comes from another provider. In this context, specifying a namespace when referring to the resource does not make any sense, and will be ignored. Additionally, when you want to reference a MiddlewareTCP from the CRD Provider, you have to append the namespace of the resource in the resource-name as Traefik appends the namespace internally automatically.

所以建议把这两者放在同一个 k8s 命名空间内部署。

## istio ingress gateway

istio 所使用的规则最为特殊，前两者主要还是在 ingress api 上做文章，istio 自有一套入口控制资源体系，分别是`Gateway`和`VirtualService`，当然该控制器同样支持原生的 ingress 规则模式进行配置，但是其相比 ingress nginx controller 来说没有丰富的注解来进行更为精准的授权流控，故这里采用 istio 原生的资源方式进行授权管理。

```yaml
---
apiVersion: networking.istio.io/v1alpha3
kind: Gateway
metadata:
  name: test-gateway
  namespace: default
spec:
  selector:
    istio: ingressgateway # use Istio default gateway implementation
  servers:
  - port:
      number: 80
      name: http
      protocol: HTTP
    hosts:
    - "xxxx.xxxx.com"
---
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: test-vs
  namespace: default
spec:
  hosts:
  - "xxxx.xxxx.com"
  gateways:
  - test-gateway
  http:
  - match:
    - uri:
        prefix: /app
    rewrite:
      uri: /
    route:
    - destination:
        port:
          number: 80
        host: servcei-a
---
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: test-ingress-policy
  namespace: istio-ingress
spec:
  selector:
    matchLabels:
      app: istio-ingressgateway
  action: ALLOW
  rules:
  - from:
    - source:
        ipBlocks: ["8.8.8.8"]
```

需注意 gw 和 vs 资源尽量放在实际负载存在的命名空间，而 AuthorizationPolicy 则放在入口控制器部署的命名空间，不然无法进行关联。其 AuthorizationPolicy 的授权管理功能较前两者来说丰富非常多，这里仅使用白名单 IP 来进行配置而已，详细的配置介绍见 istio 官网。

***写在最后（题外话）：K8S 社区实际上是在推行 gateway API（不是指 istio 中的 gateway 资源）来取代原来的 ingress API，毕竟 ingress API 支持的流量管理策略十分局限。目前各大入口控制器均在 API 上兼容 gateway API，其中 istio 官网里的相关配置都会一式两份，一份是  istio 原生配置，一份是基于 gateway API 的配置，故 gateway API 是 K8S 入口流量管理的未来***
