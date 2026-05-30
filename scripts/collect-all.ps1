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
    return [System.IO.Path]::GetRelativePath((Resolve-Path $Base), (Resolve-Path $Path))
  } catch {
    return $Path
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
      ForEach-Object { Get-RelativePath $WorkspacePath $_ })
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
  @($Items | Where-Object { $_.detected -eq $true } | ForEach-Object { $_.$PropertyName })
}

function Write-Markdown($Path, [string[]]$Lines) {
  $dir = Split-Path -Parent $Path
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  ($Lines -join "`n") + "`n" | Set-Content -Path $Path -Encoding UTF8
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
  $lines.Add("This page is generated from `yuykim_Profile`. It records the development machines, tools, runtimes, editors, agents, and workspace usage signals needed to rebuild the environment.")
  $lines.Add("")
  $lines.Add("- Last updated: $($Summary.updated_at)")
  $lines.Add("- Machines: $(@($Summary.machines).Count)")
  $lines.Add("")
  $lines.Add("## Machines")
  $lines.Add("")
  foreach ($machine in $Summary.machines) {
    $lines.Add("- [$($machine.label)](machines/$($machine.id)/): $($machine.role)")
  }
  $lines.Add("")
  $lines.Add("## Common Stack")
  $lines.Add("")
  $lines.Add("### Languages and Runtimes")
  foreach ($name in $Summary.common.languages) { $lines.Add("- $name") }
  $lines.Add("")
  $lines.Add("### Tools and Editors")
  foreach ($name in $Summary.common.tools) { $lines.Add("- $name") }
  $lines.Add("")
  $lines.Add("### Agents")
  foreach ($name in $Summary.common.agents) { $lines.Add("- $name") }
  $lines.Add("")
  $lines.Add("## Workspace Usage")
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

Write-Json (Join-Path $machineDir "system.json") $system
Write-Json (Join-Path $machineDir "languages.json") $languages
Write-Json (Join-Path $machineDir "tools.json") $tools
Write-Json (Join-Path $machineDir "editors.json") $editors
Write-Json (Join-Path $machineDir "agents.json") $agents
Write-Json (Join-Path $machineDir "workspace-usage.json") $workspace
Write-Json (Join-Path $machineDir "collected-at.json") ([pscustomobject]@{ collected_at = (Get-Date).ToUniversalTime().ToString("o") })

Render-MachineMarkdown $machineDocPath $system $languages $tools $editors $agents $workspace

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
