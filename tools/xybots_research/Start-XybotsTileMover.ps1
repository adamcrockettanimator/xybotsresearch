Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ErrorActionPreference = 'Stop'

$tileSize = 8
$state = [ordered]@{
    TopRowY = $null
    CopyX = $null
    CopyY = $null
    PasteX = $null
    PasteY = $null
    JunkX = $null
    JunkY = $null
}

function Get-Photoshop {
    try {
        return [Runtime.InteropServices.Marshal]::GetActiveObject('Photoshop.Application')
    } catch {
        return New-Object -ComObject Photoshop.Application
    }
}

function Invoke-PhotoshopScript {
    param([Parameter(Mandatory)][string]$Script)

    $photoshop = Get-Photoshop
    return $photoshop.DoJavaScript($Script)
}

function Get-PointText {
    param($X, $Y)
    if ($null -eq $X -or $null -eq $Y) {
        return '--'
    }
    return "$X,$Y"
}

function Update-Status {
    $copy = Get-PointText $state.CopyX $state.CopyY
    $paste = Get-PointText $state.PasteX $state.PasteY
    $junk = Get-PointText $state.JunkX $state.JunkY
    $top = if ($null -eq $state.TopRowY) { '--' } else { $state.TopRowY }
    $script:statusLabel.Text = "Copy $copy   Paste $paste`r`nTopY $top   Junk $junk"
}

function Get-SelectedTile {
    $script = @'
(function () {
    if (!app.documents.length) {
        throw new Error("Open the Photoshop document first.");
    }
    var bounds;
    try {
        bounds = app.activeDocument.selection.bounds;
    } catch (error) {
        throw new Error("Select an 8x8 tile with the rectangular marquee first.");
    }
    return Math.round(bounds[0].as("px")) + "," + Math.round(bounds[1].as("px"));
})();
'@

    $result = Invoke-PhotoshopScript $script
    $parts = "$result".Split(',')
    return @{
        X = [int]$parts[0]
        Y = [int]$parts[1]
    }
}

function Require-Point {
    param(
        [Parameter(Mandatory)][string]$Name,
        $X,
        $Y
    )

    if ($null -eq $X -or $null -eq $Y) {
        throw "Set $Name first."
    }
}

function Select-Tile {
    param(
        [Parameter(Mandatory)][int]$X,
        [Parameter(Mandatory)][int]$Y
    )

    $script = @"
(function () {
    if (!app.documents.length) {
        throw new Error("Open the Photoshop document first.");
    }
    var doc = app.activeDocument;
    doc.selection.select([
        [$X, $Y],
        [$($X + $tileSize), $Y],
        [$($X + $tileSize), $($Y + $tileSize)],
        [$X, $($Y + $tileSize)]
    ]);
})();
"@
    Invoke-PhotoshopScript $script | Out-Null
}

function Move-Tile {
    param(
        [Parameter(Mandatory)][int]$SourceX,
        [Parameter(Mandatory)][int]$SourceY,
        [Parameter(Mandatory)][int]$TargetX,
        [Parameter(Mandatory)][int]$TargetY
    )

    $script = @"
(function () {
    if (!app.documents.length) {
        throw new Error("Open the Photoshop document first.");
    }
    var tile = $tileSize;
    var sourceX = $SourceX;
    var sourceY = $SourceY;
    var targetX = $TargetX;
    var targetY = $TargetY;
    var doc = app.activeDocument;

    function selectTile(x, y) {
        doc.selection.select([
            [x, y],
            [x + tile, y],
            [x + tile, y + tile],
            [x, y + tile]
        ]);
    }

    selectTile(sourceX, sourceY);
    doc.selection.copy(false);
    doc.selection.clear();

    selectTile(targetX, targetY);
    var pasted = doc.paste();
    doc.activeLayer = pasted;
    var bounds = pasted.bounds;
    pasted.translate(targetX - Math.round(bounds[0].as("px")), targetY - Math.round(bounds[1].as("px")));
    doc.activeLayer = pasted.merge();
})();
"@
    Invoke-PhotoshopScript $script | Out-Null
}

