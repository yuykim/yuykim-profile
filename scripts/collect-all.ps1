Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$ConfigPath = Join-Path $RepoRoot ".dev-env.json"

function Read-Config {
  if (Test-Path $ConfigPath) {
    return Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
  }

  return [pscustomobject]@{
    profile = [pscustomobject]@{ owner = "yuykim" }
    machine = [pscustomobject]@{ id = ""; label = ""; role = "development machine" }
    workspace = [pscustomobject]@{ path = "D:/PARA/WORKSPACE" }
  }
}

function ConvertTo-Slug([string]$Value) {
  $slug = $Value.ToLowerInvariant() -replace "[^a-z0-9]+", "-"
  $slug = $slug.Trim("-")
  if ([string]::IsNullOrWhiteSpace($slug)) { return "unknown-machine" }
  return $slug
}

function Get-MachineConfig($Config) {
  $fallbackId = ConvertTo-Slug $env:COMPUTERNAME
  $id = if ($Config.machine.id) { ConvertTo-Slug $Config.machine.id } else { $fallbackId }
  $label = if ($Config.machine.label) { [string]$Config.machine.label } else { $id }
  $role = if ($Config.machine.role) { [string]$Config.machine.role } else { "development machine" }
  $model = if (($Config.machine.PSObject.Properties.Name -contains "model") -and $Config.machine.model) { [string]$Config.machine.model } else { $null }

  [pscustomobject]@{
    id = $id
    label = $label
    role = $role
    model = $model
  }
}

function Get-CommandText([string]$Command, [string[]]$Arguments) {
  $cmd = Get-Command $Command -ErrorAction SilentlyContinue
  if (-not $cmd) {
    return [pscustomobject]@{
      detected = $false
      output = $null
      path = $null
      error = "command not found"
    }
  }

  try {
    $output = & $Command @Arguments 2>&1 | Select-Object -First 8
    return [pscustomobject]@{
      detected = $true
      output = Protect-LocalText ((($output | ForEach-Object { "$_" }) -join "`n").Trim())
      path = $null
      error = $null
    }
  } catch {
    return [pscustomobject]@{
      detected = $true
      output = $null
      path = $null
      error = $_.Exception.Message
    }
  }
}

function Protect-LocalText([string]$Text) {
  if ($null -eq $Text) { return $null }

  $protected = $Text
  if ($env:USERPROFILE) {
    $escapedHome = [regex]::Escape($env:USERPROFILE)
    $protected = $protected -replace $escapedHome, "%USERPROFILE%"
  }

  return $protected -replace "`0", ""
}

function New-CommandProbe([string]$Name, [string]$Command, [string[]]$Arguments) {
  $result = Get-CommandText $Command $Arguments
  [pscustomobject]@{
    name = $Name
    command = $Command
    detected = $result.detected
    version = $result.output
    source = if ($result.detected) { "command" } else { "missing" }
    path = $result.path
    error = $result.error
  }
}

function ConvertTo-GB($Bytes) {
  if ($null -eq $Bytes) { return $null }
  return [math]::Round(([double]$Bytes / 1GB), 1)
}

function Write-Json($Path, $Value) {
  $dir = Split-Path -Parent $Path
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  $Value | ConvertTo-Json -Depth 12 | Set-Content -Path $Path -Encoding UTF8
}

