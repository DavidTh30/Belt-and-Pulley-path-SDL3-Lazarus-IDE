unit DemoScript;

{ สคริปต์แอนิเมชัน: ฉากเริ่มต้น + ลำดับคำสั่งการเคลื่อนไหว อ่าน/เขียนเป็นไฟล์ข้อความ

  รูปแบบไฟล์ (หนึ่งคำสั่งต่อบรรทัด, # = หมายเหตุ, ทศนิยมใช้จุด)
    node   <node> <x> <y> <r>               ตำแหน่ง/รัศมีเริ่มต้นของ pulley (ไม่ใส่ = ค่าตั้งต้น)
    line   <node> <x> <y> <seconds>          เลื่อนเป็นเส้นตรงแบบนุ่ม (ease in/out)
    move   <node> <x> <y> <seconds>          เลื่อนเป็นเส้นตรงความเร็วคงที่ (ได้จากการอัด)
    orbit  <node> <center> <turns> <seconds> หมุนรอบ pulley อื่น, turns บวก = ตามเข็มบนจอ
    radius <node> <r> <seconds>              เปลี่ยนรัศมี
    hold   <seconds>                         หยุดนิ่ง
  คำสั่งทำต่อกันตามลำดับ แต่ละคำสั่งเริ่มจากตำแหน่งที่คำสั่งก่อนหน้าทิ้งไว้

  ข้อมูลฉาก/belt (ไม่ใส่ = ค่าตั้งต้น)
    pulleys <count>                          จำนวน pulley
    belt thickness <t> color <r> <g> <b> speed <v> offset <f> [run <0/1>]
    wrap   <node> <side> <layer> <sweepDeg> [joint]   สภาพการพันของ belt ตอนเริ่ม (ตามลำดับทาง)
    paint  <from> <to> <color>               ช่วงที่ทาสีบนเนื้อ belt (สัดส่วน 0..1 ของความยาว)
    grid   show <0/1> snap <0/1> step <px> style <0..3> color <r> <g> <b>
    image  mode <fit|fill|stretch|center> opacity <0..100> [rotate <deg>] [scale <%>]
           [offset <dx> <dy>] path <ไฟล์ภาพ>       ภาพพื้นหลังของ View
    palette <r g b> x6                       สีพู่กันช่อง 1..6
    view   color <r> <g> <b>                 สีพื้นของ View }

{$mode objfpc}{$H+}

interface

uses
  Gfx;

type
  TPhaseKind = (pkLine, pkMove, pkOrbit, pkRadius, pkHold);

  TPhase = record
    kind: TPhaseKind;
    node, center: Integer;
    x, y, turns, r, dur: Single;
  end;

  { หนึ่งช่วงที่ belt พันอยู่ ณ ตอนเริ่ม }
  TStartWrap = record
    node, side, layer: Integer;
    sweep: Single;      // rad
    joint: Boolean;
  end;

const
  KIND_NAME: array[TPhaseKind] of string = ('line', 'move', 'orbit', 'radius', 'hold');
  MIN_DUR = 0.05;
  MAX_PULLEYS = 32;
  SWEEP_AUTO = -1000;                  // sweep ของ wrap ที่ให้คำนวณเอง (ไฟล์เขียนว่า auto)
  PAINT_N = 4096;                      // ความละเอียดของสีตามความยาว belt
  DEFAULT_BELT_COLOR: TRgb = (r: 234; g: 234; b: 228);
  DEFAULT_GRID_COLOR: TRgb = (r: 170; g: 170; b: 165);
  IMAGE_MODE_NAME: array[0..3] of string = ('fit', 'fill', 'stretch', 'center');
  DEFAULT_VIEW_COLOR: TRgb = (r: 252; g: 252; b: 250);
  DEFAULT_PALETTE: array[1..6] of TRgb = (
    (r: 215; g: 45; b: 35), (r: 235; g: 140; b: 20), (r: 225; g: 195; b: 20),
    (r: 40; g: 150; b: 70), (r: 35; g: 95; b: 200), (r: 22; g: 22; b: 22));

var
  Phases: array of TPhase;
  ScriptLen: Single = 0;               // ความยาวรวม (วินาที)
  StartX, StartY, StartR: array of Single;   // ฉากเริ่มต้นของเอกสาร
  StartWraps: array of TStartWrap;     // ว่าง = รูปทรง belt ตั้งต้น
  { belt ของเอกสาร }
  BeltThick: Single = 3;
  BeltColor: TRgb;
  BeltSpeedDoc: Single = 60;
  BeltOffset: Single = 0;
  BeltRunDoc: Boolean = False;         // belt วิ่งอยู่ตอนบันทึก
  PaintCells: array of Byte;           // PAINT_N ช่อง, 0 = ไม่มีสี
  { ตารางและภาพพื้นหลังของ View }
  GridOn: Boolean = True;
  GridSnap: Boolean = False;
  GridStep: Single = 45;
  GridStyle: Integer = 0;              // 0 เส้นประ, 1 เส้นทึบ, 2 จุด, 3 กากบาท
  GridColor: TRgb;
  ImagePath: string = '';
  ImageMode: Integer = 0;              // 0 fit, 1 fill, 2 stretch, 3 center
  ImageOpacity: Integer = 60;          // เปอร์เซ็นต์
  ImageAngle: Single = 0;              // หมุนภาพ (องศา ตามเข็มนาฬิกา)
  ImageScale: Single = 100;            // ขยายภาพ (%)
  ImageOffX: Single = 0;               // เลื่อนภาพ (px)
  ImageOffY: Single = 0;
  ViewColor: TRgb;                     // สีพื้นของ View
  PaintPalette: array[1..6] of TRgb;   // สีพู่กัน (ช่อง 0 = ยางลบ)

{ ตั้งจำนวน pulley และฉากตั้งต้น แล้วล้างสคริปต์ }
procedure InitScript(const dx, dy, dr: array of Single);
procedure ClearScript(empty: Boolean = False);

{ โหลดไฟล์; คืน '' ถ้าเรียบร้อย หรือรายการบรรทัดที่ข้าม; ถ้าอ่านไฟล์ไม่ได้จะ raise }
function LoadScriptFile(const FileName: string): string;
procedure SaveScriptFile(const FileName: string);

function NodeCount: Integer;
procedure SetNodeCount(n: Integer);
{ เพิ่ม/ลบ pulley ในฉากเริ่มต้น พร้อมแก้คำสั่งและสภาพการพันที่อ้างถึง }
procedure AddStartNode(x, y, r: Single);
procedure DeleteStartNode(k: Integer);
procedure Recalc;
function PhaseStart(i: Integer): Single;
function PhaseAt(t: Single): Integer;
procedure InsertPhase(idx: Integer; const ph: TPhase);
procedure DeletePhase(idx: Integer);
procedure SwapPhases(i, j: Integer);
procedure ClampPhase(var ph: TPhase);
function MakePhase(kind: TPhaseKind; node: Integer; a, b, c, dur: Single): TPhase;

{ ตำแหน่งและรัศมีของทุก pulley ที่เวลา t (เริ่มจากฉากเริ่มต้น) }
procedure ScriptPositions(t: Single; out px, py, pr: array of Single);

{ รวมคำสั่งจากการอัดตั้งแต่ index fromIdx ให้กระชับ }
procedure CompactFrom(fromIdx: Integer);

implementation

uses
  Classes, SysUtils, Math;

var
  DefX, DefY, DefR: array of Single;
  FS: TFormatSettings;

function NodeCount: Integer;
begin
  Result := Length(StartX);
end;

procedure SetNodeCount(n: Integer);
var
  i, old: Integer;
begin
  n := EnsureRange(n, 0, MAX_PULLEYS);
  old := Length(StartX);
  SetLength(StartX, n);
  SetLength(StartY, n);
  SetLength(StartR, n);
  for i := old to n - 1 do
    if i < Length(DefX) then
    begin
      StartX[i] := DefX[i];
      StartY[i] := DefY[i];
      StartR[i] := DefR[i];
    end
    else
    begin
      StartX[i] := 100 + (i mod 10) * 70;
      StartY[i] := 100 + (i div 10) * 70;
      StartR[i] := 30;
    end;
end;

procedure AddStartNode(x, y, r: Single);
var
  n: Integer;
begin
  n := Length(StartX);
  if n >= MAX_PULLEYS then Exit;
  SetLength(StartX, n + 1);
  SetLength(StartY, n + 1);
  SetLength(StartR, n + 1);
  StartX[n] := x;
  StartY[n] := y;
  StartR[n] := r;
end;

procedure DeleteStartNode(k: Integer);
var
  i, j: Integer;
begin
  if (k < 0) or (k >= Length(StartX)) then Exit;
  for i := k to High(StartX) - 1 do
  begin
    StartX[i] := StartX[i + 1];
    StartY[i] := StartY[i + 1];
    StartR[i] := StartR[i + 1];
  end;
  SetLength(StartX, Length(StartX) - 1);
  SetLength(StartY, Length(StartY) - 1);
  SetLength(StartR, Length(StartR) - 1);

  { สภาพการพัน: ตัดช่วงของ pulley นี้ออก เลื่อนหมายเลขที่เหลือ }
  j := 0;
  for i := 0 to High(StartWraps) do
    if StartWraps[i].node <> k then
    begin
      StartWraps[j] := StartWraps[i];
      if StartWraps[j].node > k then Dec(StartWraps[j].node);
      StartWraps[j].sweep := SWEEP_AUTO;     // เส้นเปลี่ยน ให้คำนวณส่วนโค้งใหม่
      Inc(j);
    end;
  if j < 2 then j := 0;
  SetLength(StartWraps, j);

  { คำสั่งแอนิเมชันที่ใช้ pulley นี้ถูกลบ ที่เหลือเลื่อนหมายเลข }
  i := 0;
  while i <= High(Phases) do
    if (Phases[i].node = k) or (Phases[i].center = k) then
      DeletePhase(i)
    else
    begin
      if Phases[i].node > k then Dec(Phases[i].node);
      if Phases[i].center > k then Dec(Phases[i].center);
      Inc(i);
    end;
  Recalc;
end;

procedure InitScript(const dx, dy, dr: array of Single);
var
  i: Integer;
begin
  SetLength(DefX, Length(dx));
  SetLength(DefY, Length(dx));
  SetLength(DefR, Length(dx));
  for i := 0 to High(dx) do
  begin
    DefX[i] := dx[i];
    DefY[i] := dy[i];
    DefR[i] := dr[i];
  end;
  ClearScript;
end;

procedure ClearScript(empty: Boolean);
var
  i: Integer;
begin
  SetLength(Phases, 0);
  if empty then
  begin
    { เอกสารว่าง: ไม่มี pulley และไม่มี belt }
    SetLength(StartX, 0);
    SetLength(StartY, 0);
    SetLength(StartR, 0);
  end
  else
  begin
    StartX := Copy(DefX);
    StartY := Copy(DefY);
    StartR := Copy(DefR);
  end;
  SetLength(StartWraps, 0);
  BeltThick := 3;
  BeltColor := DEFAULT_BELT_COLOR;
  BeltSpeedDoc := 60;
  BeltOffset := 0;
  BeltRunDoc := False;
  ImageAngle := 0;
  ImageScale := 100;
  ImageOffX := 0;
  ImageOffY := 0;
  SetLength(PaintCells, PAINT_N);
  FillChar(PaintCells[0], PAINT_N, 0);
  GridOn := True;
  GridSnap := False;
  GridStep := 45;
  GridStyle := 0;
  GridColor := DEFAULT_GRID_COLOR;
  ImagePath := '';
  ImageMode := 0;
  ImageOpacity := 60;
  ViewColor := DEFAULT_VIEW_COLOR;
  for i := 1 to 6 do
    PaintPalette[i] := DEFAULT_PALETTE[i];
  Recalc;
end;

procedure Recalc;
var
  i: Integer;
begin
  ScriptLen := 0;
  for i := 0 to High(Phases) do
    ScriptLen := ScriptLen + Phases[i].dur;
end;

function PhaseStart(i: Integer): Single;
var
  k: Integer;
begin
  Result := 0;
  for k := 0 to Min(i, Length(Phases)) - 1 do
    Result := Result + Phases[k].dur;
end;

function PhaseAt(t: Single): Integer;
var
  k: Integer;
  s: Single;
begin
  Result := -1;
  s := 0;
  for k := 0 to High(Phases) do
  begin
    s := s + Phases[k].dur;
    Result := k;
    if t < s then Exit;
  end;
end;

procedure ClampPhase(var ph: TPhase);
var
  n: Integer;
begin
  n := NodeCount;
  ph.dur := Max(MIN_DUR, ph.dur);
  if ph.kind <> pkHold then
    ph.node := EnsureRange(ph.node, 0, n - 1)
  else
    ph.node := -1;
  if ph.kind = pkOrbit then
  begin
    ph.center := EnsureRange(ph.center, 0, n - 1);
    if ph.center = ph.node then
      ph.center := (ph.node + 1) mod n;
  end
  else
    ph.center := -1;
  ph.r := EnsureRange(ph.r, 8, 150);
end;

function MakePhase(kind: TPhaseKind; node: Integer; a, b, c, dur: Single): TPhase;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.kind := kind;
  Result.node := node;
  Result.dur := dur;
  Result.r := 30;
  case kind of
    pkLine, pkMove: begin Result.x := a; Result.y := b; end;
    pkOrbit: begin Result.center := Round(a); Result.turns := b; end;
    pkRadius: Result.r := a;
  end;
  ClampPhase(Result);
end;

procedure InsertPhase(idx: Integer; const ph: TPhase);
var
  k: Integer;
begin
  idx := EnsureRange(idx, 0, Length(Phases));
  SetLength(Phases, Length(Phases) + 1);
  for k := High(Phases) downto idx + 1 do
    Phases[k] := Phases[k - 1];
  Phases[idx] := ph;
  Recalc;
end;

procedure DeletePhase(idx: Integer);
var
  k: Integer;
begin
  if (idx < 0) or (idx > High(Phases)) then Exit;
  for k := idx to High(Phases) - 1 do
    Phases[k] := Phases[k + 1];
  SetLength(Phases, Length(Phases) - 1);
  Recalc;
end;

procedure SwapPhases(i, j: Integer);
var
  t: TPhase;
begin
  if (i < 0) or (j < 0) or (i > High(Phases)) or (j > High(Phases)) then Exit;
  t := Phases[i];
  Phases[i] := Phases[j];
  Phases[j] := t;
end;

{ ---------- อ่าน/เขียนไฟล์ ---------- }

{ ทาช่วง [f0, f1) ของเนื้อ belt ด้วยสี c }
procedure PaintRange(f0, f1: Single; c: Integer);
var
  a, b, j: Integer;
begin
  if Length(PaintCells) <> PAINT_N then SetLength(PaintCells, PAINT_N);
  a := EnsureRange(Round(f0 * PAINT_N), 0, PAINT_N);
  b := EnsureRange(Round(f1 * PAINT_N), 0, PAINT_N);
  for j := a to b - 1 do
    PaintCells[j] := c;
end;

function ParseBelt(const w: TStringArray): Boolean;
var
  i, c1, c2, c3: Integer;
  v: Double;
  key: string;
begin
  Result := False;
  i := 1;
  while i <= High(w) do
  begin
    key := LowerCase(w[i]);
    if (key = 'color') and (i + 3 <= High(w)) then
    begin
      if not (TryStrToInt(w[i + 1], c1) and TryStrToInt(w[i + 2], c2) and TryStrToInt(w[i + 3], c3)) then Exit;
      BeltColor.r := EnsureRange(c1, 0, 255);
      BeltColor.g := EnsureRange(c2, 0, 255);
      BeltColor.b := EnsureRange(c3, 0, 255);
      Inc(i, 4);
    end
    else if (i + 1 <= High(w)) and TryStrToFloat(w[i + 1], v, FS) then
    begin
      if key = 'thickness' then BeltThick := EnsureRange(v, 1, 12)
      else if key = 'speed' then BeltSpeedDoc := EnsureRange(v, -400, 400)
      else if key = 'offset' then BeltOffset := v - Floor(v)
      else if key = 'run' then BeltRunDoc := v <> 0
      else Exit;
      Inc(i, 2);
    end
    else
      Exit;
  end;
  Result := True;
end;

function ParseGrid(const w: TStringArray): Boolean;
var
  i, c1, c2, c3: Integer;
  v: Double;
  key: string;
begin
  Result := False;
  i := 1;
  while i <= High(w) do
  begin
    key := LowerCase(w[i]);
    if (key = 'color') and (i + 3 <= High(w)) then
    begin
      if not (TryStrToInt(w[i + 1], c1) and TryStrToInt(w[i + 2], c2) and TryStrToInt(w[i + 3], c3)) then Exit;
      GridColor.r := EnsureRange(c1, 0, 255);
      GridColor.g := EnsureRange(c2, 0, 255);
      GridColor.b := EnsureRange(c3, 0, 255);
      Inc(i, 4);
    end
    else if (i + 1 <= High(w)) and TryStrToFloat(w[i + 1], v, FS) then
    begin
      if key = 'show' then GridOn := v <> 0
      else if key = 'snap' then GridSnap := v <> 0
      else if key = 'step' then GridStep := EnsureRange(v, 10, 200)
      else if key = 'style' then GridStyle := EnsureRange(Round(v), 0, 3)
      else Exit;
      Inc(i, 2);
    end
    else
      Exit;
  end;
  Result := True;
end;

{ image mode <m> opacity <n> path <ที่เหลือทั้งบรรทัด (มีช่องว่างได้)> }
function ParseImage(const w: TStringArray; const rawLine: string): Boolean;
var
  i, k, p: Integer;
  d, d2: Double;
  key: string;
begin
  Result := False;
  i := 1;
  while i <= High(w) do
  begin
    key := LowerCase(w[i]);
    if key = 'path' then
    begin
      p := Pos(' path ', LowerCase(rawLine));
      if p = 0 then Exit;
      ImagePath := Trim(Copy(rawLine, p + 6, MaxInt));
      Exit(ImagePath <> '');
    end;
    if i + 1 > High(w) then Exit;
    if key = 'mode' then
    begin
      ImageMode := -1;
      for k := 0 to 3 do
        if LowerCase(w[i + 1]) = IMAGE_MODE_NAME[k] then ImageMode := k;
      if ImageMode < 0 then
      begin
        ImageMode := 0;
        Exit;
      end;
    end
    else if key = 'opacity' then
    begin
      if not TryStrToInt(w[i + 1], k) then Exit;
      ImageOpacity := EnsureRange(k, 0, 100);
    end
    else if key = 'rotate' then
    begin
      if not TryStrToFloat(w[i + 1], d, FS) then Exit;
      ImageAngle := d - 360 * Floor(d / 360);
    end
    else if key = 'scale' then
    begin
      if not TryStrToFloat(w[i + 1], d, FS) then Exit;
      ImageScale := EnsureRange(d, 5, 1000);
    end
    else if key = 'offset' then
    begin
      if (i + 2 > High(w)) or not TryStrToFloat(w[i + 1], d, FS) or not TryStrToFloat(w[i + 2], d2, FS) then Exit;
      ImageOffX := d;
      ImageOffY := d2;
      Inc(i);                          // offset มี 2 ค่า
    end
    else
      Exit;
    Inc(i, 2);
  end;
  Result := True;
end;

function ParseScript(Lines: TStrings): string;
var
  i, p, node, center, n, k, node_, side_: Integer;
  s, cmd: string;
  w: TStringArray;
  x, y, r, turns, dur: Single;
  ok: Boolean;

  function Num(const t: string; out v: Single): Boolean;
  var
    d: Double;
  begin
    Result := TryStrToFloat(t, d, FS);
    v := d;
  end;

  function NodeOk(const t: string; out v: Integer): Boolean;
  begin
    Result := TryStrToInt(t, v) and (v >= 0) and (v < n);
  end;

begin
  Result := '';
  ClearScript;                 // ฉากตั้งต้น 9 pulley (ไฟล์อาจเปลี่ยนด้วยบรรทัด pulleys)
  n := NodeCount;

  for i := 0 to Lines.Count - 1 do
  begin
    s := Lines[i];
    p := Pos('#', s);
    if (p > 0) and (LowerCase(Copy(TrimLeft(s), 1, 6)) <> 'image ') then
      s := Copy(s, 1, p - 1);
    s := Trim(s);
    if s = '' then Continue;

    w := s.Split([' ', #9], TStringSplitOptions.ExcludeEmpty);
    cmd := LowerCase(w[0]);
    ok := False;
    if (cmd = 'pulleys') and (Length(w) = 2) then
    begin
      ok := TryStrToInt(w[1], k) and (k >= 0);
      if ok then
      begin
        if k > MAX_PULLEYS then
          Result := Result + Format('line %d: %d pulleys, only %d are used', [i + 1, k, MAX_PULLEYS]) + LineEnding;
        SetNodeCount(k);
        n := NodeCount;
      end;
    end
    else if cmd = 'belt' then
      ok := ParseBelt(w)
    else if cmd = 'grid' then
      ok := ParseGrid(w)
    else if (cmd = 'palette') and (Length(w) = 19) then
    begin
      ok := True;
      for k := 0 to 17 do
        if not TryStrToInt(w[k + 1], side_) or (side_ < 0) or (side_ > 255) then ok := False;
      if ok then
        for k := 0 to 5 do
        begin
          PaintPalette[k + 1].r := StrToInt(w[k * 3 + 1]);
          PaintPalette[k + 1].g := StrToInt(w[k * 3 + 2]);
          PaintPalette[k + 1].b := StrToInt(w[k * 3 + 3]);
        end;
    end
    else if (cmd = 'view') and (Length(w) = 5) and (LowerCase(w[1]) = 'color') then
    begin
      ok := TryStrToInt(w[2], k) and TryStrToInt(w[3], node_) and TryStrToInt(w[4], side_);
      if ok then
      begin
        ViewColor.r := EnsureRange(k, 0, 255);
        ViewColor.g := EnsureRange(node_, 0, 255);
        ViewColor.b := EnsureRange(side_, 0, 255);
      end;
    end
    else if cmd = 'image' then
      ok := ParseImage(w, Lines[i])
    else if (cmd = 'wrap') and (Length(w) in [5, 6]) then
    begin
      ok := NodeOk(w[1], node_) and TryStrToInt(w[2], side_) and (Abs(side_) = 1)
            and TryStrToInt(w[3], k) and (k >= 0)
            and ((LowerCase(w[4]) = 'auto') or Num(w[4], x))
            and ((Length(w) = 5) or (LowerCase(w[5]) = 'joint'));
      if ok then
      begin
        SetLength(StartWraps, Length(StartWraps) + 1);
        with StartWraps[High(StartWraps)] do
        begin
          node := node_;
          side := side_;
          layer := k;
          if LowerCase(w[4]) = 'auto' then sweep := SWEEP_AUTO else sweep := x * Pi / 180;
          joint := Length(w) = 6;
        end;
      end;
    end
    else if (cmd = 'paint') and (Length(w) = 4) then
    begin
      ok := Num(w[1], x) and Num(w[2], y) and TryStrToInt(w[3], k) and (k >= 0) and (k <= 255);
      if ok then
        PaintRange(x, y, k);
    end
    else if (cmd = 'node') and (Length(w) = 5) then
    begin
      ok := NodeOk(w[1], node) and Num(w[2], x) and Num(w[3], y) and Num(w[4], r) and (r > 0);
      if ok then
      begin
        StartX[node] := x;
        StartY[node] := y;
        StartR[node] := EnsureRange(r, 8, 150);
      end;
    end
    else if ((cmd = 'line') or (cmd = 'move')) and (Length(w) = 5) then
    begin
      ok := NodeOk(w[1], node) and Num(w[2], x) and Num(w[3], y) and Num(w[4], dur) and (dur > 0);
      if ok then
        if cmd = 'line' then
          InsertPhase(Length(Phases), MakePhase(pkLine, node, x, y, 0, dur))
        else
          InsertPhase(Length(Phases), MakePhase(pkMove, node, x, y, 0, dur));
    end
    else if (cmd = 'orbit') and (Length(w) = 5) then
    begin
      ok := NodeOk(w[1], node) and NodeOk(w[2], center) and (center <> node)
            and Num(w[3], turns) and Num(w[4], dur) and (dur > 0);
      if ok then
        InsertPhase(Length(Phases), MakePhase(pkOrbit, node, center, turns, 0, dur));
    end
    else if (cmd = 'radius') and (Length(w) = 4) then
    begin
      ok := NodeOk(w[1], node) and Num(w[2], r) and Num(w[3], dur) and (dur > 0);
      if ok then
        InsertPhase(Length(Phases), MakePhase(pkRadius, node, r, 0, 0, dur));
    end
    else if (cmd = 'hold') and (Length(w) = 2) then
    begin
      ok := Num(w[1], dur) and (dur > 0);
      if ok then
        InsertPhase(Length(Phases), MakePhase(pkHold, -1, 0, 0, 0, dur));
    end;

    if not ok then
      Result := Result + Format('line %d: %s', [i + 1, Trim(Lines[i])]) + LineEnding;
  end;
end;

function LoadScriptFile(const FileName: string): string;
var
  L: TStringList;
begin
  L := TStringList.Create;
  try
    L.LoadFromFile(FileName);
    Result := ParseScript(L);
  finally
    L.Free;
  end;
end;

function F(v: Single): string;
begin
  Result := FormatFloat('0.###', v, FS);
end;

procedure SaveScriptFile(const FileName: string);
var
  L: TStringList;
  i, j: Integer;
  t: string;
begin
  L := TStringList.Create;
  try
    L.Add('# Belt and Pulley Path - animation file');
    L.Add('# scene: pulleys, node, belt, wrap, paint   animation: line, move, orbit, radius, hold');
    L.Add('');
    L.Add(Format('pulleys %d', [NodeCount]));
    for i := 0 to NodeCount - 1 do
      L.Add(Format('node   %d %s %s %s', [i, F(StartX[i]), F(StartY[i]), F(StartR[i])]));
    L.Add('');
    L.Add(Format('belt thickness %s color %d %d %d speed %s offset %s run %d',
      [F(BeltThick), BeltColor.r, BeltColor.g, BeltColor.b, F(BeltSpeedDoc), FormatFloat('0.######', BeltOffset, FS),
       Ord(BeltRunDoc)]));
    for i := 0 to High(StartWraps) do
      with StartWraps[i] do
      begin
        if sweep <= SWEEP_AUTO + 1 then t := 'auto' else t := F(sweep * 180 / Pi);
        if joint then
          L.Add(Format('wrap   %d %d %d %s joint', [node, side, layer, t]))
        else
          L.Add(Format('wrap   %d %d %d %s', [node, side, layer, t]));
      end;
    L.Add(Format('grid show %d snap %d step %s style %d color %d %d %d',
      [Ord(GridOn), Ord(GridSnap), F(GridStep), GridStyle, GridColor.r, GridColor.g, GridColor.b]));
    if ImagePath <> '' then
      L.Add(Format('image mode %s opacity %d rotate %s scale %s offset %s %s path %s',
        [IMAGE_MODE_NAME[ImageMode], ImageOpacity, F(ImageAngle), F(ImageScale), F(ImageOffX), F(ImageOffY), ImagePath]));
    L.Add(Format('view color %d %d %d', [ViewColor.r, ViewColor.g, ViewColor.b]));
    t := 'palette';
    for j := 1 to 6 do
      t := t + Format(' %d %d %d', [PaintPalette[j].r, PaintPalette[j].g, PaintPalette[j].b]);
    L.Add(t);
    { สี: เก็บเป็นช่วงต่อเนื่องที่สีเดียวกัน }
    i := 0;
    while i < Length(PaintCells) do
    begin
      if PaintCells[i] = 0 then
      begin
        Inc(i);
        Continue;
      end;
      j := i + 1;
      while (j < Length(PaintCells)) and (PaintCells[j] = PaintCells[i]) do Inc(j);
      L.Add(Format('paint  %s %s %d', [FormatFloat('0.######', i / PAINT_N, FS),
        FormatFloat('0.######', j / PAINT_N, FS), PaintCells[i]]));
      i := j;
    end;
    L.Add('');
    for i := 0 to High(Phases) do
      with Phases[i] do
        case kind of
          pkLine:   L.Add(Format('line   %d %s %s %s', [node, F(x), F(y), F(dur)]));
          pkMove:   L.Add(Format('move   %d %s %s %s', [node, F(x), F(y), F(dur)]));
          pkOrbit:  L.Add(Format('orbit  %d %d %s %s', [node, center, F(turns), F(dur)]));
          pkRadius: L.Add(Format('radius %d %s %s', [node, F(r), F(dur)]));
          pkHold:   L.Add(Format('hold   %s', [F(dur)]));
        end;
    L.SaveToFile(FileName);
  finally
    L.Free;
  end;
end;

{ ---------- คำนวณตำแหน่ง ---------- }

function SmoothStep(u: Single): Single;
begin
  u := EnsureRange(u, 0, 1);
  Result := u * u * (3 - 2 * u);
end;

procedure ScriptPositions(t: Single; out px, py, pr: array of Single);
var
  i, n: Integer;
  start, u, cx, cy, a0, rad, a: Single;
begin
  for i := 0 to Min(High(px), High(StartX)) do
  begin
    px[i] := StartX[i];
    py[i] := StartY[i];
    pr[i] := StartR[i];
  end;
  start := 0;
  for i := 0 to High(Phases) do
  begin
    if t <= start then Break;
    u := EnsureRange((t - start) / Phases[i].dur, 0, 1);
    n := Phases[i].node;
    case Phases[i].kind of
      pkLine, pkMove:
        begin
          if Phases[i].kind = pkLine then u := SmoothStep(u);
          px[n] := px[n] + (Phases[i].x - px[n]) * u;
          py[n] := py[n] + (Phases[i].y - py[n]) * u;
        end;
      pkOrbit:
        begin
          u := SmoothStep(u);
          cx := px[Phases[i].center];
          cy := py[Phases[i].center];
          a0 := ArcTan2(py[n] - cy, px[n] - cx);
          rad := Hypot(px[n] - cx, py[n] - cy);
          a := a0 + Phases[i].turns * 2 * Pi * u;
          px[n] := cx + rad * Cos(a);
          py[n] := cy + rad * Sin(a);
        end;
      pkRadius:
        pr[n] := pr[n] + (Phases[i].r - pr[n]) * u;
    end;
    start := start + Phases[i].dur;
  end;
end;

{ ---------- รวมคำสั่งจากการอัด ---------- }

procedure CompactFrom(fromIdx: Integer);
const
  TOL_POS = 1.5;
  TOL_R = 0.5;
var
  i: Integer;
  a, b: TPhase;
  f, ex, ey, er, bx0, by0, br0: Single;
  merged: Boolean;
  px, py, pr: array of Single;
begin
  SetLength(px, NodeCount);
  SetLength(py, NodeCount);
  SetLength(pr, NodeCount);
  i := Max(0, fromIdx);
  while i < High(Phases) do
  begin
    a := Phases[i];
    b := Phases[i + 1];
    merged := False;
    if (a.kind = pkHold) and (b.kind = pkHold) then
    begin
      Phases[i].dur := a.dur + b.dur;
      merged := True;
    end
    else if (a.kind = pkMove) and (b.kind = pkMove) and (a.node = b.node) then
    begin
      { จุดกลาง (ปลาย a) ต้องอยู่บนเส้นตรงความเร็วคงที่จากต้น a ถึงปลาย b }
      ScriptPositions(PhaseStart(i), px, py, pr);
      bx0 := px[a.node];
      by0 := py[a.node];
      f := a.dur / (a.dur + b.dur);
      ex := bx0 + (b.x - bx0) * f;
      ey := by0 + (b.y - by0) * f;
      if Hypot(ex - a.x, ey - a.y) <= TOL_POS then
      begin
        Phases[i].x := b.x;
        Phases[i].y := b.y;
        Phases[i].dur := a.dur + b.dur;
        merged := True;
      end;
    end
    else if (a.kind = pkRadius) and (b.kind = pkRadius) and (a.node = b.node) then
    begin
      ScriptPositions(PhaseStart(i), px, py, pr);
      br0 := pr[a.node];
      f := a.dur / (a.dur + b.dur);
      er := br0 + (b.r - br0) * f;
      if Abs(er - a.r) <= TOL_R then
      begin
        Phases[i].r := b.r;
        Phases[i].dur := a.dur + b.dur;
        merged := True;
      end;
    end;
    if merged then
      DeletePhase(i + 1)
    else
      Inc(i);
  end;
  Recalc;
end;

initialization
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  FS.ThousandSeparator := #0;
end.
