program BeltPulley;

{ Belt and Pulley Path
  Lazarus / Free Pascal + SDL3 (sechshelme binding: SDL3_package)
  ต้องใช้ SDL 3.2 ขึ้นไป และวาง SDL3.dll ไว้ข้าง ๆ ไฟล์ exe

  belt ทำตัวเหมือนยางยืด: เมื่อ pulley ตัวไหนดันเข้ามาในเส้น belt จะพันรอบมันให้เอง
  และเมื่อดึงออกจนส่วนโค้งเหลือศูนย์ belt จะคลายออก
  พันซ้ำ pulley เดิมได้หลายรอบ แต่ละรอบวางซ้อนกันห่างเท่าความหนา belt (BeltT)

  Units: Gfx (วาดพื้นฐาน), DemoScript (สคริปต์/ไฟล์แอนิเมชัน), AnimPanel (เมนู + แผง ANIMATION)

  Controls
    Left drag  : ย้าย pulley (หยุดการเล่น)
    Wheel      : ปรับรัศมี pulley ใต้เมาส์ / ปรับค่าในรายการคำสั่ง (Shift = x10)
    Space      : เล่น/หยุดชั่วคราว
    R          : กลับไปจุดเริ่ม (STOP)
    D          : สลับ VIEW DEBUG / OUTLINE
    Del, Up/Dn : ลบ/เลือกคำสั่งในรายการ
    Ctrl+N/O/S : New / Open / Save   (Ctrl+Shift+S = Save As)
    Ctrl+E     : Export Road (เส้นทาง belt เป็น JSON/CSV สำหรับสร้างถนนในเกม)
    B          : belt วิ่ง/หยุด
    P          : เครื่องมือทาสี (ลากซ้าย = ทา, ลากขวา = ลบ)
    Esc        : ออก (ถามก่อนถ้ายังไม่บันทึก)

  การอัด: กด REC แล้วลาก pulley; ตำแหน่งถูกเก็บเป็นคำสั่ง move/radius/hold ต่อท้ายสคริปต์
  กด STOP หรือ REC อีกครั้งเพื่อจบ }

{$mode objfpc}{$H+}
{$APPTYPE GUI}

uses
  SDL3, SDL3_image, Classes, SysUtils, Math, Gfx, DemoScript, AnimPanel;

const
  WIN_W = 1280;
  WIN_H = AP_Y + AP_H + 20;   // เมนู + แผง BELT + ฉาก (714) + แผง ANIMATION
  SCENE_Y = SCENE_TOP;         // ฉากเดิมทั้งหมดเลื่อนลงใต้แผง BELT
  SCENE_H = 714;
  REC_SAMPLE = 0.1;           // อัดตำแหน่งทุก ๆ กี่วินาที

  DBG_X = 20;  DBG_Y = 20;  DBG_W = 833; DBG_H = 673;   // แผง DEBUG
  REN_X = 893; REN_Y = 20;  REN_W = 367; REN_H = 316;   // แผง RENDER
  TOP_X = 893; TOP_Y = 377; TOP_W = 367; TOP_H = 200;   // แผง Topology (แผง PULLEY อยู่ใต้)

  REN_SCALE = 0.4;            // ย่อจากแผง DEBUG ลงแผง RENDER
  REN_OX = 14;
  REN_OY = 28;

  GRID = 45;
  TICKS = 64;                 // ขีดบอกการเคลื่อนที่บน belt
  DEF_COUNT = 9;              // จำนวน pulley ของฉากตั้งต้น (demo)
  MAX_NODES = MAX_PULLEYS;    // จำนวน pulley สูงสุด
  MAX_PATH = 1024;
  MAX_STEP = 1.5;             // ระยะเลื่อนสูงสุดต่อ sub-step (กัน pulley กระโดดข้ามเส้น)
  SPLIT_EPS = 0.15;           // พันเกินหนึ่งรอบเกินนี้ (rad) ถึงจะแยกเป็นชั้นใหม่
  REL_EPS = 1e-3;             // ส่วนโค้งติดลบเกินนี้ = คลายออก
  INS_TOL = 0.3;              // ต้องกินเข้าไปในเส้นเกินนี้ถึงจะพัน

type
  TNode = record
    x, y, r: Single;
  end;

  { หนึ่งช่วงของ belt ที่พันอยู่บน pulley
    s = -1 นูน / +1 เว้า (ใช้เป็นเครื่องหมายของรัศมี)
    phiIn/phiOut เก็บแบบไม่ wrap เพื่อให้รู้ทิศที่มุมเปลี่ยนอย่างต่อเนื่อง }
  TElem = record
    node, s: Integer;
    layer: Single;   // ชั้นปัจจุบัน (ค่อย ๆ เลื่อนเข้าหาลำดับจริง)
    ord: Integer;    // ลำดับการพัน: พันทีหลัง = อยู่ชั้นนอก
    phiIn, phiOut: Single;
    joint: Boolean;  // ต่อกับช่วงถัดไปบน pulley เดียวกันแบบขึ้นชั้น (พันเกินหนึ่งรอบ)
  end;

const
  INIT_NODES: array[0..DEF_COUNT - 1] of TNode = (
    (x: 538; y: 181; r: 60),   // 0
    (x: 727; y: 580; r: 33),   // 1
    (x: 468; y: 316; r: 30),   // 2
    (x: 407; y: 382; r: 37),   // 3
    (x: 390; y: 465; r: 45),   // 4
    (x: 257; y: 524; r: 28),   // 5
    (x: 373; y: 203; r: 24),   // 6
    (x: 276; y: 181; r: 60),   // 7
    (x: 175; y: 181; r: 60));  // 8
  INIT_SIDE: array[0..DEF_COUNT - 1] of Integer = (-1, -1, 1, -1, 1, -1, 1, -1, -1);

var
  Win: PSDL_Window;

  Nodes: array[0..MAX_NODES - 1] of TNode;
  NodeCnt: Integer = 0;         // จำนวน pulley ตอนนี้
  SelNode: Integer = -1;        // pulley ที่เลือกในแผง PULLEY
  NeedCapture: Boolean = False; // แก้ฉากแล้ว (ใช้เป็นฉากเริ่มต้นถ้ายังไม่มีแอนิเมชัน)
  Path: array[0..MAX_PATH - 1] of TElem;
  TanOK: array[0..MAX_PATH - 1] of Boolean;
  PathN: Integer = 0;
  OrdCounter: Integer = 0;

  Poly, RPoly: TPtArr;
  PolyN: Integer = 0;

  Mode: (mIdle, mPlay, mPaused, mRecord) = mPlay;
  LoopOn: Boolean = True;
  DemoT: Single = 0;
  DemoDir: Integer = 1;
  DemoWait: Single = 0;

  DragIdx: Integer = -1;
  DragDX, DragDY: Single;
  MouseX, MouseY: Single;
  ShowDebug: Boolean = True;

  Running: Boolean = True;

  { belt: ความหนา, การวิ่ง, สี }
  BeltT: Single = 3;            // ความหนาปัจจุบัน (ค่อย ๆ เลื่อนเข้าหาเป้า)
  BeltTTarget: Single = 3;
  BeltRun: Boolean = False;
  BeltSpeed: Single = 60;       // px/s, ติดลบ = วิ่งกลับทาง
  OffF: Single = 0;             // เนื้อ belt เลื่อนไปแล้วกี่ส่วนของความยาว (0..1)
  PolyS: array of Single;       // ระยะสะสมตามแนว belt ของแต่ละจุดใน Poly
  BeltLen: Single = 0;
  PulleyAng: array[0..MAX_NODES - 1] of Single;
  PaintOn: Boolean = False;
  PaintColor: Integer = 1;
  BrushR: Single = 8;
  Painting: Integer = -1;       // สีที่กำลังทา (-1 = ไม่ได้ทา)
  DocFile: string = '';
  Modified: Boolean = False;

  { การอัด }
  RecFrom: Integer = 0;
  RecAcc: Single = 0;
  RecHold: Single = 0;
  RecPX, RecPY, RecPR: array[0..MAX_NODES - 1] of Single;

  { ผลจากกล่องเลือกไฟล์ (callback อาจมาจาก thread อื่น จึงเก็บในบัฟเฟอร์ตายตัว) }
  DlgResult: LongInt = 0;       // 1 = open, 2 = save
  DlgBusy: Boolean = False;
  DlgPath: array[0..2047] of AnsiChar;
  DlgFilters: array[0..1] of TSDL_DialogFileFilter;
  DlgDir: string;
  ImgFilters: array[0..1] of TSDL_DialogFileFilter;

  { ภาพพื้นหลังของ View }
  BgTex: PSDL_Texture = nil;
  BgW: Single = 0;
  BgH: Single = 0;
  BgMissing: Boolean = False;
  { ลากภาพพื้นหลัง (โหมด MOVE) }
  ImgDrag: Boolean = False;
  ImgDragX0: Single = 0;
  ImgDragY0: Single = 0;
  ImgOff0X: Single = 0;
  ImgOff0Y: Single = 0;
  RoadFilters: array[0..1] of TSDL_DialogFileFilter;
  PngFilters: array[0..0] of TSDL_DialogFileFilter;


{ ================= math helpers ================= }

function WrapAngle(a: Single): Single;   // [0, 2pi)
begin
  Result := a - 2 * Pi * Floor(a / (2 * Pi));
  if Result >= 2 * Pi - 1e-6 then
    Result := 0;
end;

function WrapPi(a: Single): Single;      // (-pi, pi]
begin
  Result := a - 2 * Pi * Round(a / (2 * Pi));
end;

function Unwrap(old, a: Single): Single;
begin
  Result := old + WrapPi(a - old);
end;

{ ================= belt geometry ================= }

function RadEff(const e: TElem): Single;
begin
  { เส้นกลางของ belt อยู่เหนือผิว pulley ครึ่งความหนา แต่ละชั้นห่างกันเท่าความหนา }
  Result := Nodes[e.node].r + BeltT * (e.layer + 0.5);
end;

function Sweep(const e: TElem): Single;
begin
  Result := e.s * (e.phiIn - e.phiOut);
end;

{ เส้นสัมผัสระหว่างวง A กับ B ด้วยรัศมีมีเครื่องหมาย
  จุดสัมผัส Pa = Ca + Ra*n, Pb = Cb + Rb*n และ n·(Cb-Ca) = Ra - Rb
  Ra, Rb เครื่องหมายเดียวกัน = outer tangent, ต่างกัน = cross tangent }
procedure TangentRaw(ax, ay, Ra, bx, by, Rb: Single; out n, pa, pb: TPt; out ok: Boolean);
var
  dx, dy, L, ux, uy, ca, sn: Single;
begin
  dx := bx - ax;
  dy := by - ay;
  L := Sqrt(dx * dx + dy * dy);
  if L < 1e-3 then
  begin
    n := Pt(0, 1);
    ok := False;
  end
  else
  begin
    ux := dx / L;
    uy := dy / L;
    ca := (Ra - Rb) / L;
    ok := Abs(ca) <= 1;
    ca := EnsureRange(ca, -1, 1);
    sn := Sqrt(1 - ca * ca);
    n.x := ca * ux - sn * uy;
    n.y := ca * uy + sn * ux;
  end;
  pa := Pt(ax + Ra * n.x, ay + Ra * n.y);
  pb := Pt(bx + Rb * n.x, by + Rb * n.y);
end;

procedure TangentElem(const A, B: TElem; out n, pa, pb: TPt; out ok: Boolean);
begin
  TangentRaw(Nodes[A.node].x, Nodes[A.node].y, A.s * RadEff(A),
             Nodes[B.node].x, Nodes[B.node].y, B.s * RadEff(B), n, pa, pb, ok);
end;

function ArcPoint(const e: TElem; t: Single): TPt;
var
  phi, rr: Single;
begin
  phi := e.phiIn + (e.phiOut - e.phiIn) * t;
  rr := e.s * RadEff(e);
  Result.x := Nodes[e.node].x + rr * Cos(phi);
  Result.y := Nodes[e.node].y + rr * Sin(phi);
end;

{ ================= belt topology ================= }

procedure RemoveAt(i: Integer);
var
  k: Integer;
begin
  for k := i to PathN - 2 do
    Path[k] := Path[k + 1];
  Dec(PathN);
end;

procedure InsertAt(i: Integer; const e: TElem);
var
  k: Integer;
begin
  if PathN >= MAX_PATH then Exit;
  for k := PathN downto i + 1 do
    Path[k] := Path[k - 1];
  Path[i] := e;
  Inc(PathN);
end;

{ อัปเดตมุมเข้า/ออกทุกช่วงแบบต่อเนื่อง (unwrap) จากเส้นสัมผัสปัจจุบัน }
procedure RecomputeAngles;
var
  c, q: Integer;
  n, pa, pb: TPt;
  ok: Boolean;
  a: Single;
begin
  for c := 0 to PathN - 1 do
  begin
    q := (c + 1) mod PathN;
    if Path[c].joint then
    begin
      { ครบหนึ่งรอบพอดีแล้วขึ้นชั้นถัดไปที่มุมเดิม }
      Path[c].phiOut := Path[c].phiIn - Path[c].s * 2 * Pi;
      Path[q].phiIn := Path[c].phiOut;
      TanOK[c] := True;
      Continue;
    end;
    TangentElem(Path[c], Path[q], n, pa, pb, ok);
    a := ArcTan2(n.y, n.x);
    Path[c].phiOut := Unwrap(Path[c].phiOut, a);
    Path[q].phiIn := Unwrap(Path[q].phiIn, a);
    TanOK[c] := ok;
  end;