function Read-JsonFile($Path) {
  if (-not (Test-Path $Path)) { return $null }
  return Get-Content $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Get-SystemSnapshot($Machine) {
  $computer = Get-CimInstance Win32_ComputerSystem
  $os = Get-CimInstance Win32_OperatingSystem
  $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
  $gpus = Get-CimInstance Win32_VideoController | ForEach-Object {
    [pscustomobject]@{
      name = $_.Name
      driver_version = $_.DriverVersion
      adapter_ram_gb = ConvertTo-GB $_.AdapterRAM
    }
  }
  $disks = Get-CimInstance Win32_LogicalDisk -Filter "DriveType = 3" | ForEach-Object {
    [pscustomobject]@{
      drive = $_.DeviceID
      size_gb = ConvertTo-GB $_.Size
      free_gb = ConvertTo-GB $_.FreeSpace
      file_system = $_.FileSystem
    }
  }

  [pscustomobject]@{
    machine = $Machine
    collected_at = (Get-Date).ToUniversalTime().ToString("o")
    os = [pscustomobject]@{
      caption = $os.Caption
      version = $os.Version
      build_number = $os.BuildNumber
      architecture = $os.OSArchitecture
    }
    hardware = [pscustomobject]@{
      manufacturer = $computer.Manufacturer
      model = if ($Machine.model) { $Machine.model } else { $computer.Model }
      cpu = $cpu.Name
      cpu_cores = $cpu.NumberOfCores
      cpu_logical_processors = $cpu.NumberOfLogicalProcessors
      ram_gb = ConvertTo-GB $computer.TotalPhysicalMemory
      gpu = @($gpus)
      disks = @($disks)
    }
  }
}

function Get-LanguageSnapshot {
  $items = @(
    @("Python", "python", @("--version")),
    @("Python Launcher", "py", @("--version")),
    @("pip", "pip", @("--version")),
    @("Node.js", "node", @("--version")),
    @("npm", "npm", @("--version")),
    @("pnpm", "pnpm", @("--version")),
    @("Yarn", "yarn", @("--version")),
    @("Java", "java", @("--version")),
    @("javac", "javac", @("--version")),
    @(".NET", "dotnet", @("--version")),
    @("Go", "go", @("version")),
    @("Rust", "rustc", @("--version")),
    @("Cargo", "cargo", @("--version")),
    @("Git", "git", @("--version"))
  )

  [pscustomobject]@{
    collected_at = (Get-Date).ToUniversalTime().ToString("o")
    languages = @($items | ForEach-Object { New-CommandProbe $_[0] $_[1] $_[2] })
  }
}

function Get-ToolSnapshot {
  $items = @(
    @("VS Code", "code", @("--version")),
    @("Cursor", "cursor", @("--version")),
    @("Unity Hub", "Unity Hub", @("--version")),
    @("Docker", "docker", @("--version")),
    @("Docker Compose", "docker", @("compose", "version")),
    @("WSL", "wsl", @("--version")),
    @("Conda", "conda", @("--version")),
    @("Android Debug Bridge", "adb", @("version")),
    @("Android Studio", "studio64", @("--version")),
    @("GitHub CLI", "gh", @("--version"))
  )

  [pscustomobject]@{
    collected_at = (Get-Date).ToUniversalTime().ToString("o")
    tools = @($items | ForEach-Object { New-CommandProbe $_[0] $_[1] $_[2] })
  }
}

function Get-Extensions([string]$Command) {
  $cmd = Get-Command $Command -ErrorAction SilentlyContinue
  if (-not $cmd) {
    return [pscustomobject]@{
      detected = $false
      command = $Command
      extensions = @()
      error = "command not found"
    }
  }

  try {
    $extensions = & $Command --list-extensions --show-versions 2>&1 |
      Where-Object { $_ -and "$_".Trim().Length -gt 0 } |
      ForEach-Object {
        $text = "$_".Trim()
        $parts = $text -split "@", 2
        [pscustomobject]@{
          id = $parts[0]
          version = if ($parts.Count -gt 1) { $parts[1] } else { $null }
        }
      }

    return [pscustomobject]@{
      detected = $true
      command = $Command
      extensions = @($extensions)
      error = $null
    }
  } catch {
    return [pscustomobject]@{
      detected = $true
      command = $Command
      extensions = @()
      error = $_.Exception.Message
    }
  }
}

function Get-EditorSnapshot {
  [pscustomobject]@{
    collected_at = (Get-Date).ToUniversalTime().ToString("o")
    editors = @(
      (New-CommandProbe "VS Code" "code" @("--version")),
      (New-CommandProbe "Cursor" "cursor" @("--version"))
    )
    vscode_extensions = Get-Extensions "code"
    cursor_extensions = Get-Extensions "cursor"
  }
}

function Get-RelativePath([string]$Base, [string]$Path) {
  try {
    $basePath = (Resolve-Path $Base).Path
    $targetPath = (Resolve-Path $Path).Path
    if (-not $basePath.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
      $basePath = "$basePath$([System.IO.Path]::DirectorySeparatorChar)"
    }
    $baseUri = [System.Uri]::new($basePath)
    $targetUri = [System.Uri]::new($targetPath)
    $relative = [System.Uri]::UnescapeDataString($baseUri.MakeRelativeUri($targetUri).ToString())
    return $relative.Replace("/", [System.IO.Path]::DirectorySeparatorChar)
  } catch {
    return Protect-LocalText $Path
  }
}

function Get-WorkspaceFiles([string]$WorkspacePath) {
  $excludeDirs = @(".git", "node_modules", "Library", "Temp", "Logs", "dist", "build", ".venv", "venv", "__pycache__", ".astro")
  $stack = New-Object System.Collections.Stack
  $stack.Push((Resolve-Path $WorkspacePath).Path)
  $files = New-Object System.Collections.Generic.List[string]

  while ($stack.Count -gt 0) {
    $dir = [string]$stack.Pop()
    try {
      foreach ($entry in Get-ChildItem -LiteralPath $dir -Force -ErrorAction Stop) {
        if ($entry.PSIsContainer) {
          if ($excludeDirs -notcontains $entry.Name) { $stack.Push($entry.FullName) }
        } else {
          $files.Add($entry.FullName)
        }
      }
    } catch {
      continue
    }
  }

  return $files
}

function Get-WorkspaceUsageSnapshot([string]$WorkspacePath) {
  if (-not (Test-Path $WorkspacePath)) {
    return [pscustomobject]@{
      collected_at = (Get-Date).ToUniversalTime().ToString("o")
      workspace_path = $WorkspacePath
      detected = $false
      error = "workspace path not found"
      signals = @()
    }
  }

  $patterns = @(
    @{ name = "Node/Web"; match = { param($f) (Split-Path $f -Leaf) -eq "package.json" } },
    @{ name = "Python requirements"; match = { param($f) (Split-Path $f -Leaf) -eq "requirements.txt" } },
    @{ name = "Python project"; match = { param($f) (Split-Path $f -Leaf) -eq "pyproject.toml" } },
    @{ name = "Jupyter Notebook"; match = { param($f) $f -like "*.ipynb" } },
    @{ name = "Unity"; match = { param($f) $f -like "*ProjectSettings\ProjectVersion.txt" } },
    @{ name = ".NET solution"; match = { param($f) $f -like "*.sln" } },
    @{ name = ".NET project"; match = { param($f) $f -like "*.csproj" } },
    @{ name = "Dockerfile"; match = { param($f) (Split-Path $f -Leaf) -eq "Dockerfile" } },
    @{ name = "Docker Compose"; match = { param($f) @("docker-compose.yml", "docker-compose.yaml", "compose.yml", "compose.yaml") -contains (Split-Path $f -Leaf) } }
  )

  $allFiles = @(Get-WorkspaceFiles $WorkspacePath)
  $signals = foreach ($pattern in $patterns) {
    $matches = @($allFiles | Where-Object { & $pattern.match $_ })
    [pscustomobject]@{
      name = $pattern.name
      count = $matches.Count
      examples = @($matches | Select-Object -First 12 | ForEach-Object { Get-RelativePath $WorkspacePath $_ })
    }
  }

  [pscustomobject]@{
    collected_at = (Get-Date).ToUniversalTime().ToString("o")
    workspace_path = "WORKSPACE"
    detected = $true
    scanned_files = $allFiles.Count
    signals = @($signals)
  }
}

function Get-AgentSnapshot([string]$WorkspacePath, $EditorSnapshot) {
  $commands = @(
    @("Codex", "codex", @("--version")),
    @("Claude Code", "claude", @("--version")),
    @("Gemini CLI", "gemini", @("--version")),
    @("OpenAI CLI", "openai", @("--version"))
  )

  $extensionAgents = @()
  $allExtensions = @()
  if ($EditorSnapshot.vscode_extensions.detected) { $allExtensions += $EditorSnapshot.vscode_extensions.extensions }
  if ($EditorSnapshot.cursor_extensions.detected) { $allExtensions += $EditorSnapshot.cursor_extensions.extensions }

  foreach ($ext in $allExtensions) {
    if ($ext.id -match "copilot|continue|cline|roo|openai|cursor|claude|gemini") {
      $extensionAgents += [pscustomobject]@{
        name = $ext.id
        detected = $true
        version = $ext.version
        source = "editor_extension"
      }
    }
  }

  $instructionFiles = @()
  if (Test-Path $WorkspacePath) {
    $instructionNames = @("AGENTS.md", "CLAUDE.md", "GEMINI.md", ".cursorrules")
    $instructionFiles = @(Get-WorkspaceFiles $WorkspacePath |
      Where-Object {
        $leaf = Split-Path $_ -Leaf
        ($instructionNames -contains $leaf) -or ($_ -match "\\.cursor\\rules\\")
      } |
      Select-Object -First 80 |
      ForEach-Object { Get-RelativePath $WorkspacePath $_ } |
      Where-Object { $_ -notmatch "^yuykim_Profile\\local_docs\\" })
  }

  [pscustomobject]@{
    collected_at = (Get-Date).ToUniversalTime().ToString("o")
    agents = @(
      ($commands | ForEach-Object { New-CommandProbe $_[0] $_[1] $_[2] })
      $extensionAgents
    )
    instruction_files = @($instructionFiles)
  }
}

function Get-DetectedNames($Items, [string]$PropertyName) {
  @($Items | Where-Object { $_.detected -eq $true } | ForEach-Object { Format-DisplayName $_.$PropertyName })
}

function Format-DisplayName([string]$Name) {
  switch -Regex ($Name) {
    "^anthropic\.claude-code$" { return "Claude Code extension" }
    "^openai\.chatgpt$" { return "ChatGPT extension" }
    default { return $Name }
  }
}

function Write-Markdown($Path, $Lines) {
  $dir = Split-Path -Parent $Path
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  $flatLines = ConvertTo-FlatLines $Lines
  ($flatLines -join "`n") + "`n" | Set-Content -Path $Path -Encoding UTF8
}

function ConvertTo-FlatLines($Lines) {
  foreach ($line in $Lines) {
    if (($line -is [System.Collections.IEnumerable]) -and -not ($line -is [string])) {
      ConvertTo-FlatLines $line
    } else {
      [string]$line
    }
  }
}

function ConvertTo-MarkdownValue($Value) {
  if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return "not detected" }
  return (Protect-LocalText ([string]$Value)).Replace("`r", "").Replace("`n", "<br>")
}

