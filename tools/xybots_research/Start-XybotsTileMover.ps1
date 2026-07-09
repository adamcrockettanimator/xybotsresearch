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
    LayerId = $null
    LayerName = $null
    DocWidth = $null
    DocHeight = $null
    Last = 'Ready'
}
$stateHistory = New-Object System.Collections.Generic.Stack[object]

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
    $source = Get-PointText $state.CopyX $state.CopyY
    $target = Get-PointText $state.PasteX $state.PasteY
    $junk = Get-PointText $state.JunkX $state.JunkY
    $top = if ($null -eq $state.TopRowY) { '--' } else { $state.TopRowY }
    $layer = if ($null -eq $state.LayerName) { '--' } else { $state.LayerName }
    $script:statusLabel.Text = "Source $source`r`nTarget $target`r`nTopY $top   Junk $junk`r`n$($state.Last)`r`nLayer $layer"
}

function Copy-State {
    return [ordered]@{
        TopRowY = $state.TopRowY
        CopyX = $state.CopyX
        CopyY = $state.CopyY
        PasteX = $state.PasteX
        PasteY = $state.PasteY
        JunkX = $state.JunkX
        JunkY = $state.JunkY
        LayerId = $state.LayerId
        LayerName = $state.LayerName
        DocWidth = $state.DocWidth
        DocHeight = $state.DocHeight
        Last = $state.Last
    }
}

function Restore-State {
    param([Parameter(Mandatory)]$PreviousState)

    foreach ($key in $PreviousState.Keys) {
        $state[$key] = $PreviousState[$key]
    }
    Update-Status
}

function Undo-Photoshop {
    $script = @'
(function () {
    if (!app.documents.length) {
        throw new Error("Open the Photoshop document first.");
    }
    var doc = app.activeDocument;
    if (doc.historyStates.length < 2) {
        return;
    }
    doc.activeHistoryState = doc.historyStates[doc.historyStates.length - 2];
})();
'@
    Invoke-PhotoshopScript $script | Out-Null
}

function Get-ActiveLayerInfo {
    $script = @'
(function () {
    if (!app.documents.length) {
        throw new Error("Open the Photoshop document first.");
    }

    var ref = new ActionReference();
    ref.putProperty(charIDToTypeID("Prpr"), stringIDToTypeID("layerID"));
    ref.putEnumerated(charIDToTypeID("Lyr "), charIDToTypeID("Ordn"), charIDToTypeID("Trgt"));
    var id = executeActionGet(ref).getInteger(stringIDToTypeID("layerID"));

    return id + "|" + app.activeDocument.activeLayer.name;
})();
'@

    $result = Invoke-PhotoshopScript $script
    $parts = "$result".Split('|', 2)
    return @{
        Id = [int]$parts[0]
        Name = $parts[1]
    }
}

function Get-DocumentInfo {
    $script = @'
(function () {
    if (!app.documents.length) {
        throw new Error("Open the Photoshop document first.");
    }
    var doc = app.activeDocument;
    return Math.round(doc.width.as("px")) + "," + Math.round(doc.height.as("px"));
})();
'@

    $result = Invoke-PhotoshopScript $script
    $parts = "$result".Split(',')
    return @{
        Width = [int]$parts[0]
        Height = [int]$parts[1]
    }
}