end;

{ belt ที่พัน pulley เดียวเกินหนึ่งรอบต้องทับตัวเองออกไปด้านนอก
  แยกเป็นรอบเต็มด้านใน + ส่วนที่เหลือเป็นชั้นใหม่ (ชั้นจะเลื่อนออกไปอย่างนุ่มนวล) }
procedure SplitTurns;
var
  c: Integer;
  e: TElem;
begin
  c := 0;
  while (c < PathN) and (PathN < MAX_PATH - 1) do
  begin
    if (not Path[c].joint) and (Sweep(Path[c]) > 2 * Pi + SPLIT_EPS) then
    begin
      e := Path[c];
      e.phiIn := Path[c].phiIn - Path[c].s * 2 * Pi;
      e.ord := OrdCounter;
      Inc(OrdCounter);
      Path[c].phiOut := e.phiIn;
      Path[c].joint := True;
      InsertAt(c + 1, e);
    end;
    Inc(c);
  end;
end;

{ ตั้งมุมใหม่หมด ส่วนโค้งทุกช่วงอยู่ใน [0, 2pi) }
procedure InitAngles;
var
  c, q: Integer;
  n, pa, pb: TPt;
  ok: Boolean;
  a: Single;
begin
  for c := 0 to PathN - 1 do
  begin
    q := (c + 1) mod PathN;
    TangentElem(Path[c], Path[q], n, pa, pb, ok);
    a := ArcTan2(n.y, n.x);
    Path[c].phiOut := a;
    Path[q].phiIn := a;
    TanOK[c] := ok;
  end;
  for c := 0 to PathN - 1 do
    with Path[c] do
      phiOut := phiIn - s * WrapAngle(s * (phiIn - phiOut));
end;

{ จำนวนรอบที่ belt พัน pulley k อยู่แล้ว = ชั้นของรอบใหม่ (วางไว้นอกสุดเสมอ) }
function WrapCount(k: Integer): Integer;
var
  c: Integer;
begin
  Result := 0;
  for c := 0 to PathN - 1 do
    if Path[c].node = k then
      Inc(Result);
end;

{ รัศมีผิวนอกสุดของ pulley k = ชั้นนอกสุดของ belt ที่พันอยู่ (ถ้าไม่มีก็คือตัว pulley) }
function OuterRad(k: Integer): Single;
var
  c: Integer;
  m: Single;
begin
  m := 0;
  for c := 0 to PathN - 1 do
    if (Path[c].node = k) and (Path[c].layer > m) then
      m := Path[c].layer;
  Result := Nodes[k].r + m * BeltT;
end;

{ ชั้นเป้าหมายของแต่ละรอบ = จำนวนรอบบน pulley เดียวกันที่พันมาก่อน
  เมื่อรอบด้านในคลายออก รอบด้านนอกจะค่อย ๆ ยุบเข้าไปแทน ไม่กระโดด }
procedure SettleLayers;
const
  RATE = 0.04;
var
  c, d, rank: Integer;
begin
  for c := 0 to PathN - 1 do
  begin
    rank := 0;
    for d := 0 to PathN - 1 do
      if (Path[d].node = Path[c].node) and (Path[d].ord < Path[c].ord) then
        Inc(rank);
    Path[c].layer := Path[c].layer + EnsureRange(rank - Path[c].layer, -RATE, RATE);
  end;
end;

{ ช่วงที่ติดกันเป็น pulley เดียวกัน (เกิดหลังคลายตัวกลางออก) รวมเป็นช่วงเดียว }
procedure FixMerges;
var
  c, q, keep: Integer;
  merged: Boolean;
begin
  repeat
    merged := False;
    if PathN <= 2 then Exit;
    for c := 0 to PathN - 1 do
    begin
      q := (c + 1) mod PathN;
      if (Path[c].node = Path[q].node) and not Path[c].joint then
      begin
        Path[c].phiOut := Path[q].phiOut;
        Path[c].joint := Path[q].joint;
        Path[c].layer := Min(Path[c].layer, Path[q].layer);
        Path[c].ord := Min(Path[c].ord, Path[q].ord);
        keep := c;
        if q < c then Dec(keep);
        RemoveAt(q);
        with Path[keep] do
          while Sweep(Path[keep]) < 0 do
            phiOut := phiOut - s * 2 * Pi;
        merged := True;
        Break;
      end;
    end;
  until not merged;
end;

{ คลาย: ช่วงไหนส่วนโค้งติดลบ = belt ไม่ได้แตะ pulley แล้ว เอาออก }
function ReleasePass: Boolean;
var
  c, guard: Integer;
  changed: Boolean;
begin
  Result := False;
  guard := 0;
  repeat
    changed := False;
    RecomputeAngles;
    if PathN > 2 then
      for c := 0 to PathN - 1 do
        if Sweep(Path[c]) < -REL_EPS then
        begin
          Path[(c + PathN - 1) mod PathN].joint := Path[c].joint;
          RemoveAt(c);
          FixMerges;
          RecomputeAngles;
          changed := True;
          Result := True;
          Break;
        end;
    Inc(guard);
  until (not changed) or (guard > 64);
end;

{ พัน: pulley ที่กินเข้าไปในเส้นตรงช่วงไหน แทรกเข้าไปในช่วงนั้น
  ด้านที่พันคือด้านที่มันดันเข้ามา }
function InsertPass: Boolean;
var
  c, q, k, lay, bestK, bestS, bestL, guard: Integer;
  n, pa, pb, n2, p1, p2: TPt;
  ok, ok1, ok2, found: Boolean;
  dx, dy, L2, t, h, rr, bestT, a1, a2, sw: Single;
  e: TElem;
begin
  Result := False;
  guard := 0;
  repeat
    found := False;
    for c := 0 to PathN - 1 do
    begin
      q := (c + 1) mod PathN;
      if Path[c].joint then Continue;
      TangentElem(Path[c], Path[q], n, pa, pb, ok);
      if not ok then Continue;
      dx := pb.x - pa.x;
      dy := pb.y - pa.y;
      L2 := dx * dx + dy * dy;
      if L2 < 1e-4 then Continue;

      bestK := -1; bestS := 0; bestL := 0; bestT := 2;
      for k := 0 to NodeCnt - 1 do
      begin
        if (k = Path[c].node) or (k = Path[q].node) then Continue;
        t := ((Nodes[k].x - pa.x) * dx + (Nodes[k].y - pa.y) * dy) / L2;
        if (t <= 0) or (t >= 1) or (t >= bestT) then Continue;
        { ตรวจการชนกับผิวนอกสุด (belt ที่พันอยู่แล้ว) ไม่ต้องรอให้แตะตัว pulley
          แล้ววาง belt รอบใหม่ไว้ชั้นถัดออกไป }
        h := (Nodes[k].x - pa.x) * n.x + (Nodes[k].y - pa.y) * n.y;
        if Abs(h) >= OuterRad(k) + BeltT / 2 - INS_TOL then Continue;
        lay := WrapCount(k);
        rr := Nodes[k].r + BeltT * (lay + 0.5);
        if h < 0 then e.s := 1 else e.s := -1;
        TangentRaw(Nodes[Path[c].node].x, Nodes[Path[c].node].y, Path[c].s * RadEff(Path[c]),
                   Nodes[k].x, Nodes[k].y, e.s * rr, n2, p1, p2, ok1);
        TangentRaw(Nodes[k].x, Nodes[k].y, e.s * rr,
                   Nodes[Path[q].node].x, Nodes[Path[q].node].y, Path[q].s * RadEff(Path[q]), n2, p1, p2, ok2);
        { ยอมพันแม้ pulley ซ้อนทับกันชั่วคราว (เส้นสัมผัสยังไม่มี) ไม่งั้น belt จะหลุดผ่านไป
          แล้วไปพันทับตัวเองบน pulley ปลายเส้นแทน }
        bestT := t; bestK := k; bestS := e.s; bestL := lay;
      end;

      if bestK >= 0 then
      begin
        e.node := bestK;
        e.s := bestS;
        e.layer := bestL;
        e.ord := OrdCounter;
        e.joint := False;
        Inc(OrdCounter);
        TangentElem(Path[c], e, n2, p1, p2, ok1);
        a1 := ArcTan2(n2.y, n2.x);
        TangentElem(e, Path[q], n2, p1, p2, ok2);
        a2 := ArcTan2(n2.y, n2.x);
        sw := WrapAngle(e.s * (a1 - a2));
        if sw > Pi then Continue;     // ไม่ควรเกิดตอนเพิ่งแตะเส้น
        e.phiIn := a1;
        e.phiOut := a1 - e.s * sw;
        InsertAt(c + 1, e);
        RecomputeAngles;
        found := True;
        Result := True;
        Break;
      end;
    end;
    Inc(guard);
  until (not found) or (guard > 32) or (PathN >= MAX_PATH - 1);
end;

procedure SimStep;
begin
  SettleLayers;
  ReleasePass;
  if InsertPass then
    ReleasePass;
  SplitTurns;
  RecomputeAngles;
end;

{ สร้าง belt ตามสภาพการพันที่บันทึกไว้ในเอกสาร (ถ้ามี) }
function ResetPathFromWraps: Boolean;
var
  i, k, maxL: Integer;
begin
  Result := Length(StartWraps) >= 2;
  if not Result then Exit;
  for i := 0 to High(StartWraps) do
    if StartWraps[i].node >= NodeCnt then Exit(False);
  PathN := 0;
  maxL := 0;
  for i := 0 to High(StartWraps) do
  begin
    if PathN >= MAX_PATH - 1 then Break;
    Path[PathN].node := StartWraps[i].node;
    Path[PathN].s := StartWraps[i].side;
    Path[PathN].layer := StartWraps[i].layer;
    Path[PathN].ord := StartWraps[i].layer * MAX_PATH + i;   // ลำดับชั้นเดิม
    Path[PathN].joint := StartWraps[i].joint;
    maxL := Max(maxL, StartWraps[i].layer);
    Inc(PathN);
  end;
  OrdCounter := (maxL + 1) * MAX_PATH;
  InitAngles;
  RecomputeAngles;
  { ส่วนโค้งที่ได้อยู่ใน [0, 2pi) เติมรอบให้ตรงกับที่บันทึกไว้ }
  for i := 0 to PathN - 1 do
    if not Path[i].joint and (StartWraps[i].sweep > SWEEP_AUTO + 1) then
    begin
      k := Round((StartWraps[i].sweep - Sweep(Path[i])) / (2 * Pi));
      Path[i].phiOut := Path[i].phiOut - Path[i].s * 2 * Pi * k;
    end;
  RecomputeAngles;
end;

procedure ResetPath;
var
  i: Integer;
begin
  if ResetPathFromWraps then Exit;
  PathN := 0;
  if NodeCnt = DEF_COUNT then
  begin
    { ฉากตั้งต้น: รูปทรง belt แบบใน GIF }
    for i := 0 to DEF_COUNT - 1 do
    begin
      Path[PathN].node := i;
      Path[PathN].s := INIT_SIDE[i];
      Path[PathN].layer := 0;
      Path[PathN].ord := i;
      Path[PathN].joint := False;
      Inc(PathN);
    end;
  end
  else if NodeCnt >= 2 then
  begin
    { อย่างอื่น: belt คล้อง pulley 0 กับ 1 }
    for i := 0 to 1 do
    begin
      Path[i].node := i;
      Path[i].s := -1;
      Path[i].layer := 0;
      Path[i].ord := i;
      Path[i].joint := False;
    end;
    PathN := 2;
  end;
  OrdCounter := Max(PathN, 2);
  InitAngles;
end;

{ ตั้งฉากเริ่มต้นของเอกสาร = ตำแหน่ง/รัศมี pulley และสภาพการพันของ belt ตอนนี้ }
procedure CaptureStart;
var
  i: Integer;
begin
  SetNodeCount(NodeCnt);
  for i := 0 to NodeCnt - 1 do
  begin
    StartX[i] := Nodes[i].x;
    StartY[i] := Nodes[i].y;
    StartR[i] := Nodes[i].r;
  end;
  SetLength(StartWraps, PathN);
  for i := 0 to PathN - 1 do
  begin
    StartWraps[i].node := Path[i].node;
    StartWraps[i].side := Path[i].s;
    StartWraps[i].layer := Round(Path[i].layer);
    StartWraps[i].sweep := Sweep(Path[i]);
    StartWraps[i].joint := Path[i].joint;
  end;
end;

procedure ResetAll;
var
  i: Integer;
begin
  NodeCnt := Min(NodeCount, MAX_NODES);
  if SelNode >= NodeCnt then SelNode := -1;
  for i := 0 to NodeCnt - 1 do
  begin
    Nodes[i].x := StartX[i];
    Nodes[i].y := StartY[i];
    Nodes[i].r := StartR[i];
  end;
  ResetPath;
  DemoT := 0;
  DemoDir := 1;
  DemoWait := 0.8;
  DragIdx := -1;
end;

{ เลื่อน pulley ไปยังเป้าหมายทีละนิด แล้วจำลอง belt ทุก sub-step }
procedure MoveNodesTo(const tx, ty, tr: array of Single);
var
  i, k, steps: Integer;
  d: Single;
  sx, sy, sr: array[0..MAX_NODES - 1] of Single;