function Get-JsonCommand([string]$Command, [string[]]$Arguments) {
  $result = Get-CommandText $Command $Arguments
  if (-not $result.detected -or -not $result.output) { return $null }
  try {
    return $result.output | ConvertFrom-Json
  } catch {
    return $null
  }
}

function Get-PythonPackageSnapshot {
  $pipList = Get-JsonCommand "python" @("-m", "pip", "list", "--format=json")
  $watchNames = @(
    "numpy", "pandas", "scipy", "scikit-learn", "matplotlib", "seaborn",
    "jupyter", "jupyterlab", "notebook", "ipykernel", "ipywidgets",
    "opencv-python", "networkx", "pyyaml", "tqdm", "torch", "torchvision",
    "tensorflow", "keras", "gymnasium", "mlagents", "stable-baselines3"
  )

  $packages = @()
  if ($pipList) {
    $packages = @($pipList | Sort-Object name | ForEach-Object {
      [pscustomobject]@{ name = $_.name; version = $_.version }
    })
  }

  [pscustomobject]@{
    collected_at = (Get-Date).ToUniversalTime().ToString("o")
    packages = @($packages)
    watched = @($packages | Where-Object { $watchNames -contains $_.name.ToLowerInvariant() })
  }
}

function Get-CondaSnapshot {
  $condaInfo = Get-JsonCommand "conda" @("info", "--json")
  $condaEnvs = Get-JsonCommand "conda" @("env", "list", "--json")

  [pscustomobject]@{
    collected_at = (Get-Date).ToUniversalTime().ToString("o")
    version = (Get-CommandText "conda" @("--version")).output
    active_prefix = if ($condaInfo) { Protect-LocalText $condaInfo.active_prefix } else { $null }
    active_prefix_name = if ($condaInfo) { $condaInfo.active_prefix_name } else { $null }
    python_version = if ($condaInfo) { $condaInfo.python_version } else { $null }
    envs = if ($condaEnvs) { @($condaEnvs.envs | ForEach-Object { Protect-LocalText $_ }) } else { @() }
  }
}

