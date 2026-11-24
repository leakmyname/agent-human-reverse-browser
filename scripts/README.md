# scripts

| 脚本 | 作用 |
| --- | --- |
| `rev-up.sh <名字> [起始URL]` | 起临时容器，分配随机 noVNC/CDP 端口，等待 CDP 就绪，打开起始页 |
| `rev-down.sh <名字> \| --all` | 销毁容器 + profile 卷 + 状态文件 |
| `rev-status.sh` | 列出所有实例及端口 |
| `cdp-open.py <cdp_base> <url>` | 通过 CDP 在容器浏览器里打开一个页面 |

所有脚本可从任意工作目录调用，路径基于脚本自身位置解析。
