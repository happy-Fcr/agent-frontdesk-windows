param(
  [Parameter(Mandatory=$true)][string]$Profile,
  [Parameter(Mandatory=$true)][ValidateSet('status','list','read','new','send','show','stop')][string]$Command,
  [string]$Session = '',
  [string]$InputBase64 = ''
)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new()
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public static class FrontdeskNative {
  public delegate bool EnumChildProc(IntPtr hwnd, IntPtr data);
  [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr parent, EnumChildProc cb, IntPtr data);
  [DllImport("user32.dll", CharSet=CharSet.Auto)] public static extern int GetClassName(IntPtr hwnd, StringBuilder text, int max);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern bool PostMessage(IntPtr hwnd, uint message, IntPtr wParam, IntPtr lParam);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
}
'@

$cfg = Get-Content -LiteralPath $Profile -Raw -Encoding UTF8 | ConvertFrom-Json
function Reply($value) { $value | ConvertTo-Json -Depth 8 -Compress; exit 0 }
function Fail([string]$message, [string]$code='UNAVAILABLE') { Reply ([ordered]@{ok=$false;code=$code;error=$message}) }
function WindowRoot {
  foreach ($name in @($cfg.processNames)) {
    $process = Get-Process -Name $name -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
    if ($process) { return [pscustomobject]@{ process=$process; root=[System.Windows.Automation.AutomationElement]::FromHandle($process.MainWindowHandle) } }
  }
  return $null
}
function All($root) { $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition) }
function HasPattern($element, $pattern) { $value=$null; return $element.TryGetCurrentPattern($pattern, [ref]$value) }
function Pattern($element, $pattern) { $value=$null; if($element.TryGetCurrentPattern($pattern,[ref]$value)){return $value}; return $null }
function Matches($element, $spec) {
  if (-not $spec) { return $false }
  $role = $element.Current.ControlType.ProgrammaticName -replace '^ControlType\.', ''
  if ($spec.role -and $role -ne $spec.role) { return $false }
  if ($spec.name -and $element.Current.Name -notin @($spec.name)) { return $false }
  if ($spec.namePrefix -and -not $element.Current.Name.StartsWith([string]$spec.namePrefix)) { return $false }
  if ($spec.id -and $element.Current.AutomationId -ne $spec.id) { return $false }
  if ($spec.classContains -and -not $element.Current.ClassName.Contains([string]$spec.classContains)) { return $false }
  return $true
}
function Find($root, $spec) {
  $result = New-Object System.Collections.Generic.List[object]
  $items = All $root
  for($i=0;$i -lt $items.Count;$i++){ $item=$items.Item($i); if(Matches $item $spec){$result.Add($item)} }
  return ,$result
}
function InvokeOne($root, $spec, [string]$label) {
  $found = Find $root $spec
  if($found.Count -ne 1){ throw "$label matched $($found.Count) controls; no action was taken" }
  $invoke = Pattern $found[0] ([System.Windows.Automation.InvokePattern]::Pattern)
  if(-not $invoke){ throw "$label does not support a standard accessibility action" }
  $invoke.Invoke()
}
function ElementText($element) {
  $text = Pattern $element ([System.Windows.Automation.TextPattern]::Pattern)
  if($text){ return $text.DocumentRange.GetText(-1) }
  $value = Pattern $element ([System.Windows.Automation.ValuePattern]::Pattern)
  if($value){ return $value.Current.Value }
  return $element.Current.Name
}
function DocumentUrl($root) {
  $docs = Find $root ([pscustomobject]@{role='Document'})
  foreach($doc in $docs){ $value=Pattern $doc ([System.Windows.Automation.ValuePattern]::Pattern); if($value -and $value.Current.Value -match '^https?://|^chrome://'){return [string]$value.Current.Value} }
  return ''
}
function Snapshot($root) {
  $items = All $root; $rows = New-Object System.Collections.Generic.List[object]
  for($i=0;$i -lt $items.Count;$i++){
    $item=$items.Item($i); $name=[string]$item.Current.Name
    if(-not $name){continue}
    $role=$item.Current.ControlType.ProgrammaticName -replace '^ControlType\.', ''
    if($role -notin @('Text','Heading','Document','Edit','Hyperlink','Button')){continue}
    $rows.Add([ordered]@{role=$role;name=$name;id=[string]$item.Current.AutomationId;class=[string]$item.Current.ClassName})
  }
  return [ordered]@{url=(DocumentUrl $root);items=$rows}
}
function DebugTree($root) {
  $items=All $root; $rows=New-Object System.Collections.Generic.List[object]
  for($i=0;$i -lt $items.Count;$i++){
    $item=$items.Item($i); $name=[string]$item.Current.Name
    if(-not $name){continue}
    $role=$item.Current.ControlType.ProgrammaticName -replace '^ControlType\.',''
    $class=[string]$item.Current.ClassName
    if($role -notin @('Text','Heading') -and -not ($role -eq 'Group' -and $class -match 'message|chat|flow|user|answer|content|markdown|bubble|item')){continue}
    $parents=New-Object System.Collections.Generic.List[object]; $cursor=$item
    for($depth=0;$depth -lt 6;$depth++){
      try{$cursor=[System.Windows.Automation.TreeWalker]::ControlViewWalker.GetParent($cursor)}catch{$cursor=$null}
      if(-not $cursor){break}
      $parentName=[string]$cursor.Current.Name; if($parentName.Length -gt 80){$parentName=$parentName.Substring(0,80)}
      $parents.Add([ordered]@{role=($cursor.Current.ControlType.ProgrammaticName -replace '^ControlType\.','');name=$parentName;id=[string]$cursor.Current.AutomationId;class=[string]$cursor.Current.ClassName})
    }
    $rect=$item.Current.BoundingRectangle
    $x=if([double]::IsInfinity($rect.X) -or [double]::IsNaN($rect.X)){-1}else{[int]$rect.X}
    $y=if([double]::IsInfinity($rect.Y) -or [double]::IsNaN($rect.Y)){-1}else{[int]$rect.Y}
    if($name.Length -gt 160){$name=$name.Substring(0,160)}
    $whole=''
    if($role -eq 'Group' -and ($name -eq 'doc_editor' -or $class -match 'chat-history')){try{$whole=[string](ElementText $item);if($whole.Length -gt 600){$whole=$whole.Substring(0,600)}}catch{}}
    $rows.Add([ordered]@{role=$role;name=$name;id=[string]$item.Current.AutomationId;class=[string]$item.Current.ClassName;x=$x;y=$y;text=$whole;parents=$parents})
  }
  return $rows
}
function RawClasses($root) {
  $rows=New-Object System.Collections.Generic.List[object]; $seen=@{}; $stack=New-Object System.Collections.Stack
  $stack.Push($root); $walk=[System.Windows.Automation.TreeWalker]::RawViewWalker; $visited=0
  while($stack.Count -gt 0 -and $visited -lt 30000){
    $item=$stack.Pop(); $visited++
    try{$class=[string]$item.Current.ClassName;$role=$item.Current.ControlType.ProgrammaticName -replace '^ControlType\.','';$name=[string]$item.Current.Name}catch{continue}
    if($class -and $class -match 'message|chat|flow|user|assistant|answer|content|markdown|bubble|query|response|turn|item'){
      $key="$role`n$class"; if(-not $seen.ContainsKey($key)){$seen[$key]=$true;if($name.Length -gt 100){$name=$name.Substring(0,100)};$rows.Add([ordered]@{role=$role;name=$name;id=[string]$item.Current.AutomationId;class=$class})}
    }
    $children=New-Object System.Collections.Generic.List[object]
    try{$child=$walk.GetFirstChild($item);while($child){$children.Add($child);$child=$walk.GetNextSibling($child)}}catch{}
    for($i=$children.Count-1;$i -ge 0;$i--){$stack.Push($children[$i])}
  }
  return $rows
}
function RawMessageNodes($root) {
  $rows=New-Object System.Collections.Generic.List[object]; $walk=[System.Windows.Automation.TreeWalker]::RawViewWalker
  $container=$null; $seek=New-Object System.Collections.Stack; $seek.Push($root); $searched=0
  while($seek.Count -gt 0 -and $searched -lt 30000){$candidate=$seek.Pop();$searched++
    try{if(([string]$candidate.Current.ClassName) -eq 'list_items'){$container=$candidate;break}}catch{}
    $seekChildren=New-Object System.Collections.Generic.List[object]
    try{$seekChild=$walk.GetFirstChild($candidate);while($seekChild){$seekChildren.Add($seekChild);$seekChild=$walk.GetNextSibling($seekChild)}}catch{}
    for($i=$seekChildren.Count-1;$i -ge 0;$i--){$seek.Push($seekChildren[$i])}
  }
  if(-not $container){return $rows}
  $stack=New-Object System.Collections.Stack; $stack.Push([pscustomobject]@{item=$container;depth=0}); $visited=0
  while($stack.Count -gt 0 -and $visited -lt 400){$node=$stack.Pop();$item=$node.item;$depth=[int]$node.depth;$visited++
    try{$name=[string]$item.Current.Name;$class=[string]$item.Current.ClassName;$role=$item.Current.ControlType.ProgrammaticName -replace '^ControlType\.',''}catch{continue}
    if($name.Length -gt 120){$name=$name.Substring(0,120)};$rows.Add([ordered]@{depth=$depth;role=$role;name=$name;id=[string]$item.Current.AutomationId;class=$class})
    if($depth -ge 5){continue};$children=New-Object System.Collections.Generic.List[object]
    try{$child=$walk.GetFirstChild($item);while($child){$children.Add($child);$child=$walk.GetNextSibling($child)}}catch{}
    for($i=$children.Count-1;$i -ge 0;$i--){$stack.Push([pscustomobject]@{item=$children[$i];depth=$depth+1})}
  }
  return $rows
}
function ChildElements($element, $walker) {
  $children=New-Object System.Collections.Generic.List[object]
  try{$child=$walker.GetFirstChild($element);while($child){$children.Add($child);$child=$walker.GetNextSibling($child)}}catch{}
  return ,$children
}
function VisibleText($element, $walker) {
  $parts=New-Object System.Collections.Generic.List[string]; $stack=New-Object System.Collections.Stack; $stack.Push($element)
  while($stack.Count -gt 0){$item=$stack.Pop()
    try{$role=$item.Current.ControlType.ProgrammaticName -replace '^ControlType\.','';$name=([string]$item.Current.Name).Trim();$class=[string]$item.Current.ClassName}catch{continue}
    $children=ChildElements $item $walker
    if($role -in @('Text','Heading','Hyperlink') -and $name -and $class -notmatch 'visually-hidden|screen-reader'){
      $hasTextChild=$false
      foreach($child in $children){try{$childRole=$child.Current.ControlType.ProgrammaticName -replace '^ControlType\.','';if($childRole -in @('Text','Heading','Hyperlink') -and ([string]$child.Current.Name).Trim()){$hasTextChild=$true;break}}catch{}}
      if(-not $hasTextChild -and ($parts.Count -eq 0 -or $parts[$parts.Count-1] -ne $name)){$parts.Add($name)}
    }
    for($i=$children.Count-1;$i -ge 0;$i--){$stack.Push($children[$i])}
  }
  $joined=($parts -join "`n").Trim(); if($joined.Length -gt 20000){return $joined.Substring(0,20000)}; return $joined
}
function FindRawByClass($root, [string]$wanted) {
  $walker=[System.Windows.Automation.TreeWalker]::RawViewWalker; $stack=New-Object System.Collections.Stack; $stack.Push($root); $visited=0
  while($stack.Count -gt 0 -and $visited -lt 30000){$item=$stack.Pop();$visited++
    try{if(([string]$item.Current.ClassName) -eq $wanted){return $item}}catch{}
    $children=ChildElements $item $walker; for($i=$children.Count-1;$i -ge 0;$i--){$stack.Push($children[$i])}
  }
  return $null
}
function FindHistoryRawContainer($root, $history) {
  $start=$root
  if($history.parent){$parents=Find $root $history.parent;if($parents.Count -gt 0){$start=$parents[0]}}
  return FindRawByClass $start ([string]$history.containerClass)
}
function RawRowMessages($container, $history) {
  $walker=[System.Windows.Automation.TreeWalker]::RawViewWalker; $messages=New-Object System.Collections.Generic.List[object]
  foreach($row in (ChildElements $container $walker)){
    try{if(([string]$row.Current.ClassName).Trim() -ne 'v_list_row'){continue}}catch{continue}
    $text=VisibleText $row $walker; if(-not $text){continue}
    if($text -match '^\S{2,8}\s+\d{1,2}:\d{2}(\r?\n.{1,80})?$'){continue}
    $assistant=$false; $firstTextX=99999; $stack=New-Object System.Collections.Stack; $stack.Push($row)
    while($stack.Count -gt 0){$item=$stack.Pop();try{$itemRole=$item.Current.ControlType.ProgrammaticName -replace '^ControlType\.','';if(([string]$item.Current.Name) -eq ([string]$history.assistantMarker)){$assistant=$true};if($itemRole -eq 'Text' -and ([string]$item.Current.Name).Trim()){$rect=$item.Current.BoundingRectangle;if(-not [double]::IsInfinity($rect.X) -and -not [double]::IsNaN($rect.X) -and $rect.X -ge 0 -and $rect.X -lt $firstTextX){$firstTextX=[int]$rect.X}}}catch{};$children=ChildElements $item $walker;for($i=$children.Count-1;$i -ge 0;$i--){$stack.Push($children[$i])}}
    if(-not $assistant -and $history.assistantMaxX -and $firstTextX -le [int]$history.assistantMaxX){$assistant=$true}
    if(-not $assistant -and $firstTextX -eq 99999 -and $text.Contains("`n")){$assistant=$true}
    $messages.Add([ordered]@{role=if($assistant){'assistant'}else{'user'};text=$text})
  }
  return $messages
}
function RawVirtualTranscript($root, $history) {
  $seen=@{}; $messages=New-Object System.Collections.Generic.List[object]; $walker=[System.Windows.Automation.TreeWalker]::RawViewWalker
  $container=FindHistoryRawContainer $root $history; if(-not $container){return $messages}
  $scroll=$container
  while($scroll){$pattern=Pattern $scroll ([System.Windows.Automation.ScrollPattern]::Pattern);if($pattern -and $pattern.Current.VerticallyScrollable){break};try{$scroll=$walker.GetParent($scroll)}catch{$scroll=$null}}
  $points=if($scroll){@(0,25,50,75,100)}else{@(100)}
  foreach($point in $points){
    if($scroll){try{$pattern.SetScrollPercent([System.Windows.Automation.ScrollPattern]::NoScroll,[double]$point);Start-Sleep -Milliseconds 180}catch{}}
    try{$page=@(RawRowMessages $container $history)}catch{$fresh=WindowRoot;if(-not $fresh){break};$container=FindHistoryRawContainer $fresh.root $history;if(-not $container){continue};$page=@(RawRowMessages $container $history)}
    foreach($message in $page){$key="$($message.role)`n$($message.text)";if(-not $seen.ContainsKey($key) -and $messages.Count -lt 24){$seen[$key]=$true;$messages.Add($message)}}
  }
  if($scroll){try{$pattern.SetScrollPercent([System.Windows.Automation.ScrollPattern]::NoScroll,100)}catch{}}
  return $messages
}
function Transcript($root) {
  $messages=New-Object System.Collections.Generic.List[object]; if(-not $cfg.history){return $messages}
  if($cfg.history.kind -eq 'rawVirtual'){return RawVirtualTranscript $root $cfg.history}
  $walker=[System.Windows.Automation.TreeWalker]::ControlViewWalker; $items=All $root
  for($i=0;$i -lt $items.Count;$i++){$item=$items.Item($i);$messageRole=''
    if(Matches $item $cfg.history.user){$messageRole='user'}elseif(Matches $item $cfg.history.assistant){$messageRole='assistant'}else{continue}
    $text=VisibleText $item $walker; if($text){$messages.Add([ordered]@{role=$messageRole;text=$text})}
  }
  return $messages
}
function BlockReason($root) {
  $text = ((Snapshot $root).items | ForEach-Object {$_.name}) -join "`n"
  foreach($marker in @($cfg.signedOutMarkers)){ if($marker -and $text -match [regex]::Escape([string]$marker)){return "$($cfg.label) is signed out; sign in in the desktop app first"} }
  return ''
}
function Sessions($root) {
  $out=New-Object System.Collections.Generic.List[object]; $seen=@{}
  foreach($spec in @($cfg.sessions)){
    foreach($item in (Find $root $spec)){
      $title=[string]$item.Current.Name
      if($cfg.sessionTitleStrip){$title=[regex]::Replace($title,[string]$cfg.sessionTitleStrip,'').Trim()}
      if(-not $title -or $seen.ContainsKey($title)){continue}
      $skip=$false; foreach($name in @($cfg.sessionSkip)){if($title -eq $name -or $title -like $name){$skip=$true;break}}
      if($skip){continue}; $seen[$title]=$true
      $value=Pattern $item ([System.Windows.Automation.ValuePattern]::Pattern); $id=if($value -and $value.Current.Value){[string]$value.Current.Value}else{$title}
      $out.Add([ordered]@{id=$id;title=$title})
    }
  }
  if($out.Count -eq 0){$url=DocumentUrl $root; $out.Add([ordered]@{id=if($url){$url}else{'current'};title="Current chat"})}
  return $out
}
function SessionElement($root, [string]$session) {
  foreach($spec in @($cfg.sessions)){
    foreach($item in (Find $root $spec)){
      $title=[string]$item.Current.Name
      if($cfg.sessionTitleStrip){$title=[regex]::Replace($title,[string]$cfg.sessionTitleStrip,'').Trim()}
      $value=Pattern $item ([System.Windows.Automation.ValuePattern]::Pattern); $id=if($value -and $value.Current.Value){[string]$value.Current.Value}else{$title}
      if($id -eq $session -or $title -eq $session){return $item}
    }
  }
  return $null
}
function RendererHandle($process) {
  $handles=New-Object System.Collections.Generic.List[System.IntPtr]
  [FrontdeskNative]::EnumChildWindows($process.MainWindowHandle,{param($h,$d);$sb=New-Object Text.StringBuilder 256;[void][FrontdeskNative]::GetClassName($h,$sb,256);if($sb.ToString() -match 'Chrome_RenderWidgetHostHWND'){ $handles.Add($h) };return $true},[IntPtr]::Zero)|Out-Null
  if($handles.Count -eq 0){throw 'Desktop web input window was not found'}
  return $handles[$handles.Count-1]
}
function FillComposer($window, [string]$prompt) {
  $found=Find $window.root $cfg.composer
  if($found.Count -ne 1){throw "Composer matched $($found.Count) controls; nothing was sent"}
  $composer=$found[0]; $current=(ElementText $composer).Trim()
  foreach($placeholder in @($cfg.composerPlaceholders)){if($current -eq $placeholder){$current=''}}
  if($current){throw 'The desktop composer already contains an unsent draft; handle it before sending from Frontdesk'}
  $value=Pattern $composer ([System.Windows.Automation.ValuePattern]::Pattern)
  if($value -and -not $value.Current.IsReadOnly){$value.SetValue($prompt)} else {
    $text=Pattern $composer ([System.Windows.Automation.TextPattern]::Pattern)
    if(-not $text){throw 'The composer does not support background input'}
    $before=[FrontdeskNative]::GetForegroundWindow(); $composer.SetFocus(); $target=RendererHandle $window.process
    foreach($ch in $prompt.ToCharArray()){[void][FrontdeskNative]::PostMessage($target,0x0102,[IntPtr][int][char]$ch,[IntPtr]::Zero)}
    Start-Sleep -Milliseconds 250
    if([FrontdeskNative]::GetForegroundWindow() -ne $before){throw 'Sending stopped because the desktop app took foreground focus'}
  }
  if(-not (ElementText $composer).Contains($prompt)){throw 'The desktop app did not confirm the input; nothing was sent'}
}