function Get-JupyterSnapshot {
  [pscustomobject]@{
    collected_at = (Get-Date).ToUniversalTime().ToString("o")
    jupyter = (Get-CommandText "jupyter" @("--version")).output
    jupyter_lab = (Get-CommandText "jupyter-lab" @("--version")).output
    notebook = (Get-CommandText "jupyter-notebook" @("--version")).output
  }
}

function Write-LocalDocs($RepoRoot, $Machine, $System, $Languages, $Tools, $Editors, $Agents, $Workspace, $PythonPackages, $Conda, $Jupyter) {
  $root = Join-Path $RepoRoot "local_docs"
  New-Item -ItemType Directory -Force -Path $root | Out-Null

  Write-Markdown -Path (Join-Path $root "README.md") -Lines (@(
    "# Local Development Environment",
    "",
    "이 문서는 블로그 공개용이 아니라 로컬에서 개발 환경을 점검하고 새 PC를 세팅할 때 보기 위한 상세 문서다.",
    "",
    "- 마지막 수집: $($System.collected_at)",
    ("- 머신: {0} ({1})" -f $Machine.label, $Machine.id),
    "",
    "## 문서 목록",
    "",
    "- [개발 환경](development-environment.md)",
    "- [언어와 런타임](languages-and-runtimes.md)",
    "- [Python 라이브러리](python-libraries.md)",
    "- [Conda와 Jupyter](conda-jupyter.md)",
    "- [개발 도구](tools.md)",
    "- [VS Code 확장](vscode-extensions.md)",
    "- [AI 에이전트](agents.md)",
    "- [워크스페이스 사용 흔적](workspace-usage.md)"
  ))

  $gpuLines = @($System.hardware.gpu | ForEach-Object { "- $($_.name) / driver: $($_.driver_version) / RAM: $($_.adapter_ram_gb) GB" })
  $diskLines = @($System.hardware.disks | ForEach-Object { "- $($_.drive) / size: $($_.size_gb) GB / free: $($_.free_gb) GB / fs: $($_.file_system)" })
  Write-Markdown -Path (Join-Path $root "development-environment.md") -Lines (@(
    "# 개발 환경",
    "",
    "## 머신",
    "",
    "- ID: $($Machine.id)",
    "- 이름: $($Machine.label)",
    "- 역할: $($Machine.role)",
    "- 모델: $($System.hardware.manufacturer) $($System.hardware.model)",
    "",
    "## OS",
    "",
    "- OS: $($System.os.caption)",
    "- Version: $($System.os.version)",
    "- Build: $($System.os.build_number)",
    "- Architecture: $($System.os.architecture)",
    "",
    "## CPU / RAM",
    "",
    "- CPU: $($System.hardware.cpu)",
    "- Cores: $($System.hardware.cpu_cores)",
    "- Logical processors: $($System.hardware.cpu_logical_processors)",
    "- RAM: $($System.hardware.ram_gb) GB",
    "",
    "## GPU",
    "",
    $gpuLines,
    "",
    "## Disk",
    "",
    $diskLines
  ))

  $languageLines = @($Languages.languages | ForEach-Object {
    "- $($_.name) / command: $($_.command) / detected: $($_.detected) / version: $(ConvertTo-MarkdownValue $_.version) / error: $(ConvertTo-MarkdownValue $_.error)"
  })
  Write-Markdown -Path (Join-Path $root "languages-and-runtimes.md") -Lines (@(
    "# 언어와 런타임",
    "",
    "설치 여부와 버전은 명령어 실행 결과 기준이다.",
    "",
    $languageLines
  ))

  $watchedLines = @($PythonPackages.watched | ForEach-Object { "- $($_.name): $($_.version)" })
  if ($watchedLines.Count -eq 0) { $watchedLines = @("- watched package not detected") }
  $allPackageLines = @($PythonPackages.packages | ForEach-Object { "- $($_.name): $($_.version)" })
  Write-Markdown -Path (Join-Path $root "python-libraries.md") -Lines (@(
    "# Python 라이브러리",
    "",
    "## 주요 확인 대상",
    "",
    $watchedLines,
    "",
    "## 전체 pip 패키지",
    "",
    $allPackageLines
  ))

  $condaEnvLines = @($Conda.envs | ForEach-Object { "- $_" })
  if ($condaEnvLines.Count -eq 0) { $condaEnvLines = @("- conda env not detected") }
  Write-Markdown -Path (Join-Path $root "conda-jupyter.md") -Lines (@(
    "# Conda와 Jupyter",
    "",
    "## Conda",
    "",
    "- Version: $(ConvertTo-MarkdownValue $Conda.version)",
    "- Active env: $(ConvertTo-MarkdownValue $Conda.active_prefix_name)",
    "- Python version: $(ConvertTo-MarkdownValue $Conda.python_version)",
    "- Active prefix: $(ConvertTo-MarkdownValue $Conda.active_prefix)",
    "",
    "## Conda environments",
    "",
    $condaEnvLines,
    "",
    "## Jupyter",
    "",
    "- jupyter: $(ConvertTo-MarkdownValue $Jupyter.jupyter)",
    "- jupyter-lab: $(ConvertTo-MarkdownValue $Jupyter.jupyter_lab)",
    "- jupyter-notebook: $(ConvertTo-MarkdownValue $Jupyter.notebook)"
  ))

  $toolLines = @($Tools.tools | ForEach-Object {
    "- $($_.name) / command: $($_.command) / detected: $($_.detected) / version: $(ConvertTo-MarkdownValue $_.version) / error: $(ConvertTo-MarkdownValue $_.error)"
  })
  Write-Markdown -Path (Join-Path $root "tools.md") -Lines (@(
    "# 개발 도구",
    "",
    $toolLines
  ))

  $editorLines = @($Editors.editors | ForEach-Object {
    "- $($_.name): $(ConvertTo-MarkdownValue $_.version)"
  })
  $vscodeLines = @($Editors.vscode_extensions.extensions | Sort-Object id | ForEach-Object { "- $($_.id): $($_.version)" })
  $cursorLines = @($Editors.cursor_extensions.extensions | Sort-Object id | ForEach-Object { "- $($_.id): $($_.version)" })
  if ($cursorLines.Count -eq 0) { $cursorLines = @("- Cursor extension list is empty or unavailable") }
  Write-Markdown -Path (Join-Path $root "vscode-extensions.md") -Lines (@(
    "# VS Code / Cursor 확장",
    "",
    "## Editors",
    "",
    $editorLines,
    "",
    "## VS Code extensions ($(@($Editors.vscode_extensions.extensions).Count))",
    "",
    $vscodeLines,
    "",
    "## Cursor extensions ($(@($Editors.cursor_extensions.extensions).Count))",
    "",
    $cursorLines
  ))

  $agentLines = @($Agents.agents | ForEach-Object {
    "- $($_.name) / detected: $($_.detected) / version: $(ConvertTo-MarkdownValue $_.version) / source: $($_.source)"
  })
  $instructionLines = @($Agents.instruction_files | ForEach-Object { "- $_" })
  if ($instructionLines.Count -eq 0) { $instructionLines = @("- instruction file not detected") }
  Write-Markdown -Path (Join-Path $root "agents.md") -Lines (@(
    "# AI 에이전트",
    "",
    "## 설치/확장 감지",
    "",
    $agentLines,
    "",
    "## 워크스페이스 지시 파일",
    "",
    $instructionLines
  ))

  $signalLines = @($Workspace.signals | ForEach-Object {
    $examples = if ($_.examples.Count -gt 0) { ($_.examples | ForEach-Object { "  - $_" }) } else { @("  - no examples") }
    @("- $($_.name): $($_.count)", $examples)
  })
  Write-Markdown -Path (Join-Path $root "workspace-usage.md") -Lines (@(
    "# 워크스페이스 사용 흔적",
    "",
    "- scanned files: $($Workspace.scanned_files)",
    "",
    $signalLines
  ))
}

