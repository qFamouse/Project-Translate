$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$inv = [Globalization.CultureInfo]::InvariantCulture
$root = $PSScriptRoot
$stats = Get-ChildItem -Path $root, "$env:USERPROFILE\Downloads" -Filter 'pz-translate-stats-*.md' -File -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1 -ExpandProperty FullName
if (-not $stats) { throw 'pz-translate-stats-*.md не найден ни в папке проекта, ни в Загрузках' }
$readmes = @(Join-Path $root 'README.md') + @(Get-ChildItem -Path (Join-Path $root 'i18n') -Filter 'README.*.md' -File -ErrorAction SilentlyContinue | Sort-Object Name | Select-Object -ExpandProperty FullName)
if (-not (Test-Path $readmes[0])) { throw 'README.md не найден в папке проекта' }
$s = [IO.File]::ReadAllText($stats, $utf8) -replace "`r`n", "`n"
function Get-Section($title) {
    $m = [regex]::Match($s, '(?ms)^## ' + [regex]::Escape($title) + '\n(.*?)(?=^## |\z)')
    if (-not $m.Success) { throw "В файле статистики нет раздела: $title" }
    $m.Groups[1].Value.Trim()
}
function Get-Table($text) { ,@($text -split "`n" | Where-Object { $_ -match '^\|' }) }
function Split-Row($row) { @($row.Trim().Trim('|').Split('|') | ForEach-Object { $_.Trim() }) }
function Format-N($v) { ([long]($v -replace '\D', '')).ToString('N0', $inv) }
$tot = Get-Section 'Итого'
function Get-Total($label) {
    $m = [regex]::Match($tot, '(?m)^\|\s*' + [regex]::Escape($label) + '\s*\|\s*([^|]+?)\s*\|')
    if (-not $m.Success) { throw "В разделе Итого нет показателя: $label" }
    Format-N $m.Groups[1].Value
}
$tables = @{ coverage = (Get-Table (Get-Section 'Покрытие по языкам')); mods = (Get-Table (Get-Section 'Моды по языкам')) }
foreach ($k in $tables.Keys) { if ($tables[$k].Count -lt 3) { throw "В файле статистики пустая таблица: $k" } }
$en = $tables.coverage | Where-Object { $_ -match '^\|\s*EN\b' } | Select-Object -First 1
if (-not $en) { throw 'В покрытии по языкам нет строки EN' }
$val = [ordered]@{ mods = (Get-Total 'Модов'); lines = (Get-Total 'Строк в модах'); ours = (Get-Total 'Наших переводов'); langs = (Get-Total 'Языков с нашими переводами'); en = (Format-N (Split-Row $en)[2]) }
# Заголовки-коды языков (RU, EN\*) берутся из статистики, остальные ячейки шапки остаются локализованными из README
$code = '^[A-Z]{2,4}(\\\*)?$'
function Merge-Table($old, $new, $file) {
    $loc = @(Split-Row $old[0] | Where-Object { $_ -cnotmatch $code })
    $i = 0
    $head = foreach ($c in (Split-Row $new[0])) {
        if ($c -cmatch $code) { $c } elseif ($i -lt $loc.Count) { $loc[$i++] } else { throw "${file}: в шапке таблицы не хватает столбцов" }
    }
    if ($i -ne $loc.Count) { throw "${file}: в шапке таблицы лишние столбцы" }
    @('| ' + ($head -join ' | ') + ' |') + $new[1..($new.Count - 1)] -join "`n"
}
$changed = 0
foreach ($file in $readmes) {
    $name = $file.Substring($root.Length).TrimStart('\', '/')
    $r0 = [IO.File]::ReadAllText($file, $utf8)
    $crlf = $r0.Contains("`r`n")
    $r = $r0 -replace "`r`n", "`n"
    foreach ($k in $tables.Keys) {
        $m = [regex]::Matches($r, '(?s)(<!-- table:' + $k + ' -->\n\n)(.*?)(\n\n<!-- /table -->)')
        if ($m.Count -ne 1) { throw "${name}: не нашёл блок <!-- table:$k --> ... <!-- /table -->" }
        $old = Get-Table $m[0].Groups[2].Value
        if (-not $old) { throw "${name}: в блоке table:$k нет шапки таблицы" }
        $g = $m[0].Groups
        $r = $r.Substring(0, $g[2].Index) + (Merge-Table $old $tables[$k] $name) + $r.Substring($g[3].Index)
    }
    $r = [regex]::Replace($r, '<!-- stat:(\w+) -->[^<\n]*<!-- /stat -->', {
        param($m)
        $k = $m.Groups[1].Value
        if (-not $val.Contains($k)) { throw "${name}: неизвестный показатель stat:$k" }
        '<!-- stat:' + $k + ' -->' + $val[$k] + '<!-- /stat -->'
    })
    $out = $r
    if ($crlf) { $out = $r -replace "`n", "`r`n" }
    if ($out -cne $r0) {
        [IO.File]::WriteAllText($file, $out, $utf8)
        $changed++
        Write-Host ('  обновлён ' + $name)
    }
}
if ($changed) {
    Write-Host ("README обновлены из $(Split-Path $stats -Leaf): $changed из $($readmes.Count)") -ForegroundColor Green
    $val.Keys | ForEach-Object { Write-Host ('  ' + $_ + ': ' + $val[$_]) }
} else { Write-Host "Все README ($($readmes.Count)) уже актуальны, изменений нет" -ForegroundColor Yellow }
