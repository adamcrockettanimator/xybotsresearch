Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$form = New-Object System.Windows.Forms.Form
$form.Text = "Xybots Wall Capture Checklist"
$form.TopMost = $true
$form.StartPosition = "Manual"
$form.Location = New-Object System.Drawing.Point(40, 80)
$form.Size = New-Object System.Drawing.Size(420, 300)

$label = New-Object System.Windows.Forms.Label
$label.Dock = "Fill"
$label.Font = New-Object System.Drawing.Font("Segoe UI", 12)
$label.Padding = New-Object System.Windows.Forms.Padding(14)
$label.Text = @"
Press F11 after each state:

1. Stand still in a quiet hallway
2. Move forward once, wait
3. Move forward once again, wait
4. Turn left, wait
5. Turn right, wait
6. Turn right again, wait
7. Face a wall or door

F12 toggles auto sprite capture.
Esc exits MAME.
"@

$form.Controls.Add($label)
[void]$form.ShowDialog()