function Render-MachineMarkdown($OutputPath, $System, $Languages, $Tools, $Editors, $Agents, $Workspace) {
  $lines = New-Object System.Collections.Generic.List[string]
  $lines.Add("# $($System.machine.label)")
  $lines.Add("")
  $lines.Add("- Role: $($System.machine.role)")
  $lines.Add("- Machine ID: ``$($System.machine.id)``")
  $lines.Add("- Last collected: $($System.collected_at)")
  $lines.Add("")
  $lines.Add("## System")
  $lines.Add("")
  $lines.Add("- OS: $($System.os.caption) $($System.os.version) ($($System.os.architecture))")
  $lines.Add("- Manufacturer/Model: $($System.hardware.manufacturer) $($System.hardware.model)")
  $lines.Add("- CPU: $($System.hardware.cpu)")
  $lines.Add("- RAM: $($System.hardware.ram_gb) GB")
  $lines.Add("- GPU: $((@($System.hardware.gpu) | ForEach-Object { $_.name }) -join ', ')")
  $diskText = (@($System.hardware.disks) | ForEach-Object { "$($_.drive) $($_.size_gb)GB" }) -join ", "
  $lines.Add("- Disks: $diskText")
  $lines.Add("")
  $lines.Add("## Languages and Runtimes")
  $lines.Add("")
  foreach ($item in $Languages.languages) {
    $status = if ($item.detected) { $item.version } else { "not detected" }
    $lines.Add("- $($item.name): $status")
  }
  $lines.Add("")
  $lines.Add("## Tools")
  $lines.Add("")
  foreach ($item in $Tools.tools) {
    $status = if ($item.detected) { $item.version } else { "not detected" }
    $lines.Add("- $($item.name): $status")
  }
  $lines.Add("")
  $lines.Add("## Editors")
  $lines.Add("")
  foreach ($item in $Editors.editors) {
    $status = if ($item.detected) { $item.version } else { "not detected" }
    $lines.Add("- $($item.name): $status")
  }
  $lines.Add("- VS Code extensions: $(@($Editors.vscode_extensions.extensions).Count)")
  $lines.Add("- Cursor extensions: $(@($Editors.cursor_extensions.extensions).Count)")
  $lines.Add("")
  $lines.Add("## Agents")
  $lines.Add("")
  foreach ($item in $Agents.agents) {
    $status = if ($item.detected) { if ($item.version) { $item.version } else { "detected" } } else { "not detected" }
    $lines.Add("- $($item.name): $status")
  }
  $lines.Add("")
  $lines.Add("## Workspace Usage Signals")
  $lines.Add("")
  foreach ($signal in $Workspace.signals) {
    if ($signal.count -gt 0) {
      $lines.Add("- $($signal.name): $($signal.count)")
    }
  }

  Write-Markdown $OutputPath $lines
}

