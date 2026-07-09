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
        [Parameter(Mandatory)][int]$TargetY,
        [Parameter(Mandatory)][int]$FinalSelectX,
        [Parameter(Mandatory)][int]$FinalSelectY
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
    var finalSelectX = $FinalSelectX;
    var finalSelectY = $FinalSelectY;
    var doc = app.activeDocument;

    function selectTile(x, y) {
        doc.selection.select([
            [x, y],
            [x + tile, y],
            [x + tile, y + tile],
            [x, y + tile]
        ]);
    }

    function xybotsTileMoverMove() {
        selectTile(sourceX, sourceY);
        doc.selection.copy(false);

        // Photoshop paste bounds collapse to non-transparent pixels. Probe once
        // so sparse 8x8 tiles keep their internal offset when moved.
        var probe = doc.paste();
        doc.activeLayer = probe;
        var probeBounds = probe.bounds;
        var offsetX = Math.round(probeBounds[0].as("px")) - sourceX;
        var offsetY = Math.round(probeBounds[1].as("px")) - sourceY;
        probe.remove();

        selectTile(sourceX, sourceY);
        doc.selection.clear();

        selectTile(targetX, targetY);
        var pasted = doc.paste();
        doc.activeLayer = pasted;
        var bounds = pasted.bounds;
        pasted.translate(
            targetX + offsetX - Math.round(bounds[0].as("px")),
            targetY + offsetY - Math.round(bounds[1].as("px"))
        );
        doc.activeLayer = pasted.merge();
        selectTile(finalSelectX, finalSelectY);
    }

    doc.suspendHistory("Xybots Tile Move", "xybotsTileMoverMove()");
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
$form.Size = New-Object System.Drawing.Size(120, 305)
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
        [Parameter(Mandatory)]$OnClick,
        [int]$Height = 26
    )

    $button = New-Object System.Windows.Forms.Button
    $button.Text = $Text
    $button.Size = New-Object System.Drawing.Size(86, $Height)
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

Add-Button 'SetCopy' 8 38 {
    try {
        $point = Get-SelectedTile
        $state.CopyX = $point.X
        $state.CopyY = $point.Y
        Update-Status
    } catch {
        Show-Error $_
    }
}

Add-Button 'SetPaste' 8 68 {
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

Add-Button 'SetJunk' 8 98 {
    try {
        $point = Get-SelectedTile
        $state.JunkX = $point.X
        $state.JunkY = $point.Y
        Update-Status
    } catch {
        Show-Error $_
    }
}

Add-Button 'Junk' 8 128 {
    try {
        Require-Point 'Copy' $state.CopyX $state.CopyY
        Require-Point 'Junk' $state.JunkX $state.JunkY
        $nextCopyX = $state.CopyX + $tileSize
        $nextCopyY = $state.CopyY
        Move-Tile $state.CopyX $state.CopyY $state.JunkX $state.JunkY $nextCopyX $nextCopyY
        $state.CopyX = $nextCopyX
        $state.CopyY = $nextCopyY
        $state.JunkX += $tileSize
        Update-Status
    } catch {
        Show-Error $_
    }
}

Add-Button 'Return' 8 158 {
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

Add-Button 'Move' 8 188 {
    try {
        Require-Point 'Copy' $state.CopyX $state.CopyY
        Require-Point 'Paste' $state.PasteX $state.PasteY
        $nextCopyX = $state.CopyX + $tileSize
        $nextCopyY = $state.CopyY
        Move-Tile $state.CopyX $state.CopyY $state.PasteX $state.PasteY $nextCopyX $nextCopyY
        $state.CopyX = $nextCopyX
        $state.CopyY = $nextCopyY
        $state.PasteY += $tileSize
        Update-Status
    } catch {
        Show-Error $_
    }
} 56

$script:statusLabel = New-Object System.Windows.Forms.Label
$script:statusLabel.Size = New-Object System.Drawing.Size(96, 48)
$script:statusLabel.Location = New-Object System.Drawing.Point(8, 250)
$form.Controls.Add($script:statusLabel)

Update-Status
[void]$form.ShowDialog()
