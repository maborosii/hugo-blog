# 使用官方的 Nginx 镜像作为基础镜像
FROM nginx:alpine

# 设置作者信息
LABEL maintainer="maborosi.xyz"

# 将 Hugo 生成的静态网站内容复制到 Nginx 默认的静态文件目录
COPY public /usr/share/nginx/html

# 暴露端口
EXPOSE 80

# 启动 Nginx
CMD ["nginx", "-g", "daemon off;"]
