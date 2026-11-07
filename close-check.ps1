#Requires -Version 7.0
<#
.SYNOPSIS
  Read-only "is this project ready to close?" check.

.DESCRIPTION
  The mechanical half of the closer protocol. Changes nothing: no commit, no push, no delete, and
  no network unless -Fetch is given. It answers four questions:

    - is every repository under the project committed and pushed?
    - is there an interrupted git operation (a .lock file)?
    - is a project process still running?
    - did another session write to this project recently?

  Anything it cannot prove is reported as a WARN, and the last line of the report says what is
  still open. Exit code = number of FAILs (0 means READY).

.PARAMETER ProjectRoot
  Project directory to check. Defaults to the current directory.

.PARAMETER SessionId
  The session running this check; excluded from the "other sessions" test.
  Defaults to $env:DSH_SESSION_ID.

.PARAMETER QuietMinutes
  A session write newer than this many minutes counts as "may still be running". Default 10.

.PARAMETER DshHome
  DSH home directory (sessions and the workspace registry).
  Defaults to $env:DSH_HOME, then ~/.dsh.

.PARAMETER Fetch
  Run 'git fetch' first, so ahead/behind reflects the real remote. Off by default.

.EXAMPLE
  pwsh -File close-check.ps1 -ProjectRoot C:\path\to\project
#>
[CmdletBinding()]
param(
  [string]$ProjectRoot = (Get-Location).ProviderPath,
  [string]$SessionId = $env:DSH_SESSION_ID,
  [int]$QuietMinutes = 10,
  [string]$DshHome = $(if ($env:DSH_HOME) { $env:DSH_HOME } else { Join-Path $env:USERPROFILE '.dsh' }),
  [switch]$Fetch
)

$ErrorActionPreference = 'Stop'