begin
  FillChar(sx, SizeOf(sx), 0); FillChar(sy, SizeOf(sy), 0); FillChar(sr, SizeOf(sr), 0);
  d := 0;
  for i := 0 to NodeCnt - 1 do
  begin
    d := Max(d, Hypot(tx[i] - Nodes[i].x, ty[i] - Nodes[i].y));
    d := Max(d, Abs(tr[i] - Nodes[i].r));
    sx[i] := Nodes[i].x;
    sy[i] := Nodes[i].y;
    sr[i] := Nodes[i].r;
  end;
  if d < 1e-4 then
  begin
    SimStep;
    Exit;
  end;
  steps := Min(600, Ceil(d / MAX_STEP));
  for k := 1 to steps do
  begin
    for i := 0 to NodeCnt - 1 do
    begin
      Nodes[i].x := sx[i] + (tx[i] - sx[i]) * k / steps;
      Nodes[i].y := sy[i] + (ty[i] - sy[i]) * k / steps;
      Nodes[i].r := sr[i] + (tr[i] - sr[i]) * k / steps;
    end;
    SimStep;
  end;
end;

procedure BuildPolyPts;
var
  c, k, steps: Integer;
begin
  PolyN := 0;
  for c := 0 to PathN - 1 do
  begin
    steps := Max(1, Ceil(Abs(Sweep(Path[c])) * RadEff(Path[c]) / 3));
    if PolyN + steps + 1 >= Length(Poly) then
      SetLength(Poly, (PolyN + steps + 1) * 2);
    for k := 0 to steps do
    begin
      Poly[PolyN] := ArcPoint(Path[c], k / steps);
      Inc(PolyN);
    end;
  end;
end;

{ จุดตามเส้นกลางของ belt + ระยะสะสม: PolyS[PolyN] = ความยาวทั้งเส้น (ปิดวงกลับจุดแรก) }
procedure BuildPoly;
var
  c, k: Integer;
begin
  BuildPolyPts;
  if Length(PolyS) < PolyN + 1 then
    SetLength(PolyS, PolyN + 1);
  BeltLen := 0;
  for c := 0 to PolyN - 1 do
  begin
    PolyS[c] := BeltLen;
    k := (c + 1) mod PolyN;
    BeltLen := BeltLen + Hypot(Poly[k].x - Poly[c].x, Poly[k].y - Poly[c].y);
  end;
  PolyS[PolyN] := BeltLen;
end;

{ จุดบนเส้นกลาง belt ที่ระยะ s (วนรอบได้) และทิศทางเดินที่จุดนั้น }
procedure PathPoint(s: Single; out p, dir: TPt);
var
  lo, hi, mid, j: Integer;
  len, t: Single;
begin
  p := Pt(0, 0);
  dir := Pt(1, 0);
  if (PolyN < 2) or (BeltLen <= 0) then Exit;
  s := s - BeltLen * Floor(s / BeltLen);
  lo := 0;
  hi := PolyN - 1;
  while lo < hi do
  begin
    mid := (lo + hi + 1) div 2;
    if PolyS[mid] <= s then lo := mid else hi := mid - 1;
  end;
  j := (lo + 1) mod PolyN;
  len := PolyS[lo + 1] - PolyS[lo];
  if len > 1e-6 then
  begin
    t := (s - PolyS[lo]) / len;
    dir := Pt((Poly[j].x - Poly[lo].x) / len, (Poly[j].y - Poly[lo].y) / len);
  end
  else
    t := 0;
  p := Pt(Poly[lo].x + (Poly[j].x - Poly[lo].x) * t, Poly[lo].y + (Poly[j].y - Poly[lo].y) * t);
end;

{ ทาสีบน belt ทุกช่วงที่อยู่ในวงพู่กันรอบ (x, y); col = 0 คือลบ
  สีเก็บตามตำแหน่ง "เนื้อ belt" จึงเคลื่อนไปกับ belt และยืดตามเมื่อ belt ยืด }
procedure PaintAt(x, y: Single; col: Byte);
var
  i, j, k, n, idx: Integer;
  ax, ay, dx, dy, len, t, d, h, reach, sA, sB, ss, f: Single;
begin
  if (PolyN < 2) or (BeltLen <= 1) then Exit;
  reach := BrushR + BeltT / 2;
  for i := 0 to PolyN - 1 do
  begin
    k := (i + 1) mod PolyN;
    ax := Poly[i].x; ay := Poly[i].y;
    dx := Poly[k].x - ax; dy := Poly[k].y - ay;
    len := Hypot(dx, dy);
    if len < 1e-6 then Continue;
    t := EnsureRange(((x - ax) * dx + (y - ay) * dy) / (len * len), 0, 1);
    d := Hypot(x - (ax + dx * t), y - (ay + dy * t));
    if d > reach then Continue;
    h := Sqrt(Max(0, reach * reach - d * d));
    sA := PolyS[i] + EnsureRange(t * len - h, 0, len);
    sB := PolyS[i] + EnsureRange(t * len + h, 0, len);
    n := Ceil((sB - sA) / BeltLen * PAINT_N) + 1;
    for j := 0 to n do
    begin
      ss := sA + (sB - sA) * j / n;
      f := ss / BeltLen - OffF;
      f := f - Floor(f);
      idx := Trunc(f * PAINT_N) mod PAINT_N;
      PaintCells[idx] := col;
      Modified := True;
    end;
  end;
end;

{ ================= even-odd fill ================= }

procedure FillPolyEvenOdd(const P: TPtArr; N: Integer; clipY0, clipY1: Integer);
var
  minY, maxY, yc, tx: Single;
  y, i, j, cnt: Integer;
  a, b: TPt;
  xs: array of Single;
begin
  if N < 3 then Exit;
  SetLength(xs, 256);
  minY := P[0].y; maxY := P[0].y;
  for i := 1 to N - 1 do
  begin
    if P[i].y < minY then minY := P[i].y;
    if P[i].y > maxY then maxY := P[i].y;
  end;
  for y := Max(clipY0, Floor(minY)) to Min(clipY1, Ceil(maxY)) do
  begin
    yc := y + 0.5;
    cnt := 0;
    for i := 0 to N - 1 do
    begin
      a := P[i];
      b := P[(i + 1) mod N];
      if (a.y <= yc) <> (b.y <= yc) then
      begin
        if cnt >= Length(xs) then SetLength(xs, cnt * 2);
        xs[cnt] := a.x + (yc - a.y) * (b.x - a.x) / (b.y - a.y);
        Inc(cnt);
      end;
    end;
    for i := 1 to cnt - 1 do
    begin
      tx := xs[i]; j := i - 1;
      while (j >= 0) and (xs[j] > tx) do
      begin
        xs[j + 1] := xs[j];
        Dec(j);
      end;
      xs[j + 1] := tx;
    end;
    i := 0;
    while i + 1 < cnt do
    begin
      Line(xs[i], y, xs[i + 1], y);
      Inc(i, 2);
    end;
  end;
end;

function InsideEvenOdd(const P: TPtArr; N: Integer; x, y: Single): Boolean;
var
  i, j: Integer;
begin
  Result := False;
  j := N - 1;
  for i := 0 to N - 1 do
  begin
    if ((P[i].y > y) <> (P[j].y > y)) and
       (x < (P[j].x - P[i].x) * (y - P[i].y) / (P[j].y - P[i].y) + P[i].x) then
      Result := not Result;
    j := i;
  end;
end;

{ ================= panels ================= }

{ จุดเริ่มของตาราง (ให้เส้นตรงกับตารางเดิมแบบใน GIF) }
const
  GRID_OX = DBG_X + 7;
  GRID_OY = DBG_Y + 11;

function SnapToGrid(v, origin: Single): Single;
var
  st: Single;
begin
  st := Max(10, GridStep);
  Result := origin + Round((v - origin) / st) * st;
end;

{ ตารางของ View ตามค่าในแผง GRID: เส้นประ / เส้นทึบ / จุด / กากบาท }
procedure DrawGrid;
var
  gx, gy, st, x0, y0, x1, y1: Single;
begin
  if not GridOn then Exit;
  st := Max(10, GridStep);
  x0 := DBG_X + 3;
  y0 := DBG_Y + 3;
  x1 := DBG_X + DBG_W - 3;
  y1 := DBG_Y + DBG_H - 3;
  ColDoc(GridColor, DEFAULT_GRID_COLOR);
  case GridStyle of
    0, 1:
      begin
        gx := GRID_OX + st;
        while gx < x1 do
        begin
          if GridStyle = 1 then
            Line(gx, y0, gx, y1)
          else
          begin
            gy := DBG_Y + 4;
            while gy < y1 do
            begin
              SDL_RenderPoint(Ren, gx, gy);
              gy := gy + 4;
            end;
          end;
          gx := gx + st;
        end;
        gy := GRID_OY + st;
        while gy < y1 do
        begin
          if GridStyle = 1 then
            Line(x0, gy, x1, gy)
          else
          begin
            gx := DBG_X + 4;
            while gx < x1 do
            begin
              SDL_RenderPoint(Ren, gx, gy);
              gx := gx + 4;
            end;
          end;
          gy := gy + st;
        end;
      end;
  else
    begin
      gx := GRID_OX + st;
      while gx < x1 do
      begin
        gy := GRID_OY + st;
        while gy < y1 do
        begin
          if GridStyle = 2 then
            FillRect(gx - 1, gy - 1, 3, 3)
          else
          begin
            Line(gx - 4, gy, gx + 5, gy);
            Line(gx, gy - 4, gx, gy + 5);
          end;
          gy := gy + st;
        end;
        gx := gx + st;
      end;
    end;
  end;
end;

{ ภาพพื้นหลังของ View (อยู่ใต้ตาราง) }
{ ตำแหน่งภาพพื้นหลังในกรอบ (vx, vy, vw, vh): โหมดพอดี + ขยาย + เลื่อน (หมุนรอบจุดกลางภาพ) }
function BgDstRect(vx, vy, vw, vh: Single): TSDL_FRect;
var
  sc, k: Single;
begin
  case ImageMode of
    0: sc := Min(vw / BgW, vh / BgH);       // fit
    1: sc := Max(vw / BgW, vh / BgH);       // fill
    3: sc := 1;                             // center (ขนาดจริง)
  else
    sc := 0;                                // stretch
  end;
  k := ImageScale / 100;
  if ImageMode = 2 then
  begin
    Result.w := vw * k;
    Result.h := vh * k;
  end
  else
  begin
    Result.w := BgW * sc * k;
    Result.h := BgH * sc * k;
  end;
  Result.x := vx + (vw - Result.w) / 2 + ImageOffX;
  Result.y := vy + (vh - Result.h) / 2 + ImageOffY;
end;

{ ภาพพื้นหลังของ View (อยู่ใต้ตาราง) }
procedure DrawBackground;
var
  dst: TSDL_FRect;
begin
  if (BgTex = nil) or (BgW <= 0) or (BgH <= 0) then Exit;
  dst := BgDstRect(DBG_X + 1, DBG_Y + 1, DBG_W - 2, DBG_H - 2);
  SDL_SetTextureAlphaMod(BgTex, Round(EnsureRange(ImageOpacity, 0, 100) * 2.55));
  SDL_RenderTextureRotated(Ren, BgTex, nil, @dst, ImageAngle, nil, SDL_FLIP_NONE);
end;

{ ส่วนโค้งที่ belt พันอยู่: เส้นบางตามทางเดิน + แถบหนาด้านในของ pulley }
procedure DrawElemArc(const e: TElem);
var
  cx, cy, r, re, a0, a1: Single;
begin
  cx := Nodes[e.node].x;
  cy := Nodes[e.node].y;
  r := Nodes[e.node].r;
  re := RadEff(e);
  { มุมที่เก็บเป็นทิศของ n; จุดจริงอยู่ที่ s*R*n จึงต้องกลับทิศเมื่อ s<0 }
  a0 := e.phiIn;
  a1 := e.phiOut;
  if e.s < 0 then
  begin
    a0 := a0 + Pi;
    a1 := a1 + Pi;
  end;
  if BeltT >= 2 then
  begin
    ColDoc(BeltColor, DEFAULT_BELT_COLOR);
    ArcBand(cx, cy, re - BeltT / 2, re + BeltT / 2, a0, a1);
    Ink;
    ArcLine(cx, cy, re - BeltT / 2, a0, a1);
    ArcLine(cx, cy, re + BeltT / 2, a0, a1);
  end
  else
  begin
    Ink;
    ArcLine(cx, cy, re, a0, a1);
  end;
  Ink;
  { แถบหนาแสดงช่วงที่ pulley สัมผัส belt: วาดทุกรอบ ทับกันเป็นแถบเดียว }
  ArcBand(cx, cy, r - 5, r, a0, a1);
  if r > 12 then
  begin
    ArcLine(cx, cy, r - 9, a0, a1);
    Line(cx + (r - 9) * Cos(a0), cy + (r - 9) * Sin(a0), cx + r * Cos(a0), cy + r * Sin(a0));
    Line(cx + (r - 9) * Cos(a1), cy + (r - 9) * Sin(a1), cx + r * Cos(a1), cy + r * Sin(a1));
  end;
end;

{ ช่วงตรงของ belt: แถบกว้างเท่าความหนา }
procedure BeltSeg(const pa, pb: TPt; ok: Boolean);
var
  L, nx, ny, h: Single;
