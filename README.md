# ItemRadar

A macOS menu bar app that discovers and manages local services (projects without a desktop client) — scan, one-click start/stop, and auto-open the web UI in your browser.

一个 macOS 菜单栏应用：自动发现本机「没有桌面客户端、原本要靠终端启动」的项目，一键启动 / 停止，并在服务有网页时自动用浏览器打开。

> 列表只展示「可启动」的项目：必须能解析出启动命令才会显示；解析不出命令的项目
> 不会出现在列表里（需在 `projects` 里手动补 `command` 才会被纳入）。

## 功能

- 菜单栏图标：终端符号（terminal）
- 点击图标弹出面板：项目列表（名字 / 路径 / 启动命令）+ 每项的「启动 / 停止」按钮
- 启动后**自动探测网页地址并用浏览器打开**（见下文「自动打开浏览器」）
- 右上角「从指定文件夹获取」：弹系统文件夹选择器，选中后自动扫描其中的可启动项目
- 右上角「设置」⚙：配置扫描范围（哪些文件夹会被自动扫描），可添加/删除文件夹，开关用户目录顶层扫描
- 底部「手动添加」：手动添加一个服务（用于扫描器识别不到的服务，如全局 CLI 工具 / 注入式运行时），填写时会校验「路径是否存在、命令是否可用、网页地址格式」
- 列表支持**拖拽排序**（顺序会记住，下次启动还在）
- 右键项目行：
  - 「在 Finder 中显示」
  - 「打开日志」「在浏览器打开」（运行中时）
  - 「编辑启动命令…」「编辑网页地址…」
  - 「复制启动命令」
  - 「自动打开浏览器」开关（可逐项目关闭）
  - 「从列表中移除」

## 已安装位置

- 应用：`~/Applications/ProjectBar.app`（已加入登录自启）
- 源码：`~/Documents/deepseek/ProjectBar/`
- 配置：`~/.projectbar/config.json`
- 运行状态：`~/.projectbar/state.json`
- 服务日志：`~/.projectbar/logs/`

## 默认扫描范围

- `~/Documents`、`~/Downloads`、`~/Desktop`（深度 3）
- 额外扫用户目录顶层（深度 1，覆盖 `~/code`、`~/github` 等）

> ⚠️ 扫描器只能识别「项目目录」（含 `package.json` / Python / Docker 等特征文件）。
> 像 **全局 CLI 工具**（`dsh`、`astrbot`）或**注入式运行时**（NapCat 注入 QQ）这类
> 「不是目录项目」的服务，扫描器识别不到——请用底部「添加服务…」手动添加，
> 填好启动命令和网页地址即可。

## 自动打开浏览器

点「启动」后，会按以下顺序探测该服务的网页地址并自动打开：

1. 项目手动配置了 `url` → 直接用它。
2. 解析启动日志里的 `http(s)://localhost:端口` 等地址（最多等 ~10 秒）。
3. 用 `lsof` 查该服务进程树监听的 TCP 端口 → `http://localhost:端口`。
4. 都探测不到 → 只启动、不开浏览器，并提示「未检测到网页地址」。

> `0.0.0.0` / `::` 这类绑定地址会自动换成 `localhost`。运行中的项目也有
> 「在浏览器打开」按钮兜底。

## 配置文件 `~/.projectbar/config.json`

```json
{
  "roots": ["~/Documents", "~/Downloads", "~/Desktop"],
  "scanDepth": 3,
  "scanHomeTopLevel": true,
  "projects": [
    {
      "name": "可选显示名",
      "path": "~/path/to/project",
      "command": "可选，覆盖启动命令",
      "url": "可选，网页地址，如 http://localhost:3000",
      "openBrowser": true,
      "enabled": true
    }
  ]
}
```

字段说明：

| 字段 | 含义 |
|---|---|
| `roots` | 要扫描的项目根目录列表（支持 `~`）。 |
| `scanDepth` | 扫描深度：1 = 只看根目录的直接子目录。 |
| `scanHomeTopLevel` | 是否额外扫用户目录顶层（深度 1），缺省 `true`。 |
| `projects` | 手动项目清单，也是「覆盖 / 排除」手段。 |

`projects` 里每条：

| 字段 | 含义 |
|---|---|
| `name` | 显示名（缺省用目录名）。 |
| `path` | 项目绝对路径（支持 `~`）。 |
| `command` | 手动指定启动命令；不填则自动推断（推断不出则不展示）。 |
| `url` | 网页地址；启动后用它打开浏览器。 |
| `openBrowser` | 是否自动打开浏览器，缺省 `true`。 |
| `enabled` | `false` 表示排除该项目（不展示，也阻止自动扫描命中它）。 |

### 自动推断启动命令的规则

1. `package.json` 含 `dev` / `start` / `serve` 脚本 → 用对应脚本
   （按 `pnpm-lock.yaml`→pnpm、`yarn.lock`→yarn、`bun`→bun，否则 npm）。
2. `docker-compose.yml` 等 → `docker compose up`。
3. `manage.py` → `python3 manage.py runserver`；`app.py` / `main.py` → `python3 <文件>`。
4. `Cargo.toml` → `cargo run`；`go.mod` → `go run .`。
5. `index.php` → `php -S localhost:8000`；`*.csproj` / `*.sln` → `dotnet run`。
6. `Gemfile` + Rails 特征（`bin/rails` 或 `config/routes.rb`）→ `bundle exec rails server`。
7. 以上都不满足 → 该项目**不会出现在列表里**；在 `projects` 里补 `command` 即可。

> 提示：配置文件保存后应用会自动刷新，无需重启。像 ComfyUI 这类需要 venv 的
> 项目，建议在 `command` 里写完整命令，例如 `./venv/bin/python main.py`。

## 命令行用法（可选）

```sh
BIN=~/Applications/ProjectBar.app/Contents/MacOS/ProjectBar
"$BIN" --scan                 # 列出已发现的项目
"$BIN" --start <路径或名称>    # 启动
"$BIN" --stop  <路径或名称>    # 停止
"$BIN" --status <路径或名称>   # 查看运行状态
"$BIN" --test-url "<命令>"     # 自测：探测某命令启动后的网页地址
```

## 重新构建

```sh
cd ~/Documents/deepseek/ProjectBar
./build.sh
cp -R build/ProjectBar.app ~/Applications/ && codesign --force --deep --sign - ~/Applications/ProjectBar.app
```

## 卸载

```sh
launchctl unload ~/Library/LaunchAgents/local.projectbar.plist
rm -f ~/Library/LaunchAgents/local.projectbar.plist
rm -rf ~/Applications/ProjectBar.app
# rm -rf ~/.projectbar   # 配置与日志一并删除
```

## 说明与限制

- 只跟踪「由本应用启动」的服务状态；在终端里手动启动的服务不会显示为运行中。
- 关闭菜单栏应用不会杀掉已启动的服务；服务会继续运行，下次打开应用会重新识别状态。
- 「停止」会发送 SIGTERM，3 秒后仍存活再 SIGKILL，整棵进程树一起结束。
- 启动 3 秒后若进程已异常退出（可能命令不对），会提示「异常退出」。