$window=WindowRoot
if(-not $window){Fail "$($cfg.label) is not running; open the desktop app first" 'NOT_RUNNING'}
$blocked=BlockReason $window.root
if($Command -eq 'status'){Reply ([ordered]@{ok=$true;connected=(-not $blocked);error=$blocked;where=$window.process.Path})}
if($blocked){Fail $blocked 'SIGNED_OUT'}
if($Command -eq 'list'){Reply ([ordered]@{ok=$true;sessions=@(Sessions $window.root);snapshot=(Snapshot $window.root)})}
if($Command -eq 'read'){
  if($Session -and $Session -ne 'current' -and $Session -ne (DocumentUrl $window.root)){
    $target=SessionElement $window.root $Session
    if($target){$invoke=Pattern $target ([System.Windows.Automation.InvokePattern]::Pattern);if($invoke){$invoke.Invoke();Start-Sleep -Milliseconds 700;$window=WindowRoot}}
  }
  $transcript=@(Transcript $window.root)
  Reply ([ordered]@{ok=$true;url=(DocumentUrl $window.root);messages=@($transcript | Select-Object -First 24)})
}
if($Command -eq 'show'){
  $target=SessionElement $window.root $Session
  if(-not $target){Fail 'The desktop app did not uniquely match this chat' 'NOT_FOUND'}
  $invoke=Pattern $target ([System.Windows.Automation.InvokePattern]::Pattern); if(-not $invoke){Fail 'This chat cannot be opened through standard accessibility'}; $invoke.Invoke(); Reply ([ordered]@{ok=$true})
}
if($Command -eq 'new'){InvokeOne $window.root $cfg.new 'New chat'; Start-Sleep -Milliseconds 800; $window=WindowRoot; $url=DocumentUrl $window.root; Reply ([ordered]@{ok=$true;id=if($url){$url}else{"new-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"}})}
if($Command -eq 'stop'){InvokeOne $window.root $cfg.stop 'Stop'; Reply ([ordered]@{ok=$true;pending=$true})}
if($Command -eq 'send'){
  $prompt=if($InputBase64){[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($InputBase64))}else{''}
  if(-not $prompt){Fail 'Message cannot be empty' 'EMPTY'}
  if($Session -and $Session -ne 'current' -and $Session -ne (DocumentUrl $window.root)){
    $target=SessionElement $window.root $Session
    if($target){$invoke=Pattern $target ([System.Windows.Automation.InvokePattern]::Pattern);if($invoke){$invoke.Invoke();Start-Sleep -Milliseconds 700;$window=WindowRoot}}
  }
  $before=Snapshot $window.root; FillComposer $window $prompt; Start-Sleep -Milliseconds 200; $window=WindowRoot; InvokeOne $window.root $cfg.send 'Send'
  $started=$false; $deadline=(Get-Date).AddSeconds([int]$cfg.waitSeconds)
  do { Start-Sleep -Milliseconds 900; $window=WindowRoot; $stops=Find $window.root $cfg.stop; if($stops.Count -gt 0){$started=$true}; if($started -and $stops.Count -eq 0){break} } while((Get-Date) -lt $deadline)
  $after=Snapshot $window.root; $known=@{}; foreach($row in $before.items){$known[$row.name]=$true}
  $replyParts=New-Object System.Collections.Generic.List[string]
  foreach($row in $after.items){$name=[string]$row.name;if(-not $name -or $name -eq $prompt -or $known.ContainsKey($name)){continue};$skip=$false;foreach($pattern in @($cfg.replySkip)){if($name -match $pattern){$skip=$true;break}};if(-not $skip -and $row.role -in @('Text','Heading')){$replyParts.Add($name)}}
  $reply=($replyParts -join "`n").Trim()
  Reply ([ordered]@{ok=$true;completed=($started -and (Find $window.root $cfg.stop).Count -eq 0);reply=$reply;snapshot=$after})
}