begin
  L := Hypot(pb.x - pa.x, pb.y - pa.y);
  if (BeltT < 2) or (L < 1e-3) then
  begin
    if ok then Ink else Col(220, 40, 40);
    Line(pa.x, pa.y, pb.x, pb.y);
    Exit;
  end;
  h := BeltT / 2;
  nx := -(pb.y - pa.y) / L * h;
  ny := (pb.x - pa.x) / L * h;
  ColDoc(BeltColor, DEFAULT_BELT_COLOR);
  Quad(Pt(pa.x + nx, pa.y + ny), Pt(pb.x + nx, pb.y + ny), Pt(pb.x - nx, pb.y - ny), Pt(pa.x - nx, pa.y - ny));
  Flush;
  if ok then Ink else Col(220, 40, 40);
  Line(pa.x + nx, pa.y + ny, pb.x + nx, pb.y + ny);
  Line(pa.x - nx, pa.y - ny, pb.x - nx, pb.y - ny);
end;

{ สีบน belt: ไล่ช่องสีที่ติดกันเป็นช่วง แล้ววาดเป็นแถบตามเส้นกลาง
  ox, oy, sc แปลงพิกัดฉากไปยังแผงที่วาด (แผง DEBUG ใช้ sc = 1) }
procedure DrawPaint(ox, oy, sc, w: Single);
var
  i, j, k, n, c: Integer;
  s0, s1, ss: Single;
  p, d, q, prevA, prevB, a, b: TPt;
  pc: TRgb;
begin
  if (BeltLen <= 1) or (PolyN < 2) then Exit;
  prevA := Pt(0, 0);
  prevB := prevA;
  i := 0;
  while i < PAINT_N do
  begin
    c := PaintCells[i];
    if c = 0 then
    begin
      Inc(i);
      Continue;
    end;
    j := i + 1;
    while (j < PAINT_N) and (PaintCells[j] = c) do Inc(j);
    s0 := (i / PAINT_N + OffF) * BeltLen;
    s1 := (j / PAINT_N + OffF) * BeltLen;
    pc := PaintRgb(c);
    ColRaw(pc.r, pc.g, pc.b);
    n := Max(1, Ceil((s1 - s0) / 3));
    for k := 0 to n do
    begin
      ss := s0 + (s1 - s0) * k / n;
      PathPoint(ss, p, d);
      q := Pt(ox + (p.x - DBG_X) * sc, oy + (p.y - DBG_Y) * sc);
      a := Pt(q.x - d.y * w / 2, q.y + d.x * w / 2);
      b := Pt(q.x + d.y * w / 2, q.y - d.x * w / 2);
      if k > 0 then
        Quad(prevA, a, b, prevB);
      prevA := a;
      prevB := b;
    end;
    i := j;
  end;
  Flush;
end;

{ ขีดตามเนื้อ belt ให้เห็นว่ากำลังวิ่ง }
procedure DrawBeltTicks;
var
  k: Integer;
  p, d: TPt;
  h: Single;
begin
  if (BeltLen <= 1) or (PolyN < 2) then Exit;
  h := Max(BeltT, 2) / 2 + 2;
  Col(120, 120, 115);
  for k := 0 to TICKS - 1 do
  begin
    PathPoint((k / TICKS + OffF) * BeltLen, p, d);
    Line(p.x - d.y * h, p.y + d.x * h, p.x + d.y * h, p.y - d.x * h);
  end;
end;

{ ซี่ล้อหมุนตาม belt (แสดงเฉพาะตอน belt วิ่ง) }
procedure DrawSpokes;
var
  k, j, c: Integer;
  inPath: Boolean;
  a, r: Single;
begin
  for k := 0 to NodeCnt - 1 do
  begin
    inPath := False;
    for c := 0 to PathN - 1 do
      if Path[c].node = k then inPath := True;
    r := Nodes[k].r;
    if not inPath or (r < 14) then Continue;
    Col(150, 150, 145);
    for j := 0 to 2 do
    begin
      a := PulleyAng[k] + j * 2 * Pi / 3;
      Line(Nodes[k].x + Cos(a) * 8, Nodes[k].y + Sin(a) * 8,
           Nodes[k].x + Cos(a) * (r - 12), Nodes[k].y + Sin(a) * (r - 12));
    end;
  end;
end;

procedure DrawBrush;
var
  pc: TRgb;
begin
  if not PaintOn then Exit;
  if (MouseX < DBG_X) or (MouseX > DBG_X + DBG_W) or (MouseY < DBG_Y) or (MouseY > DBG_Y + DBG_H) then Exit;
  if PaintColor = 0 then
    Col(120, 120, 115)
  else
  begin
    pc := PaintRgb(PaintColor);
    ColRaw(pc.r, pc.g, pc.b);
  end;
  DashedCircle(MouseX, MouseY, BrushR + BeltT / 2);
  Line(MouseX - 3, MouseY, MouseX + 3, MouseY);
  Line(MouseX, MouseY - 3, MouseX, MouseY + 3);
end;

{ ป้าย VIEW + โหมด (DEBUG/OUTLINE) มุมซ้ายบนของแผง: คลิกเพื่อสลับมุมมอง }
function OnViewPill(x, y: Single): Boolean;
var
  w: Single;
begin
  if ShowDebug then w := Length('DEBUG') else w := Length('OUTLINE');
  w := (Length('VIEW') * 8 + 12) + 4 + (w * 8 + 12);
  Result := (x >= DBG_X + 16) and (x < DBG_X + 16 + w) and (y >= DBG_Y + 16) and (y < DBG_Y + 31);
end;

procedure DrawDebugPanel;
var
  i, j, hov: Integer;
  pa, pb: TPt;
  w: Single;
begin
  Panel(DBG_X, DBG_Y, DBG_W, DBG_H);
  ColDoc(ViewColor, DEFAULT_VIEW_COLOR);              // สีพื้นของ View (ตั้งในแผง COLOR)
  FillRoundRect(DBG_X + 1, DBG_Y + 1, DBG_W - 2, DBG_H - 2, 6);
  SetClip(DBG_X + 1, DBG_Y + 1, DBG_W - 2, DBG_H - 2);
  DrawBackground;
  DrawGrid;

  hov := DragIdx;
  if ShowDebug then
  begin
    for i := 0 to NodeCnt - 1 do
    begin
      if (i = hov) or (i = SelNode) then Col(220, 90, 20) else Col(60, 60, 55);
      DashedCircle(Nodes[i].x, Nodes[i].y, Nodes[i].r);
      Ink;
      Line(Nodes[i].x - 5, Nodes[i].y, Nodes[i].x + 6, Nodes[i].y);
      Line(Nodes[i].x, Nodes[i].y - 5, Nodes[i].x, Nodes[i].y + 6);
    end;

    for i := 0 to PathN - 1 do
      DrawElemArc(Path[i]);

    for i := 0 to PathN - 1 do
    begin
      j := (i + 1) mod PathN;
      pa := ArcPoint(Path[i], 1);
      pb := ArcPoint(Path[j], 0);
      BeltSeg(pa, pb, TanOK[i]);
    end;
  end
  else
  begin
    Ink;
    for i := 0 to PolyN - 1 do
    begin
      j := (i + 1) mod PolyN;
      Line(Poly[i].x, Poly[i].y, Poly[j].x, Poly[j].y);
    end;
  end;
  if BeltRun then
    DrawSpokes;
  DrawBeltTicks;
  DrawPaint(DBG_X, DBG_Y, 1, Max(BeltT, 2) + 2);
  DrawBrush;
  SDL_SetRenderClipRect(Ren, nil);

  w := Pill(DBG_X + 16, DBG_Y + 16, 'VIEW', False);
  if ShowDebug then
    Pill(DBG_X + 16 + w + 4, DBG_Y + 16, 'DEBUG', True)
  else
    Pill(DBG_X + 16 + w + 4, DBG_Y + 16, 'OUTLINE', True);
  w := Pill(DBG_X + 16, DBG_Y + 36, 'NODE', False);
  Pill(DBG_X + 16 + w + 4, DBG_Y + 36, IntToStr(PathN), True);
  case Mode of
    mPlay:   Pill(DBG_X + DBG_W - 16 - 4 * 8 - 12, DBG_Y + 16, 'PLAY', True);
    mPaused: Pill(DBG_X + DBG_W - 16 - 5 * 8 - 12, DBG_Y + 16, 'PAUSE', True);
    mRecord: Pill(DBG_X + DBG_W - 16 - 3 * 8 - 12, DBG_Y + 16, 'REC', True);
  end;
end;

function ToRen(const p: TPt): TPt;
begin
  Result.x := REN_X + REN_OX + (p.x - DBG_X) * REN_SCALE;
  Result.y := REN_Y + REN_OY + (p.y - DBG_Y) * REN_SCALE;
end;

procedure DrawRenderPanel;
var
  i: Integer;
  c: TPt;
  s: string;
begin
  Panel(REN_X, REN_Y, REN_W, REN_H);
  SetClip(REN_X + 1, REN_Y + 1, REN_W - 2, REN_H - 2);
  if PolyN >= 3 then
  begin
    if Length(RPoly) < PolyN then
      SetLength(RPoly, PolyN);
    for i := 0 to PolyN - 1 do
      RPoly[i] := ToRen(Poly[i]);
    Ink;
    FillPolyEvenOdd(RPoly, PolyN, REN_Y + 1, REN_Y + REN_H - 2);
    DrawPaint(REN_X + REN_OX, REN_Y + REN_OY, REN_SCALE, 3);
    for i := 0 to NodeCnt - 1 do
    begin
      c := ToRen(Pt(Nodes[i].x, Nodes[i].y));
      if InsideEvenOdd(RPoly, PolyN, c.x, c.y) then Paper else Ink;
      s := IntToStr(i);
      Txt(c.x - Length(s) * 4, c.y - 4, s);
    end;
  end;
  SDL_SetRenderClipRect(Ren, nil);
  Pill(REN_X + 16, REN_Y + 16, 'RENDER', True);
end;

procedure TopoArc(x1, x2, baseY: Single; up: Boolean);
var
  cx, rx, ry, a, ax, ay, bx, by: Single;
  k, n: Integer;
begin
  cx := (x1 + x2) / 2;
  rx := Abs(x2 - x1) / 2;
  ry := Min(rx * 0.72, 62);
  n := Max(8, Round(rx));
  for k := 0 to n - 1 do
  begin
    a := Pi * k / n;
    ax := cx - rx * Cos(a);
    bx := cx - rx * Cos(Pi * (k + 1) / n);
    if up then
    begin
      ay := baseY - ry * Sin(a);
      by := baseY - ry * Sin(Pi * (k + 1) / n);
      Line(ax, ay, bx, by);
    end
    else
    begin
      ay := baseY + ry * Sin(a);
      by := baseY + ry * Sin(Pi * (k + 1) / n);
      if not Odd(k) then
        Line(ax, ay, bx, by);
    end;
  end;
end;

procedure DrawTopoPanel;
var
  i, a, b: Integer;
  x0, cy, xa, xb, sp, bs: Single;
  str: string;
begin
  Panel(TOP_X, TOP_Y, TOP_W, TOP_H);
  Pill(TOP_X + 16, TOP_Y + 16, 'Topology', True);
  if NodeCnt = 0 then
  begin
    Col(150, 150, 145);
    Txt(TOP_X + 16, TOP_Y + 96, 'no pulleys - use + ADD below');
    Exit;
  end;
  { ระยะห่างกล่องย่อตามจำนวน pulley ให้พอดีแผง }
  sp := 36.5;
  if NodeCnt > 1 then sp := Min(36.5, (TOP_W - 50) / (NodeCnt - 1));
  bs := Min(21, sp - 3);
  x0 := TOP_X + (TOP_W - sp * (NodeCnt - 1)) / 2;
  cy := TOP_Y + 108;

  { เส้นเชื่อมตามลำดับการเดินของ belt: ไปทางขวา = โค้งบนเส้นทึบ, ย้อนกลับ = โค้งล่างเส้นประ }
  Ink;
  for i := 0 to PathN - 2 do
  begin
    a := Path[i].node;
    b := Path[i + 1].node;
    xa := x0 + a * sp;
    xb := x0 + b * sp;
    if b = a then Continue;
    if b > a then
      TopoArc(xa, xb, cy - bs / 2 - 5, True)
    else
      TopoArc(xb, xa, cy + bs / 2 + 5, False);
  end;

  for i := 0 to NodeCnt - 1 do
  begin
    xa := x0 + i * sp;
    Ink;
    Line(xa, cy - bs / 2 - 6, xa, cy - bs / 2);
    Line(xa, cy + bs / 2, xa, cy + bs / 2 + 6);
    Disc(xa, cy - bs / 2 - 5, 2.2);
    Disc(xa, cy + bs / 2 + 6, 2.2);
    if i = SelNode then Col(220, 90, 20) else Ink;
    FillRoundRect(xa - bs / 2, cy - bs / 2, bs, bs, Min(5, bs / 3));
    Paper;
    str := IntToStr(i);
    if bs >= Length(str) * 8 + 2 then
      Txt(xa - Length(str) * 4 + 0.5, cy - 3.5, str);
  end;
end;

procedure DrawTicks;
begin
  Col(70, 70, 70);
  Line(1077, 6, 1077, 18);
  Line(1077, REN_Y + REN_H + 4, 1077, REN_Y + REN_H + 16);
  Line(REN_X - 12, 180, REN_X - 2, 180);
  Line(REN_X + REN_W + 2, 180, REN_X + REN_W + 12, 180);
end;

{ ================= main ================= }

function PickNode(x, y: Single): Integer;
var
  i: Integer;
  d, best: Single;
begin
  Result := -1;
  best := 1e9;
  for i := 0 to NodeCnt - 1 do
  begin
    d := Hypot(x - Nodes[i].x, y - Nodes[i].y);
    if (d < Max(Nodes[i].r, 12)) and (d < best) then
    begin
      best := d;
      Result := i;
    end;
  end;
end;

