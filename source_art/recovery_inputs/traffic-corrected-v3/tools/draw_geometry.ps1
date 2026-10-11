param([Parameter(Mandatory=$true)][string]$GeometryPath, [Parameter(Mandatory=$true)][string]$OutPath)
Add-Type -AssemblyName System.Drawing
$geoData = Get-Content -LiteralPath $GeometryPath -Raw | ConvertFrom-Json
$canvas = [System.Drawing.Bitmap]::new(1680, 900)
$graphics = [System.Drawing.Graphics]::FromImage($canvas)
$graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$graphics.Clear([System.Drawing.Color]::FromArgb(246,248,250))
$fontTitle = [System.Drawing.Font]::new('Segoe UI',25,[System.Drawing.FontStyle]::Bold)
$fontHeading = [System.Drawing.Font]::new('Segoe UI',16,[System.Drawing.FontStyle]::Bold)
$fontText = [System.Drawing.Font]::new('Segoe UI',12)
$fontSmall = [System.Drawing.Font]::new('Segoe UI',10)
$ink = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(25,36,50))
$muted = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(85,101,117))
$routeColor = [System.Drawing.Color]::FromArgb(0,118,119)
$routePen = [System.Drawing.Pen]::new($routeColor,3)
$directPen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(191,113,36),2)
$directPen.DashStyle = [System.Drawing.Drawing2D.DashStyle]::Dash
$gridPen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(221,227,233),1)
$framePen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(170,182,194),1)
$envelopePen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(131,144,157),1.5)
$envelopePen.DashStyle = [System.Drawing.Drawing2D.DashStyle]::Dash
$trafficBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(72,100,128))
$patrolBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(163,62,64))

function Plot-Panel([single]$left,[single]$top,[single]$scale,[single]$xmin,[single]$xmax,[bool]$labels) {
    $ymin = -24.0
    $width = ($xmax - $xmin) * $scale
    $height = 24.0 * $scale
    $graphics.FillRectangle([System.Drawing.Brushes]::White,$left,$top,[single]$width,[single]$height)
    $graphics.SetClip([System.Drawing.RectangleF]::new($left,$top,[single]$width,[single]$height))
    foreach ($x in @(0,20,40,60,80,100,120,140,160,180,200,220,240,260,280,300,320,340,360)) {
        if ($x -ge $xmin -and $x -le $xmax) { $px=$left+($x-$xmin)*$scale; $graphics.DrawLine($gridPen,[single]$px,$top,[single]$px,[single]($top+$height)) }
    }
    foreach ($y in @(-20,-16,-12,-8,-4,0)) {
        $py=$top+($y-$ymin)*$scale
        $graphics.DrawLine($gridPen,$left,[single]$py,[single]($left+$width),[single]$py)
    }
    [System.Drawing.PointF[]]$direct = @($geoData.direct_points | ForEach-Object { [System.Drawing.PointF]::new([single]($left+($_[0]-$xmin)*$scale),[single]($top+($_[1]-$ymin)*$scale)) })
    [System.Drawing.PointF[]]$route = @($geoData.detour_points | ForEach-Object { [System.Drawing.PointF]::new([single]($left+($_[0]-$xmin)*$scale),[single]($top+($_[1]-$ymin)*$scale)) })
    $graphics.DrawLines($directPen,$direct)
    $graphics.DrawLines($routePen,$route)
    foreach ($actor in $geoData.actors) {
        $px=$left+($actor.x-$xmin)*$scale
        $py=$top+($actor.y-$ymin)*$scale
        $radius=$actor.radius_m*$scale
        $outer=($actor.radius_m+$geoData.craft_radius_m)*$scale
        $bodyBrush = if ($actor.role -eq 'patrol') { $patrolBrush } else { $trafficBrush }
        $graphics.DrawEllipse($envelopePen,[single]($px-$outer),[single]($py-$outer),[single](2*$outer),[single](2*$outer))
        $graphics.FillEllipse($bodyBrush,[single]($px-$radius),[single]($py-$radius),[single](2*$radius),[single](2*$radius))
        if ($labels) {
            $graphics.DrawString($actor.role,$fontSmall,$ink,[single]($px+12),[single]($py+12))
        }
    }
    if ($labels) {
        $patrol = $geoData.actors | Where-Object role -eq 'patrol'
        $px=$left+($patrol.x-$xmin)*$scale
        $pyRoute=$top+(-20-$ymin)*$scale
        $pyEnvelope=$top+($patrol.y-$patrol.radius_m-$geoData.craft_radius_m-$ymin)*$scale
        $graphics.DrawLine($framePen,[single]$px,[single]$pyRoute,[single]$px,[single]$pyEnvelope)
        $graphics.DrawLine($framePen,[single]($px-5),[single]$pyRoute,[single]($px+5),[single]$pyRoute)
        $graphics.DrawLine($framePen,[single]($px-5),[single]$pyEnvelope,[single]($px+5),[single]$pyEnvelope)
        $graphics.DrawString('3.75 m spare',$fontSmall,$ink,[single]($px+10),[single](($pyRoute+$pyEnvelope)/2-10))
    }
    $graphics.ResetClip()
    $graphics.DrawRectangle($framePen,$left,$top,[single]$width,[single]$height)
    $tickXs = if ($labels) { @(90,100,110,120,130,140,150,155) } else { @(0,20,85,150,185,275,340,360) }
    foreach ($x in $tickXs) {
        $px=$left+($x-$xmin)*$scale
        $graphics.DrawString([string]$x,$fontSmall,$muted,[single]($px-10),[single]($top+$height+8))
    }
    $tickYs = if ($labels) { @(-24,-20,-16,-12,-8,-4,0) } else { @(-24,-8,0) }
    foreach ($y in $tickYs) {
        $py=$top+($y-$ymin)*$scale
        $graphics.DrawString([string]$y,$fontSmall,$muted,[single]($left-40),[single]($py-9))
    }
}