function Render-IndexMarkdown($OutputPath, $Summary, $MachineMarkdownLinks) {
  $lines = New-Object System.Collections.Generic.List[string]
  $lines.Add("---")
  $lines.Add("title: `"Dev Environment`"")
  $lines.Add("updated: `"$($Summary.updated_at)`"")
  $lines.Add("---")
  $lines.Add("")
  $lines.Add("# Dev Environment")
  $lines.Add("")
  $lines.Add("This page is generated from ``yuykim_Profile``. It is the public setup snapshot I use when rebuilding a laptop or desktop.")
  $lines.Add("")
  $lines.Add("- Last updated: $($Summary.updated_at)")
  $lines.Add("- Machines: $(@($Summary.machines).Count)")
  $lines.Add("")
  $lines.Add("## Machine Specs")
  $lines.Add("")
  foreach ($machine in $Summary.machines) {
    $lines.Add("### [$($machine.label)](machines/$($machine.id)/)")
    $lines.Add("")
    $lines.Add("- Role: $($machine.role)")
    $lines.Add("- Model: $($machine.system.model)")
    $lines.Add("- OS: $($machine.system.os)")
    $lines.Add("- CPU: $($machine.system.cpu)")
    $lines.Add("- GPU: $($machine.system.gpu)")
    $lines.Add("- RAM: $($machine.system.ram_gb) GB")
    $lines.Add("- Disk: $($machine.system.disks)")
    $lines.Add("- VS Code extensions: $($machine.editors.vscode_extensions)")
    $lines.Add("- Cursor extensions: $($machine.editors.cursor_extensions)")
    $lines.Add("")
  }
  $lines.Add("## Core Stack")
  $lines.Add("")
  $lines.Add("### Languages and Runtimes")
  foreach ($name in $Summary.common.languages) {
    if (@("Python", "pip", "Conda", "Node.js", "npm", "pnpm", "Java", ".NET", "Go", "Rust", "Git") -contains $name) {
      $lines.Add("- $name")
    }
  }
  $lines.Add("")
  $lines.Add("### Tools and Editors")
  foreach ($name in $Summary.common.tools) {
    if (@("VS Code", "Cursor", "Docker", "Docker Compose", "WSL", "Unity Hub", "Conda", "GitHub CLI", "Homebrew") -contains $name) {
      $lines.Add("- $name")
    }
  }
  $lines.Add("")
  $lines.Add("## Agents")
  foreach ($name in $Summary.common.agents) {
    if ($name -match "Codex|Claude|OpenAI|ChatGPT|Gemini|Copilot|Cline|Roo|Continue") {
      $lines.Add("- $name")
    }
  }
  $lines.Add("")
  $lines.Add("## Workspace Signals")
  $lines.Add("")
  foreach ($signal in $Summary.workspace_usage) {
    if ($signal.count -gt 0) { $lines.Add("- $($signal.name): $($signal.count)") }
  }

  Write-Markdown $OutputPath $lines
}

$config = Read-Config
$machine = Get-MachineConfig $config
$workspacePath = if ($config.workspace.path) { [string]$config.workspace.path } else { Join-Path $RepoRoot ".." }
$machineDir = Join-Path $RepoRoot "data/machines/$($machine.id)"
$machineDocPath = Join-Path $RepoRoot "dev_env/machines/$($machine.id).md"

$system = Get-SystemSnapshot $machine
$languages = Get-LanguageSnapshot
$tools = Get-ToolSnapshot
$editors = Get-EditorSnapshot
$workspace = Get-WorkspaceUsageSnapshot $workspacePath
$agents = Get-AgentSnapshot $workspacePath $editors
$pythonPackages = Get-PythonPackageSnapshot
$conda = Get-CondaSnapshot
$jupyter = Get-JupyterSnapshot

Write-Json (Join-Path $machineDir "system.json") $system
Write-Json (Join-Path $machineDir "languages.json") $languages
Write-Json (Join-Path $machineDir "tools.json") $tools
Write-Json (Join-Path $machineDir "editors.json") $editors
Write-Json (Join-Path $machineDir "agents.json") $agents
Write-Json (Join-Path $machineDir "workspace-usage.json") $workspace
Write-Json (Join-Path $machineDir "python-packages.json") $pythonPackages
Write-Json (Join-Path $machineDir "conda.json") $conda
Write-Json (Join-Path $machineDir "jupyter.json") $jupyter
Write-Json (Join-Path $machineDir "collected-at.json") ([pscustomobject]@{ collected_at = (Get-Date).ToUniversalTime().ToString("o") })

Render-MachineMarkdown $machineDocPath $system $languages $tools $editors $agents $workspace
Write-LocalDocs $RepoRoot $machine $system $languages $tools $editors $agents $workspace $pythonPackages $conda $jupyter

$machineDirs = @(Get-ChildItem (Join-Path $RepoRoot "data/machines") -Directory -ErrorAction SilentlyContinue)
$machines = @()
$allLanguages = @()
$allTools = @()
$allAgents = @()
$workspaceSignals = @{}

foreach ($dir in $machineDirs) {
  $sys = Read-JsonFile (Join-Path $dir.FullName "system.json")
  $lang = Read-JsonFile (Join-Path $dir.FullName "languages.json")
  $tool = Read-JsonFile (Join-Path $dir.FullName "tools.json")
  $edit = Read-JsonFile (Join-Path $dir.FullName "editors.json")
  $agent = Read-JsonFile (Join-Path $dir.FullName "agents.json")
  $usage = Read-JsonFile (Join-Path $dir.FullName "workspace-usage.json")
  if (-not $sys) { continue }

  $machines += [pscustomobject]@{
    id = $sys.machine.id
    label = $sys.machine.label
    role = $sys.machine.role
    collected_at = $sys.collected_at
    system = [pscustomobject]@{
      os = "$($sys.os.caption) $($sys.os.version)"
      model = "$($sys.hardware.manufacturer) $($sys.hardware.model)".Trim()
      cpu = $sys.hardware.cpu
      gpu = ((@($sys.hardware.gpu) | ForEach-Object { $_.name }) -join ", ")
      ram_gb = $sys.hardware.ram_gb
      disks = ((@($sys.hardware.disks) | ForEach-Object { "$($_.drive) $($_.size_gb)GB" }) -join ", ")
    }
    editors = [pscustomobject]@{
      vscode_extensions = if ($edit) { @($edit.vscode_extensions.extensions).Count } else { 0 }
      cursor_extensions = if ($edit) { @($edit.cursor_extensions.extensions).Count } else { 0 }
    }
  }

  if ($lang) { $allLanguages += Get-DetectedNames $lang.languages "name" }
  if ($tool) { $allTools += Get-DetectedNames $tool.tools "name" }
  if ($edit) { $allTools += Get-DetectedNames $edit.editors "name" }
  if ($agent) { $allAgents += Get-DetectedNames $agent.agents "name" }
  if ($usage) {
    foreach ($signal in $usage.signals) {
      if (-not $workspaceSignals.ContainsKey($signal.name)) { $workspaceSignals[$signal.name] = 0 }
      $workspaceSignals[$signal.name] += [int]$signal.count
    }
  }
}

$summary = [pscustomobject]@{
  updated_at = (Get-Date).ToUniversalTime().ToString("o")
  machines = @($machines | Sort-Object id)
  common = [pscustomobject]@{
    languages = @($allLanguages | Sort-Object -Unique)
    tools = @($allTools | Sort-Object -Unique)
    agents = @($allAgents | Sort-Object -Unique)
  }
  workspace_usage = @($workspaceSignals.GetEnumerator() | ForEach-Object {
    [pscustomobject]@{ name = $_.Key; count = $_.Value }
  } | Sort-Object name)
}

Write-Json (Join-Path $RepoRoot "data/summary.json") $summary
Render-IndexMarkdown (Join-Path $RepoRoot "dev_env/index.md") $summary @()

Write-Host "Collected dev environment snapshot for '$($machine.id)'."
Write-Host "Generated dev_env/index.md and $machineDocPath"