procedure CurrentTargets(out tx, ty, tr: array of Single);
var
  i: Integer;
begin
  for i := 0 to NodeCnt - 1 do
  begin
    tx[i] := Nodes[i].x; ty[i] := Nodes[i].y; tr[i] := Nodes[i].r;
  end;
end;

{ ให้ pulley ตามตำแหน่งในสคริปต์ที่เวลา t }
procedure FollowScript(t: Single);
var
  tx, ty, tr: array[0..MAX_NODES - 1] of Single;
begin
  ScriptPositions(t, tx, ty, tr);
  MoveNodesTo(tx, ty, tr);
end;

procedure UpdatePlay(dt: Single);
var
  tx, ty, tr: array[0..MAX_NODES - 1] of Single;
begin
  if ScriptLen <= 0 then
  begin
    Mode := mIdle;
    Exit;
  end;
  if DemoWait > 0 then
  begin
    DemoWait := DemoWait - dt;
    CurrentTargets(tx, ty, tr);
    MoveNodesTo(tx, ty, tr);
    Exit;
  end;
  DemoT := DemoT + DemoDir * dt;
  if DemoT >= ScriptLen then
  begin
    DemoT := ScriptLen;
    if LoopOn then
      DemoDir := -1      // เล่นย้อนกลับเพื่อคลาย belt แล้ววนใหม่
    else
      Mode := mPaused;
  end
  else if DemoT <= 0 then
  begin
    DemoT := 0;
    DemoDir := 1;
  end;
  FollowScript(DemoT);
  if (DemoT = 0) and (DemoDir = 1) and (Mode = mPlay) then
  begin
    ResetAll;            // กลับถึงจุดเริ่ม ล้างเศษที่อาจค้าง
    DemoWait := 1.0;
  end;
end;

{ ---------- การอัด ---------- }

procedure StartRecording;
var
  i, n: Integer;
begin
  UiCancelEdit;
  if Length(Phases) = 0 then
    CaptureStart;
  { อัดต่อท้ายสคริปต์เดิม: จำลองสคริปต์เดิมจนจบเพื่อให้ belt อยู่ในสภาพเดียวกับตอนเล่น }
  ResetAll;
  n := Ceil(ScriptLen * 30);
  for i := 1 to n do
    FollowScript(ScriptLen * i / n);
  DemoT := ScriptLen;
  RecFrom := Length(Phases);
  RecAcc := 0;
  RecHold := 0;
  for i := 0 to NodeCnt - 1 do
  begin
    RecPX[i] := Nodes[i].x; RecPY[i] := Nodes[i].y; RecPR[i] := Nodes[i].r;
  end;
  Mode := mRecord;
end;

procedure RecordSample;
var
  i, cnt: Integer;
  moved, sized: array[0..MAX_NODES - 1] of Boolean;
begin
  FillChar(moved, SizeOf(moved), 0); FillChar(sized, SizeOf(sized), 0);
  cnt := 0;
  for i := 0 to NodeCnt - 1 do
  begin
    moved[i] := Hypot(Nodes[i].x - RecPX[i], Nodes[i].y - RecPY[i]) > 0.5;
    sized[i] := Abs(Nodes[i].r - RecPR[i]) > 0.3;
    if moved[i] then Inc(cnt);
    if sized[i] then Inc(cnt);
  end;
  if cnt = 0 then
    RecHold := RecHold + RecAcc
  else
  begin
    if RecHold >= MIN_DUR then
      InsertPhase(Length(Phases), MakePhase(pkHold, -1, 0, 0, 0, RecHold));
    RecHold := 0;
    for i := 0 to NodeCnt - 1 do
    begin
      if moved[i] then
        InsertPhase(Length(Phases), MakePhase(pkMove, i, Nodes[i].x, Nodes[i].y, 0, Max(MIN_DUR, RecAcc / cnt)));
      if sized[i] then
        InsertPhase(Length(Phases), MakePhase(pkRadius, i, Nodes[i].r, 0, 0, Max(MIN_DUR, RecAcc / cnt)));
      RecPX[i] := Nodes[i].x; RecPY[i] := Nodes[i].y; RecPR[i] := Nodes[i].r;
    end;
  end;
  RecAcc := 0;
end;

procedure StopRecording;
begin
  if Mode <> mRecord then Exit;
  RecordSample;
  CompactFrom(RecFrom);
  if Length(Phases) > RecFrom then
    Modified := True;
  DemoT := ScriptLen;
  Sel := High(Phases);
  EnsureSelVisible;
  DragIdx := -1;
  Mode := mPaused;
end;

procedure UpdateManual(wheelNode: Integer; wheelDelta: Single);
var
  tx, ty, tr: array[0..MAX_NODES - 1] of Single;
  i: Integer;
begin
  FillChar(tx, SizeOf(tx), 0); FillChar(ty, SizeOf(ty), 0); FillChar(tr, SizeOf(tr), 0);
  for i := 0 to NodeCnt - 1 do
  begin
    tx[i] := Nodes[i].x; ty[i] := Nodes[i].y; tr[i] := Nodes[i].r;
  end;
  if DragIdx >= 0 then
  begin
    tx[DragIdx] := EnsureRange(MouseX + DragDX, DBG_X, DBG_X + DBG_W);
    ty[DragIdx] := EnsureRange(MouseY + DragDY, DBG_Y, DBG_Y + DBG_H);
    if GridSnap then
    begin
      tx[DragIdx] := SnapToGrid(tx[DragIdx], GRID_OX);
      ty[DragIdx] := SnapToGrid(ty[DragIdx], GRID_OY);
    end;
  end;
  if wheelNode >= 0 then
    tr[wheelNode] := EnsureRange(Nodes[wheelNode].r + wheelDelta, 8, 150);
  MoveNodesTo(tx, ty, tr);
end;

{ ---------- ธีม (จำไว้ในโฟลเดอร์ตั้งค่าของผู้ใช้ ไม่ใช่ในเอกสาร) ---------- }

function ThemeFile: string;
begin
  Result := GetAppConfigDir(False) + 'theme.cfg';
end;

procedure LoadThemePref;
var
  L: TStringList;
begin
  if not FileExists(ThemeFile) then Exit;
  L := TStringList.Create;
  try
    try
      L.LoadFromFile(ThemeFile);
      if L.Count > 0 then SetTheme(FindTheme(Trim(L[0])));
    except
      // ไฟล์เสียก็ใช้ธีมตั้งต้น
    end;
  finally
    L.Free;
  end;
end;

procedure SaveThemePref;
var
  L: TStringList;
begin
  L := TStringList.Create;
  try
    try
      ForceDirectories(GetAppConfigDir(False));
      L.Add(THEMES[ThemeIdx].name);
      L.SaveToFile(ThemeFile);
    except
      // บันทึกไม่ได้ก็แค่ไม่จำธีม
    end;
  finally
    L.Free;
  end;
end;

{ ---------- เอกสาร / ไฟล์ ---------- }

procedure UpdateTitle;
var
  t: string;
begin
  if DocFile = '' then t := 'untitled' else t := ExtractFileName(DocFile);
  if Modified then t := t + ' *';
  SDL_SetWindowTitle(Win, PAnsiChar('Belt and Pulley Path - ' + t));
end;

procedure ShowError(const title, msg: string);
begin
  SDL_ShowSimpleMessageBox(SDL_MESSAGEBOX_ERROR, PAnsiChar(title), PAnsiChar(msg), Win);
end;

{ ถามก่อนทิ้งงานที่ยังไม่บันทึก }
function ConfirmDiscard: Boolean;
var
  data: TSDL_MessageBoxData;
  btn: array[0..1] of TSDL_MessageBoxButtonData;
  id: LongInt;
begin
  if not Modified then Exit(True);
  btn[0].flags := SDL_MESSAGEBOX_BUTTON_ESCAPEKEY_DEFAULT;
  btn[0].buttonID := 0;
  btn[0].Text := 'Cancel';
  btn[1].flags := SDL_MESSAGEBOX_BUTTON_RETURNKEY_DEFAULT;
  btn[1].buttonID := 1;
  btn[1].Text := 'Discard';
  FillChar(data, SizeOf(data), 0);
  data.flags := SDL_MESSAGEBOX_WARNING;
  data.window := Win;
  data.title := 'Unsaved changes';
  data.message := 'The animation has unsaved changes. Discard them?';
  data.numbuttons := 2;
  data.Buttons := @btn[0];
  id := 0;
  Result := SDL_ShowMessageBox(@data, @id) and (id = 1);
end;

procedure ClearBackground;
begin
  if BgTex <> nil then
    SDL_DestroyTexture(BgTex);
  BgTex := nil;
  BgW := 0;
  BgH := 0;
  BgMissing := False;
end;

{ หาไฟล์ภาพ: ตามที่บันทึกไว้ หรือชื่อเดียวกันในโฟลเดอร์ของไฟล์แอนิเมชัน }
function ResolveImage(const path: string): string;
begin
  Result := '';
  if path = '' then Exit;
  if FileExists(path) then Exit(path);
  if (DocFile <> '') and FileExists(ExtractFilePath(DocFile) + ExtractFileName(path)) then
    Result := ExtractFilePath(DocFile) + ExtractFileName(path);
end;

function LoadBackground(const path: string; showErr: Boolean): Boolean;
var
  fn: string;
  tex: PSDL_Texture;
begin
  Result := False;
  ClearBackground;
  if path = '' then Exit;
  fn := ResolveImage(path);
  if fn = '' then
  begin
    BgMissing := True;
    if showErr then ShowError('Image', 'File not found:' + LineEnding + path);
    Exit;
  end;
  tex := IMG_LoadTexture(Ren, PAnsiChar(UTF8String(fn)));   // SDL ใช้ชื่อไฟล์แบบ UTF-8
  if tex = nil then
  begin
    BgMissing := True;
    if showErr then
      ShowError('Image', 'Cannot load ' + fn + LineEnding + string(SDL_GetError));
    Exit;
  end;
  BgTex := tex;
  SDL_SetTextureBlendMode(BgTex, SDL_BLENDMODE_BLEND);
  SDL_GetTextureSize(BgTex, @BgW, @BgH);
  Result := True;
end;

{ บันทึกภาพพื้นหลังที่หมุน/ย่อ/เลื่อนแล้วเป็น PNG ขนาดเท่า View แล้วใช้ไฟล์นั้นเป็นพื้นหลังแทน }
function BakeBackground(const fn: string): Boolean;
var
  tgt: PSDL_Texture;
  surf: PSDL_Surface;
  dst: TSDL_FRect;
  vw, vh: Integer;
begin
  Result := False;
  if BgTex = nil then Exit;
  vw := DBG_W - 2;
  vh := DBG_H - 2;
  tgt := SDL_CreateTexture(Ren, SDL_PIXELFORMAT_ARGB8888, SDL_TEXTUREACCESS_TARGET, vw, vh);
  if tgt = nil then
  begin
    ShowError('Save as background', string(SDL_GetError));
    Exit;
  end;
  SDL_SetRenderTarget(Ren, tgt);
  SDL_SetRenderDrawColor(Ren, 0, 0, 0, 0);       // ส่วนที่ไม่มีภาพ = โปร่งใส
  SDL_RenderClear(Ren);
  dst := BgDstRect(0, 0, vw, vh);
  SDL_SetTextureAlphaMod(BgTex, 255);
  SDL_RenderTextureRotated(Ren, BgTex, nil, @dst, ImageAngle, nil, SDL_FLIP_NONE);
  surf := SDL_RenderReadPixels(Ren, nil);
  SDL_SetRenderTarget(Ren, nil);
  SDL_DestroyTexture(tgt);
  if surf = nil then
  begin
    ShowError('Save as background', string(SDL_GetError));
    Exit;
  end;
  Result := IMG_SavePNG(surf, PAnsiChar(UTF8String(fn)));
  SDL_DestroySurface(surf);
  if not Result then
    ShowError('Save as background', 'Cannot save ' + fn + LineEnding + string(SDL_GetError));
end;

{ ส่งออกเส้นทาง belt (เส้นกลาง) ไว้สร้างถนนในเกมขับรถ: JSON หรือ CSV ตามนามสกุลไฟล์
  พิกัดเทียบมุมซ้ายบนของ View (x ไปขวา, y ลง) หน่วยพิกเซล เรียงตามทิศที่ belt วิ่ง }
procedure ExportRoad(const fn: string);
var
  L: TStringList;
  n, i, c, q: Integer;
  p, d, pa, pb: TPt;
  ss, a0, sw, rr: Single;
  fs: TFormatSettings;
  isCsv: Boolean;
  sep, turn: string;

  function F(v: Single): string;
  begin
    Result := FormatFloat('0.###', v, fs);
  end;