function Get-NextSourcePoint {
    param(
        [Parameter(Mandatory)][int]$X,
        [Parameter(Mandatory)][int]$Y
    )

    $nextX = $X + $tileSize
    $nextY = $Y
    if ($null -ne $state.DocWidth -and ($nextX + $tileSize) -gt $state.DocWidth) {
        $nextX = 0
        $nextY += $tileSize
    }
    return @{
        X = $nextX
        Y = $nextY
        Wrapped = ($nextX -eq 0 -and $nextY -ne $Y)
    }
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
        [Parameter(Mandatory)][int]$FinalSelectY,
        [Parameter(Mandatory)][int]$LayerId
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
    var layerId = $LayerId;
    var doc = app.activeDocument;
    var xybotsMoveResult = "moved";

    function selectLayerById(id) {
        var ref = new ActionReference();
        ref.putIdentifier(charIDToTypeID("Lyr "), id);
        var desc = new ActionDescriptor();
        desc.putReference(charIDToTypeID("null"), ref);
        desc.putBoolean(charIDToTypeID("MkVs"), false);
        executeAction(charIDToTypeID("slct"), desc, DialogModes.NO);
    }

    function selectTile(x, y) {
        doc.selection.select([
            [x, y],
            [x + tile, y],
            [x + tile, y + tile],
            [x, y + tile]
        ]);
    }

    function xybotsTileMoverMove() {
        selectLayerById(layerId);
        var sourceLayer = doc.activeLayer;

        selectTile(sourceX, sourceY);
        try {
            executeAction(charIDToTypeID("CtTL"), undefined, DialogModes.NO);
        } catch (cutError) {
            if (!/empty/i.test(cutError.message)) {
                throw cutError;
            }
            xybotsMoveResult = "empty";
            selectTile(finalSelectX, finalSelectY);
            return;
        }
        var movedLayer = doc.activeLayer;
        if (movedLayer == sourceLayer) {
            throw new Error("Photoshop did not isolate the selected 8x8 tile; aborting before moving the source layer.");
        }
        movedLayer.name = "xybots tile move";
        movedLayer.blendMode = BlendMode.NORMAL;
        movedLayer.opacity = 100;

        doc.activeLayer = movedLayer;
        movedLayer.translate(targetX - sourceX, targetY - sourceY);

        try {
            executeAction(charIDToTypeID("Mrg2"), undefined, DialogModes.NO);
        } catch (mergeError) {
            // If merge-down is refused, leave the small moved-tile layer. The
            // source layer remains locked by id for later operations.
        }

        selectTile(finalSelectX, finalSelectY);
    }

    doc.suspendHistory("Xybots Tile Move", "xybotsTileMoverMove()");
    return xybotsMoveResult;
})();
"@
    return Invoke-PhotoshopScript $script
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
$form.Size = New-Object System.Drawing.Size(132, 355)
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
    $button.Size = New-Object System.Drawing.Size(98, $Height)
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

Add-Button 'Source' 8 38 {
    try {
        $point = Get-SelectedTile
        $layer = Get-ActiveLayerInfo
        $docInfo = Get-DocumentInfo
        $state.CopyX = $point.X
        $state.CopyY = $point.Y
        $state.LayerId = $layer.Id
        $state.LayerName = $layer.Name
        $state.DocWidth = $docInfo.Width
        $state.DocHeight = $docInfo.Height
        Update-Status
    } catch {
        Show-Error $_
    }
}

Add-Button 'Target' 8 68 {
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
        if ($null -eq $state.LayerId) { throw 'Source first so the tool can lock onto the source layer.' }
        $previousState = Copy-State
        $nextSource = Get-NextSourcePoint $state.CopyX $state.CopyY
        $nextCopyX = $nextSource.X
        $nextCopyY = $nextSource.Y
        $result = Move-Tile $state.CopyX $state.CopyY $state.JunkX $state.JunkY $nextCopyX $nextCopyY $state.LayerId
        $stateHistory.Push([pscustomobject]@{ State = $previousState; Photoshop = ($result -ne 'empty') })
        $state.CopyX = $nextCopyX
        $state.CopyY = $nextCopyY
        $state.JunkX += $tileSize
        $state.Last = if ($result -eq 'empty') { 'Empty source tile' } elseif ($nextSource.Wrapped) { 'Moved to junk; source wrapped' } else { 'Moved to junk' }
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
        if ($null -eq $state.LayerId) { throw 'Source first so the tool can lock onto the source layer.' }
        $previousState = Copy-State
        $nextSource = Get-NextSourcePoint $state.CopyX $state.CopyY
        $nextCopyX = $nextSource.X
        $nextCopyY = $nextSource.Y
        $result = Move-Tile $state.CopyX $state.CopyY $state.PasteX $state.PasteY $nextCopyX $nextCopyY $state.LayerId
        $stateHistory.Push([pscustomobject]@{ State = $previousState; Photoshop = ($result -ne 'empty') })
        $state.CopyX = $nextCopyX
        $state.CopyY = $nextCopyY
        $state.PasteY += $tileSize
        $state.Last = if ($result -eq 'empty') { 'Empty source tile' } elseif ($nextSource.Wrapped) { 'Moved; source wrapped' } else { 'Moved' }
        Update-Status
    } catch {
        Show-Error $_
    }
} 56

Add-Button 'Undo' 8 248 {
    try {
        if ($stateHistory.Count -gt 0) {
            $entry = $stateHistory.Pop()
            if ($entry.PSObject.Properties.Name -contains 'Photoshop') {
                if ($entry.Photoshop) {
                    Undo-Photoshop
                }
                Restore-State $entry.State
            } else {
                Undo-Photoshop
                Restore-State $entry
            }
        } else {
            Update-Status
        }
    } catch {
        Show-Error $_
    }
}

$script:statusLabel = New-Object System.Windows.Forms.Label
$script:statusLabel.Size = New-Object System.Drawing.Size(112, 82)
$script:statusLabel.Location = New-Object System.Drawing.Point(8, 280)
$form.Controls.Add($script:statusLabel)

Update-Status
[void]$form.ShowDialog()