$root = (Resolve-Path -LiteralPath $ProjectRoot).Path.TrimEnd([char[]]('\', '/'))
$now = Get-Date
$failures = [System.Collections.Generic.List[string]]::new()
$warnings = [System.Collections.Generic.List[string]]::new()
$info = [System.Collections.Generic.List[string]]::new()

$git = Get-Command git -ErrorAction SilentlyContinue
if (-not $git) {
  Write-Host 'FAIL  git is not on PATH; the checkout half of this check cannot run.' -ForegroundColor Red
  Write-Host 'VERDICT: NOT READY (1 fail, 0 warn)'
  exit 1
}

function Invoke-Git {
  param([string]$Dir, [string[]]$GitArgs)
  $output = & git -C $Dir @GitArgs 2>$null
  if ($LASTEXITCODE -ne 0) { return $null }
  return $output
}

# --- repositories ------------------------------------------------------------------------------
# Stop at a repository boundary: a repo inside a repo is a submodule or a mistake, not a project.
$skipDirs = @('node_modules', 'dist', 'build', 'out', '.venv', 'venv', 'bin', 'obj', 'coverage', '.next', '.cache', 'target')

function Find-Repos {
  param([string]$Dir, [int]$Depth)
  if (Test-Path -LiteralPath (Join-Path $Dir '.git')) { return @($Dir) }
  if ($Depth -le 0) { return @() }
  $found = @()
  foreach ($child in Get-ChildItem -LiteralPath $Dir -Directory -Force -ErrorAction SilentlyContinue) {
    if ($skipDirs -contains $child.Name) { continue }
    if ($child.Name.StartsWith('.')) { continue }
    $found += Find-Repos -Dir $child.FullName -Depth ($Depth - 1)
  }
  return $found
}

$rows = @()
foreach ($repo in @(Find-Repos -Dir $root -Depth 3)) {
  $name = $repo.Substring($root.Length).TrimStart([char[]]('\', '/'))
  if (-not $name) { $name = Split-Path -Path $repo -Leaf }

  if ($Fetch) { & git -C $repo fetch --quiet 2>$null | Out-Null }

  $branch = Invoke-Git $repo @('rev-parse', '--abbrev-ref', 'HEAD')
  $noCommits = $false
  if (-not $branch) { $branch = '(none)'; $noCommits = $true }

  $upstream = Invoke-Git $repo @('rev-parse', '--abbrev-ref', '--symbolic-full-name', '@{u}')
  $dirtyLines = Invoke-Git $repo @('status', '--porcelain')
  $dirty = if ($null -eq $dirtyLines) { 0 } else { @($dirtyLines).Count }
  $stashLines = Invoke-Git $repo @('stash', 'list')
  $stash = if ($null -eq $stashLines) { 0 } else { @($stashLines).Count }

  $ahead = 0
  $behind = 0
  if ($upstream) {
    $counts = Invoke-Git $repo @('rev-list', '--count', '--left-right', "$upstream...HEAD")
    if ($counts) {
      $parts = @($counts -split '\s+' | Where-Object { $_ -ne '' })
      if ($parts.Count -ge 2) { $behind = [int]$parts[0]; $ahead = [int]$parts[1] }
    }
  }

  $gitDir = Invoke-Git $repo @('rev-parse', '--absolute-git-dir')
  $locks = @()
  if ($gitDir) {
    $locks = @(Get-ChildItem -LiteralPath $gitDir -Recurse -Force -Filter '*.lock' -ErrorAction SilentlyContinue)
  }

  $verdict = 'ok'
  if ($noCommits) {
    $verdict = 'WARN'
    $warnings.Add("$name has no commits yet")
  }
  if (-not $upstream -and -not $noCommits) {
    $verdict = 'WARN'
    $warnings.Add("$name branch '$branch' has no upstream - local-only, or the remote was never added")
  }
  if ($dirty -gt 0) {
    $verdict = 'FAIL'
    $failures.Add("$name has $dirty uncommitted change(s) - commit them or say why they stay")
  }
  if ($behind -gt 0) {
    $verdict = 'FAIL'
    $failures.Add("$name is $behind commit(s) behind $upstream - git pull --rebase, re-run the gate")
  }
  if ($ahead -gt 0) {
    $verdict = 'FAIL'
    $failures.Add("$name has $ahead commit(s) not pushed - git push")
  }
  if ($locks.Count -gt 0) {
    $verdict = 'FAIL'
    $failures.Add("$name has git lock file(s) - an operation was interrupted: $($locks[0].Name)")
  }
  if ($stash -gt 0) {
    if ($verdict -eq 'ok') { $verdict = 'WARN' }
    $warnings.Add("$name has $stash stash entr(ies) - uncommitted work is not closed")
  }

  # A local branch carrying commits its upstream does not have is work that only exists here.
  $branchLines = Invoke-Git $repo @('for-each-ref', '--format=%(refname:short)|%(upstream:track)', 'refs/heads')
  foreach ($line in @($branchLines)) {
    if (-not $line) { continue }
    $parts = $line -split '\|', 2
    if ($parts.Count -lt 2 -or -not $parts[1]) { continue }
    if ($parts[0] -eq $branch) { continue }
    if ($parts[1] -match 'ahead') {
      if ($verdict -eq 'ok') { $verdict = 'WARN' }
      $warnings.Add("$name branch '$($parts[0])' has unpushed commits ($($parts[1]))")
    }
  }

  $rows += [pscustomobject]@{
    repo   = $name
    branch = $branch
    ahead  = $ahead
    behind = $behind
    dirty  = $dirty
    stash  = $stash
    locks  = $locks.Count
    verdict = $verdict
  }
}

# --- sessions ----------------------------------------------------------------------------------
$sessionRoot = Join-Path $DshHome 'sessions'
$sessionIds = @()
if (Test-Path -LiteralPath (Join-Path $DshHome 'storages\workspace.json')) {
  try {
    $registry = Get-Content -LiteralPath (Join-Path $DshHome 'storages\workspace.json') -Raw | ConvertFrom-Json -AsHashtable
    foreach ($key in $registry['tables']['workspaces'].Keys) {
      $workspace = $registry['tables']['workspaces'][$key]
      if ($workspace['path'] -and ($workspace['path'].TrimEnd([char[]]('\', '/')) -ieq $root)) {
        $sessionIds = @($workspace['sessionIds'])
      }
    }
  } catch {
    $info.Add("could not read $DshHome\storages\workspace.json ($($_.Exception.Message))")
  }
}
if ($sessionIds.Count -eq 0) {
  $slug = '--' + ($root -replace ':', '' -replace '\\', '-') + '--'
  $candidate = Join-Path $sessionRoot $slug
  if (Test-Path -LiteralPath $candidate) {
    $sessionIds = @(Get-ChildItem -LiteralPath $candidate -Directory | ForEach-Object { $_.Name })
  }
}

$activeSessions = @()
$sessionRows = @()
foreach ($id in $sessionIds) {
  $pattern = Join-Path $sessionRoot "*\$id\session.v4.jsonl*"
  $file = Get-ChildItem -Path $pattern -File -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $file) { continue }
  $isSelf = $SessionId -and ($id -eq $SessionId)
  $recent = $file.LastWriteTime -gt $now.AddMinutes(-$QuietMinutes)
  $sessionRows += [pscustomobject]@{
    session = $id -replace '^session-', ''
    lastWrite = $file.LastWriteTime.ToString('MM-dd HH:mm')
    note = if ($isSelf) { 'this session' } elseif ($recent) { 'ACTIVE' } else { '' }
  }
  if ($recent -and -not $isSelf) {
    $activeSessions += $id
    $warnings.Add("session $($id -replace '^session-', '') wrote to this project at $($file.LastWriteTime.ToString('HH:mm')) - it may still be running")
  }
}

# --- processes ---------------------------------------------------------------------------------
$procs = @()
try {
  $selfPid = $PID
  $parentPid = (Get-CimInstance Win32_Process -Filter "ProcessId=$PID").ParentProcessId
  $ignoreProcs = @('Code.exe', 'devenv.exe', 'explorer.exe', 'WindowsTerminal.exe', 'DeepSeek Harness.exe', 'idea64.exe', 'rider64.exe', 'chrome.exe', 'msedge.exe', 'firefox.exe')
  $procs = @(Get-CimInstance Win32_Process | Where-Object {
      $_.ProcessId -ne $selfPid -and
      $_.ProcessId -ne $parentPid -and
      $_.CommandLine -and
      $ignoreProcs -notcontains $_.Name -and
      $_.CommandLine.IndexOf($root, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
    })
} catch {
  $info.Add("process scan unavailable ($($_.Exception.Message)) - check for a dev server or test run by hand")
}
foreach ($proc in $procs) {
  $warnings.Add("process $($proc.Name) (pid $($proc.ProcessId)) references this project - stop it before closing")
}

# --- report ------------------------------------------------------------------------------------
Write-Host ''
Write-Host ("CLOSE CHECK  {0}" -f $root)
Write-Host ("             {0:yyyy-MM-dd HH:mm}  (session {1})" -f $now, $(if ($SessionId) { $SessionId -replace '^session-', '' } else { 'unknown' }))
Write-Host ''

if ($rows.Count -eq 0) {
  Write-Host 'REPOS       none found within 3 levels'
  if (-not $failures.Contains("no git repository under the project")) {
    $warnings.Add('no git repository under this project - "committed and pushed" cannot be met; declare the gap in AGENTS.md')
  }
} else {
  Write-Host 'REPOS'
  $rows | Format-Table -AutoSize | Out-Host
}

Write-Host 'SESSIONS'
if ($sessionRows.Count -eq 0) {
  Write-Host '  no recorded session for this project (or no DSH session store here)'
} else {
  $sessionRows | Format-Table -AutoSize | Out-Host
  Write-Host ("  {0} session(s), {1} active in the last {2} min" -f $sessionRows.Count, $activeSessions.Count, $QuietMinutes)
}

Write-Host 'PROCESSES'
if ($procs.Count -eq 0) { Write-Host '  none referencing this project' }
else { $procs | Select-Object -Property Name, ProcessId | Format-Table -AutoSize | Out-Host }

if ($failures.Count -gt 0) {
  Write-Host ''
  foreach ($line in $failures) { Write-Host ("FAIL  {0}" -f $line) -ForegroundColor Red }
}
if ($warnings.Count -gt 0) {
  Write-Host ''
  foreach ($line in $warnings) { Write-Host ("WARN  {0}" -f $line) -ForegroundColor Yellow }
}
foreach ($line in $info) { Write-Host ("INFO  {0}" -f $line) -ForegroundColor DarkGray }

Write-Host ''
if ($failures.Count -eq 0) {
  Write-Host ("VERDICT: READY ({0} fail, {1} warn)" -f 0, $warnings.Count) -ForegroundColor Green
} else {
  Write-Host ("VERDICT: NOT READY ({0} fail, {1} warn)" -f $failures.Count, $warnings.Count) -ForegroundColor Red
}
exit ([Math]::Min(255, $failures.Count))