begin
  if PathN < 2 then
  begin
    ShowError('Export Road', 'There is no belt to export.');
    Exit;
  end;
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  BuildPoly;
  n := Max(8, Round(BeltLen / 4));             // จุดห่างกันประมาณ 4 px
  isCsv := LowerCase(ExtractFileExt(fn)) = '.csv';
  L := TStringList.Create;
  try
    if isCsv then
    begin
      L.Add('s,x,y,heading_deg');
      for i := 0 to n - 1 do
      begin
        ss := BeltLen * i / n;
        PathPoint(ss, p, d);
        L.Add(F(ss) + ',' + F(p.x - DBG_X) + ',' + F(p.y - DBG_Y) + ',' + F(ArcTan2(d.y, d.x) * 180 / Pi));
      end;
    end
    else
    begin
      L.Add('{');
      L.Add('  "format": "belt-road 1",');
      L.Add('  "units": "px",');
      L.Add('  "origin": "top-left of the View, x right, y down",');
      L.Add('  "closed": true,');
      L.Add('  "direction": "points follow the belt travel direction",');
      L.Add('  "length": ' + F(BeltLen) + ',');
      L.Add('  "width": ' + F(BeltT) + ',');
      L.Add('  "point_spacing": ' + F(BeltLen / n) + ',');
      L.Add('  "points": [');
      for i := 0 to n - 1 do
      begin
        ss := BeltLen * i / n;
        PathPoint(ss, p, d);
        if i < n - 1 then sep := ',' else sep := '';
        L.Add(Format('    [%s, %s, %s]%s', [F(p.x - DBG_X), F(p.y - DBG_Y), F(ArcTan2(d.y, d.x) * 180 / Pi), sep]));
      end;
      L.Add('  ],');
      L.Add('  "segments": [');
      for c := 0 to PathN - 1 do
      begin
        q := (c + 1) mod PathN;
        { โค้งรอบ pulley: มุมเป็นทิศจากจุดศูนย์กลางไปยังเส้นกลางถนน }
        a0 := Path[c].phiIn;
        if Path[c].s < 0 then a0 := a0 + Pi;
        sw := Path[c].phiOut - Path[c].phiIn;
        rr := RadEff(Path[c]);
        if sw > 0 then turn := 'right' else turn := 'left';     // y ชี้ลง: มุมเพิ่ม = ตามเข็ม = เลี้ยวขวา
        L.Add(Format('    {"type": "arc", "pulley": %d, "center": [%s, %s], "radius": %s, ' +
          '"start_deg": %s, "end_deg": %s, "sweep_deg": %s, "turn": "%s", "length": %s},',
          [Path[c].node, F(Nodes[Path[c].node].x - DBG_X), F(Nodes[Path[c].node].y - DBG_Y), F(rr),
           F(a0 * 180 / Pi), F((a0 + sw) * 180 / Pi), F(sw * 180 / Pi), turn, F(Abs(sw) * rr)]));
        pa := ArcPoint(Path[c], 1);
        pb := ArcPoint(Path[q], 0);
        if c < PathN - 1 then sep := ',' else sep := '';
        L.Add(Format('    {"type": "line", "from": [%s, %s], "to": [%s, %s], "length": %s}%s',
          [F(pa.x - DBG_X), F(pa.y - DBG_Y), F(pb.x - DBG_X), F(pb.y - DBG_Y),
           F(Hypot(pb.x - pa.x, pb.y - pa.y)), sep]));
      end;
      L.Add('  ],');
      L.Add('  "pulleys": [');
      for i := 0 to NodeCnt - 1 do
      begin
        if i < NodeCnt - 1 then sep := ',' else sep := '';
        L.Add(Format('    {"id": %d, "x": %s, "y": %s, "r": %s}%s',
          [i, F(Nodes[i].x - DBG_X), F(Nodes[i].y - DBG_Y), F(Nodes[i].r), sep]));
      end;
      L.Add('  ]');
      L.Add('}');
    end;
    try
      L.SaveToFile(fn);
    except
      on Ex: Exception do
        ShowError('Export Road', 'Cannot save ' + fn + LineEnding + Ex.Message);
    end;
  finally
    L.Free;
  end;
end;

procedure AfterLoad;
begin
  SelNode := -1;
  NodeCnt := Min(NodeCount, MAX_NODES);
  { ค่าของ belt มาจากเอกสาร (ไฟล์ที่เปิด หรือค่าตั้งต้นของ New) }
  BeltTTarget := BeltThick;
  BeltT := BeltThick;
  BeltSpeed := BeltSpeedDoc;
  BeltRun := BeltRunDoc;
  ImageMoveOn := False;
  OffF := BeltOffset;
  Modified := False;
  Sel := -1;
  UiCancelEdit;
  ResetAll;
  DemoT := 0;
  if ScriptLen > 0 then Mode := mPaused else Mode := mIdle;
  { สภาพการพันตอนเริ่มต้องชัดเจนเสมอ (ไม่งั้นเพิ่ม/ลบ pulley แล้ว belt เริ่มต้นจะเปลี่ยน) }
  if (Length(StartWraps) = 0) and (PathN >= 2) then
    CaptureStart;
  LoadBackground(ImagePath, False);
  UpdateTitle;
end;

procedure OpenFile(const fn: string);
var
  msg: string;
begin
  try
    msg := LoadScriptFile(fn);
  except
    on Ex: Exception do
    begin
      ShowError('Open', 'Cannot open ' + fn + LineEnding + Ex.Message);
      Exit;
    end;
  end;
  DocFile := fn;
  AfterLoad;
  if msg <> '' then
    SDL_ShowSimpleMessageBox(SDL_MESSAGEBOX_WARNING, PAnsiChar(ExtractFileName(fn)),
      PAnsiChar('These lines were skipped:' + LineEnding + msg), Win);
end;

function SaveFile(const fn: string): Boolean;
begin
  Result := False;
  try
    BeltThick := BeltTTarget;
    BeltSpeedDoc := BeltSpeed;
    BeltOffset := OffF;
    BeltRunDoc := BeltRun;
    { ยังไม่มีแอนิเมชัน: บันทึกตำแหน่ง/ขนาด pulley และ belt ตามที่เห็นตอนนี้ }
    if Length(Phases) = 0 then
      CaptureStart;
    SaveScriptFile(fn);
  except
    on Ex: Exception do
    begin
      ShowError('Save', 'Cannot save ' + fn + LineEnding + Ex.Message);
      Exit;
    end;
  end;
  DocFile := fn;
  Modified := False;
  UpdateTitle;
  Result := True;
end;

{ callback ของกล่องเลือกไฟล์ อาจถูกเรียกจาก thread อื่น จึงแค่คัดลอกชื่อไฟล์แล้วตั้งธง }
procedure DialogCallback(userdata: Pointer; filelist: PPAnsiChar; filter: LongInt); cdecl;
var
  p: PAnsiChar;
  i: Integer;