function Show-Error {
    param([Parameter(Mandatory)]$ErrorRecord)
    [System.Windows.Forms.MessageBox]::Show(
        "$ErrorRecord",
        'Xybots Tile Mover',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    ) | Out-Null
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Xybots Tile Mover'
$form.Size = New-Object System.Drawing.Size(370, 155)
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedToolWindow
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
$form.TopMost = $true

$font = New-Object System.Drawing.Font('Segoe UI', 9)
$form.Font = $font

function Add-Button {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][int]$X,
        [Parameter(Mandatory)][int]$Y,
        [Parameter(Mandatory)]$OnClick
    )

    $button = New-Object System.Windows.Forms.Button
    $button.Text = $Text
    $button.Size = New-Object System.Drawing.Size(78, 26)
    $button.Location = New-Object System.Drawing.Point($X, $Y)
    $button.Add_Click($OnClick)
    $form.Controls.Add($button)
}

Add-Button 'SetTop' 8 8 {
    try {
        $point = Get-SelectedTile
        $state.TopRowY = $point.Y
        if ($null -eq $state.PasteX -or $null -eq $state.PasteY) {
            $state.PasteX = $point.X
            $state.PasteY = $point.Y
        }
        Update-Status
    } catch {
        Show-Error $_
    }
}

Add-Button 'SetCopy' 91 8 {
    try {
        $point = Get-SelectedTile
        $state.CopyX = $point.X
        $state.CopyY = $point.Y
        Update-Status
    } catch {
        Show-Error $_
    }
}

Add-Button 'SetPaste' 174 8 {
    try {
        $point = Get-SelectedTile
        $state.PasteX = $point.X
        $state.PasteY = $point.Y
        if ($null -eq $state.TopRowY) {
            $state.TopRowY = $point.Y
        }
        Update-Status
    } catch {
        Show-Error $_
    }
}

Add-Button 'Move' 8 40 {
    try {
        Require-Point 'Copy' $state.CopyX $state.CopyY
        Require-Point 'Paste' $state.PasteX $state.PasteY
        Move-Tile $state.CopyX $state.CopyY $state.PasteX $state.PasteY
        $state.CopyX += $tileSize
        $state.PasteY += $tileSize
        Select-Tile $state.CopyX $state.CopyY
        Update-Status
    } catch {
        Show-Error $_
    }
}

Add-Button 'Return' 91 40 {
    try {
        Require-Point 'Paste' $state.PasteX $state.PasteY
        if ($null -eq $state.TopRowY) {
            $state.TopRowY = $state.PasteY
        }
        $state.PasteX += $tileSize
        $state.PasteY = $state.TopRowY
        Select-Tile $state.PasteX $state.PasteY
        Update-Status
    } catch {
        Show-Error $_
    }
}

Add-Button 'SetJunk' 8 72 {
    try {
        $point = Get-SelectedTile
        $state.JunkX = $point.X
        $state.JunkY = $point.Y
        Update-Status
    } catch {
        Show-Error $_
    }
}

Add-Button 'Junk' 91 72 {
    try {
        Require-Point 'Copy' $state.CopyX $state.CopyY
        Require-Point 'Junk' $state.JunkX $state.JunkY
        Move-Tile $state.CopyX $state.CopyY $state.JunkX $state.JunkY
        $state.CopyX += $tileSize
        $state.JunkX += $tileSize
        Select-Tile $state.CopyX $state.CopyY
        Update-Status
    } catch {
        Show-Error $_
    }
}

$script:statusLabel = New-Object System.Windows.Forms.Label
$script:statusLabel.Size = New-Object System.Drawing.Size(340, 34)
$script:statusLabel.Location = New-Object System.Drawing.Point(8, 105)
$form.Controls.Add($script:statusLabel)

Update-Status
[void]$form.ShowDialog()