try {
    $graphics.DrawString('360 m ground route - static integration reference',$fontTitle,$ink,40,28)
    $graphics.DrawString('Seed 42 | +x right, +y down | Reference craft radius 1.0 m | Technical diagram, not game art',$fontText,$muted,43,77)
    $graphics.DrawString('Full route (metres)',$fontHeading,$ink,80,128)
    Plot-Panel 80 163 4.15 0 360 $false
    $graphics.DrawString('Local obstruction and detour (same scale in x and y)',$fontHeading,$ink,80,336)
    Plot-Panel 80 383 14 90 155 $true
    $graphics.DrawString('What this fixture proves',$fontHeading,$ink,1050,392)
    $graphics.DrawString("Direct y = -8 m path is blocked.`nThe shown detour clears initial circles.`nMinimum spare clearance: 3.75 m.`nInitial bodies do not overlap.",$fontText,$ink,1050,439)
    $graphics.DrawLine($routePen,1052,565,1095,565)
    $graphics.DrawString('Detour centreline',$fontText,$ink,1110,553)
    $graphics.DrawLine($directPen,1052,603,1095,603)
    $graphics.DrawString('Blocked direct reference line',$fontText,$ink,1110,591)
    $graphics.DrawEllipse($envelopePen,1060,634,22,22)
    $graphics.DrawString('Body radius + 1 m craft radius',$fontText,$ink,1110,631)
    $graphics.DrawString('Reference gate x values: 85, 185, 275 m',$fontText,$muted,1050,690)
    $graphics.DrawString('No baseline colliders or moving-body safety proof. No ground plane is assumed.',$fontHeading,$ink,80,803)
    $graphics.DrawString('Data comes from the native helper GEOMETRY.json. Rendered offline; no game window or collision solver.',$fontText,$muted,80,842)
    $canvas.Save($OutPath,[System.Drawing.Imaging.ImageFormat]::Png)
    Write-Output $OutPath
} finally {
    $graphics.Dispose()
    $canvas.Dispose()
    foreach ($resource in @($fontTitle,$fontHeading,$fontText,$fontSmall,$ink,$muted,$routePen,$directPen,$gridPen,$framePen,$envelopePen,$trafficBrush,$patrolBrush)) { $resource.Dispose() }
}
