# dump_onenote.ps1 — Dump la hierarchie OneNote en XML + un CSV (id, page_id, title, hyperlink)
# Usage : powershell -ExecutionPolicy Bypass -File dump_onenote.ps1
#
# Sortie :
#   onenote_hierarchy.xml — hierarchie complete (notebooks/sections/pages)
#   onenote_pages.csv     — liste des pages avec hyperlinks cliquables
#
# Pre-requis : OneNote desktop installe (peut etre lance ou non).

param(
    [string]$OutDir = $PSScriptRoot
)

$ErrorActionPreference = "Stop"

Write-Host "[INFO] Connexion a OneNote..."
$onenote = New-Object -ComObject OneNote.Application

# HierarchyScope.hsPages = 4
$xml = ""
Write-Host "[INFO] Recuperation de la hierarchie complete..."
$onenote.GetHierarchy("", 4, [ref]$xml)

$xmlPath = Join-Path $OutDir "onenote_hierarchy.xml"
$xml | Out-File -FilePath $xmlPath -Encoding UTF8
Write-Host "[OK] XML brut ecrit : $xmlPath ($($xml.Length) caracteres)"

# Parse le XML pour extraire les pages avec leur contexte (notebook/section)
[xml]$doc = $xml

$pages = New-Object System.Collections.ArrayList

function Walk-Node {
    param($Node, [string]$Notebook, [string]$SectionPath)

    foreach ($child in $Node.ChildNodes) {
        $tag = $child.LocalName
        $name = $child.GetAttribute("name")

        if ($tag -eq "Notebook") {
            $isInRecycle = $child.GetAttribute("isInRecycleBin")
            if ($isInRecycle -eq "true") { continue }
            Walk-Node -Node $child -Notebook $name -SectionPath ""
        }
        elseif ($tag -eq "SectionGroup") {
            $isRecycle = $child.GetAttribute("isRecycleBin")
            $isInRecycle = $child.GetAttribute("isInRecycleBin")
            if ($isRecycle -eq "true" -or $isInRecycle -eq "true") { continue }
            $newPath = if ($SectionPath) { "$SectionPath / $name" } else { $name }
            Walk-Node -Node $child -Notebook $Notebook -SectionPath $newPath
        }
        elseif ($tag -eq "Section") {
            $isInRecycle = $child.GetAttribute("isInRecycleBin")
            if ($isInRecycle -eq "true") { continue }
            $newPath = if ($SectionPath) { "$SectionPath / $name" } else { $name }
            Walk-Node -Node $child -Notebook $Notebook -SectionPath $newPath
        }
        elseif ($tag -eq "Page") {
            $pageId = $child.GetAttribute("ID")
            $hyperlink = ""
            try {
                $script:onenote.GetHyperlinkToObject($pageId, "", [ref]$hyperlink)
            } catch {
                $hyperlink = ""
            }
            $row = [PSCustomObject]@{
                page_title = $name
                notebook   = $Notebook
                section    = $SectionPath
                page_id    = $pageId
                hyperlink  = $hyperlink
            }
            [void]$pages.Add($row)
        }
    }
}

Write-Host "[INFO] Walk de la hierarchie + recuperation hyperlinks..."
$script:onenote = $onenote
Walk-Node -Node $doc.DocumentElement -Notebook "" -SectionPath ""

$csvPath = Join-Path $OutDir "onenote_pages.csv"
$pages | Export-Csv -Path $csvPath -Delimiter ";" -Encoding UTF8 -NoTypeInformation
Write-Host "[OK] $($pages.Count) pages ecrites dans $csvPath"

# Stats par notebook
Write-Host ""
Write-Host "Par notebook :"
$pages | Group-Object notebook | Sort-Object Count -Descending | ForEach-Object {
    "  {0,-30} {1,6}" -f $_.Name, $_.Count
}