begin
  DlgPath[0] := #0;
  if (filelist <> nil) and (filelist^ <> nil) then
  begin
    p := filelist^;
    i := 0;
    while (p[i] <> #0) and (i < High(DlgPath)) do
    begin
      DlgPath[i] := p[i];
      Inc(i);
    end;
    DlgPath[i] := #0;
  end;
  InterLockedExchange(DlgResult, LongInt(PtrUInt(userdata)));
end;

procedure DoNew;
begin
  if not ConfirmDiscard then Exit;
  StopRecording;
  ClearScript(True);
  DocFile := '';
  AfterLoad;
  Mode := mIdle;
end;

procedure DoOpen;
begin
  if DlgBusy or not ConfirmDiscard then Exit;
  StopRecording;
  if DocFile <> '' then DlgDir := ExtractFilePath(DocFile) else DlgDir := ExtractFilePath(ParamStr(0));
  DlgBusy := True;
  SDL_ShowOpenFileDialog(@DialogCallback, Pointer(1), Win, @DlgFilters[0], 2, PAnsiChar(DlgDir), False);
end;

{ บันทึกเป็นไฟล์ใหม่เสมอ (ถามชื่อไฟล์) }
procedure DoSaveAs;
begin
  if DlgBusy then Exit;
  StopRecording;
  if DocFile <> '' then DlgDir := ExtractFilePath(DocFile) else DlgDir := ExtractFilePath(ParamStr(0));
  DlgBusy := True;
  SDL_ShowSaveFileDialog(@DialogCallback, Pointer(2), Win, @DlgFilters[0], 2, PAnsiChar(UTF8String(DlgDir)));
end;

procedure DoSave;
begin
  if DlgBusy then Exit;
  StopRecording;
  if DocFile <> '' then
  begin
    SaveFile(DocFile);
    Exit;
  end;
  DlgDir := ExtractFilePath(ParamStr(0));
  DlgBusy := True;
  SDL_ShowSaveFileDialog(@DialogCallback, Pointer(2), Win, @DlgFilters[0], 2, PAnsiChar(DlgDir));
end;

procedure DoExportRoad;
begin
  if DlgBusy then Exit;
  if PathN < 2 then
  begin
    ShowError('Export Road', 'There is no belt to export.');
    Exit;
  end;
  if DocFile <> '' then DlgDir := ExtractFilePath(DocFile) else DlgDir := ExtractFilePath(ParamStr(0));
  DlgBusy := True;
  SDL_ShowSaveFileDialog(@DialogCallback, Pointer(4), Win, @RoadFilters[0], 2, PAnsiChar(UTF8String(DlgDir)));
end;

procedure DoBakeImage;
begin
  if DlgBusy or (BgTex = nil) then Exit;
  if ImagePath <> '' then DlgDir := ExtractFilePath(ImagePath) else DlgDir := ExtractFilePath(ParamStr(0));
  DlgBusy := True;
  SDL_ShowSaveFileDialog(@DialogCallback, Pointer(5), Win, @PngFilters[0], 1, PAnsiChar(UTF8String(DlgDir)));
end;

procedure DoOpenImage;
begin
  if DlgBusy then Exit;
  if ImagePath <> '' then DlgDir := ExtractFilePath(ImagePath)
  else if DocFile <> '' then DlgDir := ExtractFilePath(DocFile)
  else DlgDir := ExtractFilePath(ParamStr(0));
  DlgBusy := True;
  SDL_ShowOpenFileDialog(@DialogCallback, Pointer(3), Win, @ImgFilters[0], 2,
    PAnsiChar(UTF8String(DlgDir)), False);
end;

procedure PollDialog;
var
  k: LongInt;
  fn: string;
  u: RawByteString;
begin
  k := InterLockedExchange(DlgResult, 0);
  if k = 0 then Exit;
  DlgBusy := False;
  { ชื่อไฟล์จาก SDL เป็น UTF-8: แปลงเป็นสตริงของระบบ (ชื่อภาษาไทยจึงเปิดได้) }
  u := StrPas(PAnsiChar(@DlgPath[0]));
  SetCodePage(u, CP_UTF8, False);
  fn := u;
  if fn = '' then Exit;           // ยกเลิก
  if k = 4 then
  begin
    if ExtractFileExt(fn) = '' then fn := fn + '.json';
    ExportRoad(fn);
    Exit;
  end;
  if k = 5 then
  begin
    if LowerCase(ExtractFileExt(fn)) <> '.png' then fn := fn + '.png';
    if BakeBackground(fn) and LoadBackground(fn, True) then
    begin
      { ภาพใหม่ตรงกับ View อยู่แล้ว: ไม่ต้องหมุน/ย่อ/เลื่อนอีก }
      ImagePath := fn;
      ImageMode := 3;
      ImageAngle := 0;
      ImageScale := 100;
      ImageOffX := 0;
      ImageOffY := 0;
      ImageMoveOn := False;
      Modified := True;
      UpdateTitle;
    end;
    Exit;
  end;
  if k = 3 then
  begin
    if LoadBackground(fn, True) then
    begin
      ImagePath := fn;
      Modified := True;
      UpdateTitle;
    end;
  end
  else if k = 1 then
    OpenFile(fn)
  else
  begin
    if ExtractFileExt(fn) = '' then fn := fn + '.txt';
    SaveFile(fn);
  end;
end;

{ ---------- คำสั่งจากแผง ANIMATION ---------- }

procedure PauseAt(t: Single);
begin
  DemoT := EnsureRange(t, 0, ScriptLen);
  DragIdx := -1;
  Mode := mPaused;
end;

procedure AddCommand(kind: TPhaseKind);
var
  node: Integer;
  ph: TPhase;
begin
  if (kind <> pkHold) and ((NodeCnt = 0) or ((kind = pkOrbit) and (NodeCnt < 2))) then Exit;
  if Length(Phases) = 0 then
    CaptureStart;                 // คำสั่งแรก: ฉากเริ่มต้น = ที่เห็นอยู่
  node := Min(4, NodeCnt - 1);
  if (Sel >= 0) and (Sel <= High(Phases)) and (Phases[Sel].node >= 0) then
    node := Phases[Sel].node;
  if SelNode >= 0 then
    node := SelNode;
  case kind of
    pkLine, pkMove: ph := MakePhase(kind, node, Nodes[node].x, Nodes[node].y, 0, 1.0);
    pkOrbit: ph := MakePhase(pkOrbit, node, (node + 1) mod Max(1, NodeCnt), 1, 0, 2.0);
    pkRadius: ph := MakePhase(pkRadius, node, Nodes[node].r, 0, 0, 0.5);
  else
    ph := MakePhase(pkHold, -1, 0, 0, 0, 1.0);
  end;
  if (Sel < 0) or (Sel > High(Phases)) then Sel := High(Phases);
  InsertPhase(Sel + 1, ph);
  Inc(Sel);
  EnsureSelVisible;
  Modified := True;
  PauseAt(PhaseStart(Sel) + Phases[Sel].dur);
end;

{ ---------- แผง PULLEY ---------- }

function NodeInPath(k: Integer): Boolean;
var
  c: Integer;
begin
  Result := False;
  for c := 0 to PathN - 1 do
    if Path[c].node = k then Exit(True);
end;

procedure SceneEdited;
begin
  Modified := True;
  if Length(Phases) = 0 then
    CaptureStart;
end;

{ มี pulley ตั้งแต่ 2 ตัวแต่ยังไม่มี belt: คล้อง belt รอบ pulley 0 กับ 1 }
procedure EnsureBelt;
var
  i: Integer;
begin
  if PathN >= 2 then Exit;
  PathN := 0;
  if NodeCnt < 2 then Exit;
  for i := 0 to 1 do
  begin
    Path[i].node := i;
    Path[i].s := -1;
    Path[i].layer := 0;
    Path[i].ord := OrdCounter + i;
    Path[i].joint := False;
  end;
  Inc(OrdCounter, 2);
  PathN := 2;
  InitAngles;
end;

{ ตัดช่วงของ pulley k ออกจาก belt (keepIndex = เลื่อนหมายเลข pulley ที่มากกว่า k ลงด้วยไหม) }
procedure RemoveNodeFromPath(k: Integer; renumber: Boolean);
var
  c, j: Integer;
begin
  j := 0;
  for c := 0 to PathN - 1 do
    if Path[c].node <> k then
    begin
      Path[j] := Path[c];
      if renumber and (Path[j].node > k) then Dec(Path[j].node);
      Inc(j);
    end;
  PathN := j;
  if PathN < 2 then
  begin
    PathN := 0;
    Exit;
  end;
  for c := 0 to PathN - 1 do
    if Path[c].joint and (Path[(c + 1) mod PathN].node <> Path[c].node) then
      Path[c].joint := False;
  FixMerges;
  InitAngles;
  RecomputeAngles;
end;

{ หาที่ว่างให้ pulley ใหม่: ไม่ทับ pulley อื่นและไม่ทับเส้น belt }
function FindFreeSpot(r: Single; out x, y: Single): Boolean;
var
  gx, gy, best, d, dmin, cx, cy: Single;
  i, k: Integer;
  dx, dy, len, t: Single;
begin
  Result := False;
  cx := DBG_X + DBG_W / 2;
  cy := DBG_Y + DBG_H / 2;
  x := cx;
  y := cy;
  best := 1e9;
  gy := DBG_Y + r + 20;
  while gy <= DBG_Y + DBG_H - r - 20 do
  begin
    gx := DBG_X + r + 20;
    while gx <= DBG_X + DBG_W - r - 20 do
    begin
      dmin := 1e9;
      for i := 0 to NodeCnt - 1 do
        dmin := Min(dmin, Hypot(gx - Nodes[i].x, gy - Nodes[i].y) - Nodes[i].r - r);
      for i := 0 to PolyN - 1 do
      begin
        k := (i + 1) mod PolyN;
        dx := Poly[k].x - Poly[i].x;
        dy := Poly[k].y - Poly[i].y;
        len := dx * dx + dy * dy;
        if len < 1e-6 then Continue;
        t := EnsureRange(((gx - Poly[i].x) * dx + (gy - Poly[i].y) * dy) / len, 0, 1);
        dmin := Min(dmin, Hypot(gx - Poly[i].x - dx * t, gy - Poly[i].y - dy * t) - r - BeltT);
      end;
      d := Hypot(gx - cx, gy - cy);
      if (dmin > 12) and (d < best) then
      begin
        best := d;
        x := gx;
        y := gy;
        Result := True;
      end;
      gx := gx + 15;
    end;
    gy := gy + 15;
  end;
end;

procedure AddPulley;
var
  x, y: Single;
begin
  if NodeCnt >= MAX_NODES then Exit;
  StopRecording;
  FindFreeSpot(30, x, y);
  Nodes[NodeCnt].x := x;
  Nodes[NodeCnt].y := y;
  Nodes[NodeCnt].r := 30;
  PulleyAng[NodeCnt] := 0;
  if Length(Phases) > 0 then
    AddStartNode(x, y, 30);       // ฉากเริ่มต้นของแอนิเมชันมี pulley ตัวนี้ด้วย
  Inc(NodeCnt);
  SelNode := NodeCnt - 1;
  if Mode in [mPlay, mPaused] then Mode := mIdle;
  EnsureBelt;
  SceneEdited;
end;

procedure DeletePulley(k: Integer);
var
  i: Integer;
begin
  if (k < 0) or (k >= NodeCnt) then Exit;
  StopRecording;
  UiCancelEdit;
  RemoveNodeFromPath(k, True);
  for i := k to NodeCnt - 2 do
  begin
    Nodes[i] := Nodes[i + 1];
    PulleyAng[i] := PulleyAng[i + 1];
  end;
  Dec(NodeCnt);
  DeleteStartNode(k);             // ฉากเริ่มต้น + คำสั่งที่อ้างถึง pulley นี้
  if Length(StartX) <> NodeCnt then SetNodeCount(NodeCnt);
  Sel := Min(Sel, High(Phases));
  EnsureSelVisible;
  SelNode := -1;
  DragIdx := -1;
  if Mode in [mPlay, mPaused] then Mode := mIdle;
  EnsureBelt;
  SceneEdited;
end;

{ คล้อง belt เข้ากับ pulley k ที่ช่วงตรงที่อยู่ใกล้ที่สุด (belt อ้อมไปด้านไกลของ pulley) }
procedure HookPulley(k: Integer);
var
  c, q, best, i, j: Integer;
  n, pa, pb, n2, p1, p2: TPt;
  ok: Boolean;
  dx, dy, len, t, d, bestD, h, a1, a2, sw: Single;
  e: TElem;
begin
  if (k < 0) or (k >= NodeCnt) or NodeInPath(k) then Exit;
  EnsureBelt;
  if NodeInPath(k) or (PathN < 2) then
  begin
    SceneEdited;
    Exit;
  end;
  BuildPoly;                      // ใช้รูปวง belt ปัจจุบันตัดสินด้านที่พัน
  best := -1;
  bestD := 1e9;
  for c := 0 to PathN - 1 do
  begin
    if Path[c].joint then Continue;
    q := (c + 1) mod PathN;
    TangentElem(Path[c], Path[q], n, pa, pb, ok);
    dx := pb.x - pa.x;
    dy := pb.y - pa.y;
    len := dx * dx + dy * dy;
    if len < 1e-6 then Continue;
    t := EnsureRange(((Nodes[k].x - pa.x) * dx + (Nodes[k].y - pa.y) * dy) / len, 0, 1);
    d := Hypot(Nodes[k].x - pa.x - dx * t, Nodes[k].y - pa.y - dy * t);
    if d < bestD then
    begin
      bestD := d;
      best := c;
    end;
  end;
  if best < 0 then Exit;
  c := best;
  q := (c + 1) mod PathN;
  { ด้านที่พัน: อยู่นอกวง belt = พันแบบนูน (belt อ้อมด้านนอก), อยู่ในวง = แบบเว้า
    ด้านนูนขึ้นกับทิศเดินของ belt: ตามเข็มบนจอ (พื้นที่เป็นบวกเมื่อ y ชี้ลง) นูน = -1 }
  h := 0;
  for i := 0 to PolyN - 1 do
  begin
    j := (i + 1) mod PolyN;
    h := h + Poly[i].x * Poly[j].y - Poly[j].x * Poly[i].y;
  end;
  if h > 0 then e.s := -1 else e.s := 1;
  if (PolyN >= 3) and InsideEvenOdd(Poly, PolyN, Nodes[k].x, Nodes[k].y) then
    e.s := -e.s;
  e.node := k;
  e.layer := WrapCount(k);
  e.ord := OrdCounter;
  Inc(OrdCounter);
  e.joint := False;
  TangentElem(Path[c], e, n2, p1, p2, ok);
  a1 := ArcTan2(n2.y, n2.x);
  TangentElem(e, Path[q], n2, p1, p2, ok);
  a2 := ArcTan2(n2.y, n2.x);
  sw := WrapAngle(e.s * (a1 - a2));
  e.phiIn := a1;
  e.phiOut := a1 - e.s * sw;
  InsertAt(c + 1, e);
  RecomputeAngles;
  if Mode in [mPlay, mPaused] then Mode := mIdle;
  SceneEdited;
end;

procedure UnhookPulley(k: Integer);
var
  c, cnt: Integer;
begin
  cnt := 0;
  for c := 0 to PathN - 1 do
    if Path[c].node = k then Inc(cnt);
  if (cnt = 0) or (PathN - cnt < 2) then Exit;   // belt ต้องเหลืออย่างน้อย 2 ช่วง
  RemoveNodeFromPath(k, False);
  if Mode in [mPlay, mPaused] then Mode := mIdle;
  SceneEdited;
end;

procedure EditPulley(field: Integer; v: Single);
var
  tx, ty, tr: array[0..MAX_NODES - 1] of Single;
  i: Integer;
begin
  FillChar(tx, SizeOf(tx), 0); FillChar(ty, SizeOf(ty), 0); FillChar(tr, SizeOf(tr), 0);
  if (SelNode < 0) or (SelNode >= NodeCnt) then Exit;
  for i := 0 to NodeCnt - 1 do
  begin
    tx[i] := Nodes[i].x; ty[i] := Nodes[i].y; tr[i] := Nodes[i].r;
  end;
  case field of
    0: tx[SelNode] := EnsureRange(v, DBG_X, DBG_X + DBG_W);
    1: ty[SelNode] := EnsureRange(v, DBG_Y, DBG_Y + DBG_H);
  else
    tr[SelNode] := EnsureRange(v, 8, 150);
  end;
  if Mode in [mPlay, mPaused] then Mode := mIdle;
  MoveNodesTo(tx, ty, tr);       // เลื่อนทีละนิด belt จึงพัน/คลายตามปกติ
  SceneEdited;
end;

procedure HandleAction(act: TUiAction);
begin
  case act of
    uaNew: DoNew;
    uaOpen: DoOpen;
    uaSave: DoSave;
    uaSaveAs: DoSaveAs;
    uaColorChanged: Modified := True;
    uaAnimToggled:
      { ซ่อนแผง ANIMATION = หน้าต่างเตี้ยลงเหลือแค่ฉาก }
      if AnimPanelOn then
        SDL_SetWindowSize(Win, WIN_W, WIN_H)
      else
        SDL_SetWindowSize(Win, WIN_W, AP_Y);
    uaExit: if ConfirmDiscard then Running := False;
    uaPlay:
      if Mode = mPlay then
        Mode := mPaused
      else if ScriptLen > 0 then
      begin
        if (Mode = mIdle) or (DemoT >= ScriptLen - 1e-3) then
          ResetAll;
        DemoDir := 1;
        DemoWait := 0;
        Mode := mPlay;
      end;
    uaRec:
      if Mode = mRecord then StopRecording else StartRecording;
    uaStop:
      if Mode = mRecord then
        StopRecording
      else
      begin
        ResetAll;
        PauseAt(0);
      end;
    uaLoop: LoopOn := not LoopOn;
    uaScrub: PauseAt(ScrubT);
    uaSelect:
      if (Sel >= 0) and (Sel <= High(Phases)) then
        PauseAt(PhaseStart(Sel) + Phases[Sel].dur);
    uaEdited:
      begin
        Modified := True;
        if (Sel >= 0) and (Sel <= High(Phases)) then
          PauseAt(PhaseStart(Sel) + Phases[Sel].dur);
      end;
    uaAddLine: AddCommand(pkLine);
    uaAddMove: AddCommand(pkMove);
    uaAddOrbit: AddCommand(pkOrbit);
    uaAddRadius: AddCommand(pkRadius);
    uaAddHold: AddCommand(pkHold);
    uaDelete:
      begin
        DeletePhase(Sel);
        Sel := Min(Sel, High(Phases));
        EnsureSelVisible;
        Modified := True;
        if Sel >= 0 then PauseAt(PhaseStart(Sel) + Phases[Sel].dur) else PauseAt(0);
      end;
    uaUp, uaDown:
      begin
        if act = uaUp then
        begin
          if Sel <= 0 then Exit;
          SwapPhases(Sel, Sel - 1);
          Dec(Sel);
        end
        else
        begin
          if Sel >= High(Phases) then Exit;
          SwapPhases(Sel, Sel + 1);
          Inc(Sel);
        end;
        EnsureSelVisible;
        Modified := True;
        PauseAt(PhaseStart(Sel) + Phases[Sel].dur);
      end;
    uaBeltRun: BeltRun := not BeltRun;
    uaSpeedDn:
      begin
        BeltSpeed := EnsureRange(BeltSpeed - 20, -400, 400);
        Modified := True;
      end;
    uaSpeedUp:
      begin
        BeltSpeed := EnsureRange(BeltSpeed + 20, -400, 400);
        Modified := True;
      end;
    uaThickDn:
      begin
        BeltTTarget := EnsureRange(BeltTTarget - 1, 1, 12);
        Modified := True;
      end;
    uaThickUp:
      begin
        BeltTTarget := EnsureRange(BeltTTarget + 1, 1, 12);
        Modified := True;
      end;
    uaPaintTool: PaintOn := not PaintOn;
    uaColor:
      begin
        PaintColor := PickedColor;
        PaintOn := True;
      end;
    uaBrushDn: BrushR := EnsureRange(BrushR - 2, 2, 40);
    uaBrushUp: BrushR := EnsureRange(BrushR + 2, 2, 40);
    uaClearPaint:
      begin
        FillChar(PaintCells[0], PAINT_N, 0);
        Modified := True;
      end;
    uaBeltColor:
      begin
        BeltColor := BELT_COLORS[PickedColor];
        Modified := True;
      end;
    uaSetStart:
      begin
        CaptureStart;
        Modified := True;
        ResetAll;
        DemoT := 0;
        if ScriptLen > 0 then Mode := mPaused else Mode := mIdle;
      end;
    uaAddPulley: AddPulley;
    uaDelPulley: DeletePulley(SelNode);
    uaHook: HookPulley(SelNode);
    uaUnhook: UnhookPulley(SelNode);
    uaPulleyEdit: EditPulley(PulleyEditField, PulleyEditValue);
    uaGridChanged, uaImageChanged: Modified := True;
    uaImageOpen: DoOpenImage;
    uaImageBake: DoBakeImage;
    uaExportRoad: DoExportRoad;
    uaTheme:
      begin
        SetTheme(PickedTheme);
        SaveThemePref;
      end;
    uaImageClear:
      begin
        ClearBackground;
        ImagePath := '';
        Modified := True;
      end;
    uaSetPos:
      begin
        { ใช้ตำแหน่ง/รัศมีปัจจุบันของ pulley (ลากไปวางก่อนแล้วกดปุ่มนี้) }
        with Phases[Sel] do
          case kind of
            pkLine, pkMove: begin x := Nodes[node].x; y := Nodes[node].y; end;
            pkRadius: r := Nodes[node].r;
          end;
        Modified := True;
        PauseAt(PhaseStart(Sel) + Phases[Sel].dur);
      end;
  end;
  UpdateTitle;
end;

{ ปรับความหนาทีละนิด ไม่ให้รัศมีกระโดด (จำลอง belt ทุกก้าว) }
procedure EaseThickness;
var
  k: Integer;
begin
  k := 0;
  while (Abs(BeltTTarget - BeltT) > 1e-4) and (k < 5) do
  begin
    BeltT := BeltT + EnsureRange(BeltTTarget - BeltT, -0.1, 0.1);
    SimStep;
    Inc(k);
  end;
end;

procedure MoveBelt(dt: Single);
var
  k, c: Integer;
begin
  if not BeltRun or (BeltLen <= 1) then Exit;
  OffF := OffF + BeltSpeed * dt / BeltLen;
  OffF := OffF - Floor(OffF);
  for k := 0 to NodeCnt - 1 do
    for c := 0 to PathN - 1 do
      if Path[c].node = k then
      begin
        { จุดสัมผัสเดินตามมุม phi: อัตรา = -s * v / R }
        PulleyAng[k] := PulleyAng[k] - Path[c].s * BeltSpeed * dt / RadEff(Path[c]);
        Break;
      end;
end;

var
  E: TSDL_Event;
  hit, wheelNode: Integer;
  wheelDelta, dt, sx, sy: Single;
  lastTick, nowTick: QWord;
  act: TUiAction;
  vp: TSDL_Rect;
  ctrl, shift: Boolean;
  defX, defY, defR: array[0..DEF_COUNT - 1] of Single;

begin
  SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide,
                    exOverflow, exUnderflow, exPrecision]);

  if not SDL_Init(SDL_INIT_VIDEO) then
  begin
    // แอปแบบ GUI ไม่มี console จึงแจ้งผ่านกล่องข้อความแทน WriteLn
    SDL_ShowSimpleMessageBox(SDL_MESSAGEBOX_ERROR, 'Belt and Pulley Path',
      PAnsiChar('SDL_Init failed: ' + string(SDL_GetError)), nil);
    Halt(1);
  end;

  Win := SDL_CreateWindow('Belt and Pulley Path', WIN_W, WIN_H, 0);
  Ren := SDL_CreateRenderer(Win, nil);
  SDL_SetRenderVSync(Ren, 1);
  UiWin := Win;

  DlgFilters[0].Name := 'Belt animation (*.txt)';
  DlgFilters[0].pattern := 'txt';
  DlgFilters[1].Name := 'All files';
  DlgFilters[1].pattern := '*';
  ImgFilters[0].Name := 'Images (png, jpg, bmp, gif, webp, tga)';
  ImgFilters[0].pattern := 'png;jpg;jpeg;bmp;gif;webp;tga;tif;tiff';
  ImgFilters[1].Name := 'All files';
  ImgFilters[1].pattern := '*';
  RoadFilters[0].Name := 'Road JSON (*.json)';
  RoadFilters[0].pattern := 'json';
  RoadFilters[1].Name := 'Road points CSV (*.csv)';
  RoadFilters[1].pattern := 'csv';
  PngFilters[0].Name := 'PNG image (*.png)';
  PngFilters[0].pattern := 'png';

  { ฉากตั้งต้นของเอกสารใหม่ = รูปทรงเริ่มต้นเดิม }
  for hit := 0 to DEF_COUNT - 1 do
  begin
    defX[hit] := INIT_NODES[hit].x;
    defY[hit] := INIT_NODES[hit].y;
    defR[hit] := INIT_NODES[hit].r;
  end;
  InitScript(defX, defY, defR);

  { ธีมที่ใช้ครั้งก่อน แล้วเริ่มด้วยเอกสารใหม่ }
  LoadThemePref;
  { เริ่มโปรแกรมด้วยเอกสารใหม่ (เหมือนเลือก File > New) }
  ClearScript(True);
  DocFile := '';
  AfterLoad;
  Mode := mIdle;
  UpdateTitle;

  Running := True;
  lastTick := SDL_GetTicks;

  while Running do
  begin
    wheelNode := -1;
    wheelDelta := 0;
    while SDL_PollEvent(@E) do
    begin
      act := uaNone;
      case E._type of
        SDL_EVENT_QUIT:
          if ConfirmDiscard then Running := False;

        SDL_EVENT_TEXT_INPUT:
          UiTextInput(string(E.text.Text));

        SDL_EVENT_KEY_DOWN:
          begin
            ctrl := (E.key.mod_ and SDL_KMOD_CTRL) <> 0;
            shift := (E.key.mod_ and SDL_KMOD_SHIFT) <> 0;
            if ctrl then
              case E.key.key of
                SDLK_N: act := uaNew;
                SDLK_O: act := uaOpen;
                SDLK_S: if shift then act := uaSaveAs else act := uaSave;
                SDLK_E: act := uaExportRoad;
              end
            else if not UiKey(E.key.key, shift, act) then
              case E.key.key of
                SDLK_ESCAPE: act := uaExit;
                SDLK_D: ShowDebug := not ShowDebug;
                SDLK_R: act := uaStop;
                SDLK_SPACE: act := uaPlay;
                SDLK_B: act := uaBeltRun;
                SDLK_P: act := uaPaintTool;
              end;
          end;

        SDL_EVENT_MOUSE_MOTION:
          begin
            sx := E.motion.x;
            sy := E.motion.y - SCENE_Y;
            MouseX := sx;
            MouseY := sy;
            UiMouseMove(E.motion.x, E.motion.y, (E.motion.state and SDL_BUTTON_LMASK) <> 0, act);
            if ImgDrag then
            begin
              ImageOffX := ImgOff0X + (sx - ImgDragX0);
              ImageOffY := ImgOff0Y + (sy - ImgDragY0);
            end;
            if Painting >= 0 then
              PaintAt(MouseX, MouseY, Painting);
          end;

        SDL_EVENT_MOUSE_BUTTON_DOWN:
          if (E.button.button = SDL_BUTTON_LEFT) and not UiMenuOpen
             and not UiOverFloat(E.button.x, E.button.y)
             and OnViewPill(E.button.x, E.button.y - SCENE_Y) then
            ShowDebug := not ShowDebug
          else if ImageMoveOn and (BgTex <> nil) and (E.button.button = SDL_BUTTON_LEFT)
             and (E.button.x >= DBG_X) and (E.button.x < DBG_X + DBG_W)
             and (E.button.y >= SCENE_Y + DBG_Y) and (E.button.y < SCENE_Y + DBG_Y + DBG_H)
             and not UiMenuOpen and not UiOverFloat(E.button.x, E.button.y) then
          begin
            { โหมด MOVE ของแผง IMAGE: ลากเพื่อเลื่อนภาพพื้นหลัง }
            ImgDrag := True;
            ImgDragX0 := E.button.x;
            ImgDragY0 := E.button.y - SCENE_Y;
            ImgOff0X := ImageOffX;
            ImgOff0Y := ImageOffY;
          end
          else if PaintOn and (E.button.button in [SDL_BUTTON_LEFT, SDL_BUTTON_RIGHT])
             and (E.button.y >= SCENE_Y) and (E.button.y < SCENE_Y + DBG_Y + DBG_H)
             and (E.button.x < DBG_X + DBG_W) and not UiMenuOpen
             and not UiOverFloat(E.button.x, E.button.y) then
          begin
            { เครื่องมือทาสี: ซ้าย = ทาด้วยสีที่เลือก, ขวา = ลบ }
            if E.button.button = SDL_BUTTON_LEFT then Painting := PaintColor else Painting := 0;
            PaintAt(E.button.x, E.button.y - SCENE_Y, Painting);
          end
          else if E.button.button = SDL_BUTTON_LEFT then
          begin
            if not UiMouseDown(E.button.x, E.button.y, act) then
            begin
              sx := E.button.x;
              sy := E.button.y - SCENE_Y;
              hit := PickNode(sx, sy);
              if (sx >= DBG_X) and (sx < DBG_X + DBG_W) and (sy >= DBG_Y) and (sy < DBG_Y + DBG_H) then
                SelNode := hit;            // คลิกที่ว่าง = ยกเลิกการเลือก
              if hit >= 0 then
              begin
                if Mode in [mPlay, mPaused] then Mode := mIdle;
                DragIdx := hit;
                if Length(Phases) = 0 then Modified := True;
                DragDX := Nodes[hit].x - sx;
                DragDY := Nodes[hit].y - sy;
              end;
            end;
          end;

        SDL_EVENT_MOUSE_BUTTON_UP:
          begin
            Painting := -1;
            if ImgDrag then
            begin
              ImgDrag := False;
              Modified := True;
            end;
            if E.button.button = SDL_BUTTON_LEFT then
            begin
              if DragIdx >= 0 then NeedCapture := True;
              DragIdx := -1;
              UiMouseUp;
            end;
          end;

        SDL_EVENT_MOUSE_WHEEL:
          if not UiWheel(E.wheel.mouse_x, E.wheel.mouse_y, E.wheel.y,
                         (SDL_GetModState and SDL_KMOD_SHIFT) <> 0, act) then
          begin
            hit := PickNode(MouseX, MouseY);
            if hit >= 0 then
            begin
              if Mode in [mPlay, mPaused] then Mode := mIdle;
              wheelNode := hit;
              NeedCapture := True;
              if Length(Phases) = 0 then Modified := True;
              wheelDelta := wheelDelta + E.wheel.y * 3;
            end;
          end;
      end;
      if act <> uaNone then
        HandleAction(act);
    end;
    PollDialog;

    nowTick := SDL_GetTicks;
    dt := Min(0.05, (nowTick - lastTick) / 1000);
    lastTick := nowTick;

    EaseThickness;
    MoveBelt(dt);
    if Painting >= 0 then
      PaintAt(MouseX, MouseY, Painting);    // ทาต่อเนื่องแม้เมาส์นิ่งแต่ belt วิ่ง

    case Mode of
      mPlay: UpdatePlay(dt);
      mPaused: FollowScript(DemoT);
      mIdle: UpdateManual(wheelNode, wheelDelta);
      mRecord:
        begin
          UpdateManual(wheelNode, wheelDelta);
          RecAcc := RecAcc + dt;
          if RecAcc >= REC_SAMPLE then
            RecordSample;
          DemoT := ScriptLen + RecHold + RecAcc;
        end;
    end;

    { ยังไม่มีแอนิเมชัน: สิ่งที่แก้บนจอคือฉากเริ่มต้น }
    if NeedCapture and (Mode = mIdle) and (Length(Phases) = 0) then
      CaptureStart;
    NeedCapture := False;

    BuildPoly;

    { สถานะให้แผงแสดง }
    UiPlaying := Mode = mPlay;
    UiRecording := Mode = mRecord;
    UiLoop := LoopOn;
    UiTime := DemoT;
    UiModified := Modified;
    UiDocName := ExtractFileName(DocFile);
    UiBeltRun := BeltRun;
    UiSpeed := BeltSpeed;
    UiThick := BeltTTarget;
    UiPaint := PaintOn;
    UiColor := PaintColor;
    UiBrush := BrushR;
    UiBeltColor := BeltColor;
    UiNodeCount := NodeCnt;
    UiMaxNodes := MAX_NODES;
    if SelNode >= NodeCnt then SelNode := -1;
    UiSelNode := SelNode;
    if SelNode >= 0 then
    begin
      UiSelX := Nodes[SelNode].x;
      UiSelY := Nodes[SelNode].y;
      UiSelR := Nodes[SelNode].r;
      UiSelInBelt := NodeInPath(SelNode);
    end;
    UiImgName := ExtractFileName(ImagePath);
    UiImgW := Round(BgW);
    UiImgH := Round(BgH);
    UiImgMissing := BgMissing;
    case Mode of
      mPlay: UiStatus := 'PLAYING';
      mPaused: UiStatus := 'PAUSED';
      mRecord: UiStatus := 'RECORDING - drag pulleys';
    else
      UiStatus := 'EDIT';
    end;

    Paper;
    SDL_RenderClear(Ren);
    vp.x := 0; vp.y := SCENE_Y; vp.w := WIN_W; vp.h := SCENE_H;
    SDL_SetRenderViewport(Ren, @vp);
    DrawTicks;
    DrawDebugPanel;
    DrawRenderPanel;
    DrawTopoPanel;
    SDL_SetRenderViewport(Ren, nil);
    DrawBeltPanel;
    DrawPulleyPanel;
    DrawAnimPanel;
    DrawFloatPanels;
    DrawMenuBar;
    DrawMenuDropdown;
    SDL_RenderPresent(Ren);
  end;

  ClearBackground;
  SDL_DestroyRenderer(Ren);
  SDL_DestroyWindow(Win);
  SDL_Quit;
end.
