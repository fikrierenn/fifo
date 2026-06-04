@echo off
setlocal EnableExtensions

set "ROOT=%~dp0"
set "OUT=%ROOT%all_files_dump.txt"

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$root = Resolve-Path '%ROOT%';" ^
  "$out = '%OUT%';" ^
  "$excludeDirs = @('.git','bin','obj','.vs','node_modules','packages');" ^
  "$excludeExt = @('.png','.jpg','.jpeg','.gif','.webp','.ico','.pdf','.zip','.7z','.rar','.dll','.exe','.pdb','.db','.bak','.log');" ^
  "if (Test-Path $out) { Remove-Item $out -Force };" ^
  "Get-ChildItem -Path $root -Recurse -File | Where-Object {" ^
  "  if ($_.FullName -eq $out) { return $false };" ^
  "  $rel = $_.FullName.Substring($root.Path.Length).TrimStart('\','/');" ^
  "  foreach ($d in $excludeDirs) { if ($rel -like ($d + '\*') -or $rel -like ('*\' + $d + '\*')) { return $false } };" ^
  "  if ($excludeExt -contains $_.Extension.ToLower()) { return $false };" ^
  "  return $true" ^
  "} | ForEach-Object {" ^
  "  Add-Content -Path $out -Value (\"`r`n===== \" + $_.FullName + \" =====`r`n\");" ^
  "  Get-Content -Path $_.FullName -Raw | Add-Content -Path $out" ^
  "};"

echo Done: %OUT%
