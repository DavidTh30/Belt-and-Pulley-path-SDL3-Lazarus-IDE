unit AnimPanel;

{ เมนู File และแผง ANIMATION (ปุ่มเล่น/อัด, timeline, รายการคำสั่งที่แก้ไขได้)
  หน่วยนี้จัดการแค่การวาดและการคลิก/พิมพ์ แล้วส่ง action กลับให้โปรแกรมหลักทำงานจริง }

{$mode objfpc}{$H+}

interface

uses
  SDL3, Gfx, DemoScript;

const
  MENU_H = 24;
  { แผง BELT แยกจากแถบเมนู อยู่ใต้เมนู }
  BP_X = 20;
  BP_Y = MENU_H + 6;
  BP_W = 1240;
  BP_H = 30;
  SCENE_TOP = MENU_H + 30;       // ฉาก (แผง DEBUG/RENDER/TOPO) เริ่มที่นี่
  AP_X = 20;
  AP_Y = SCENE_TOP + 714;
  { แผง PULLEY: มุมขวาล่างของฉาก ใต้แผง Topology }
  PP_X = 893;
  PP_Y = SCENE_TOP + 589;
  PP_W = 367;
  PP_H = 104;
  AP_W = 1240;
  AP_H = 200;

type
  TUiAction = (uaNone, uaNew, uaOpen, uaSave, uaExit,
               uaPlay, uaRec, uaStop, uaLoop, uaScrub, uaSelect, uaEdited,
               uaAddLine, uaAddMove, uaAddOrbit, uaAddRadius, uaAddHold,
               uaDelete, uaUp, uaDown, uaSetPos,
               uaBeltRun, uaSpeedDn, uaSpeedUp, uaThickDn, uaThickUp,
               uaPaintTool, uaColor, uaBrushDn, uaBrushUp, uaClearPaint,
               uaBeltColor, uaSetStart,
               uaAddPulley, uaDelPulley, uaHook, uaUnhook, uaPulleyEdit,
               uaGridChanged, uaImageOpen, uaImageClear, uaImageChanged);

const
  { สีของพู่กัน: 0 = ยางลบ }
  PAINT_COLORS: array[0..6] of TRgb = (
    (r: 252; g: 252; b: 250), (r: 215; g: 45; b: 35), (r: 235; g: 140; b: 20),
    (r: 225; g: 195; b: 20), (r: 40; g: 150; b: 70), (r: 35; g: 95; b: 200),
    (r: 22; g: 22; b: 22));
  { สีพื้นของ belt }
  BELT_COLORS: array[0..5] of TRgb = (
    (r: 234; g: 234; b: 228), (r: 196; g: 196; b: 188), (r: 120; g: 120; b: 114),
    (r: 45; g: 45; b: 45), (r: 172; g: 122; b: 72), (r: 110; g: 142; b: 192));

var
  UiWin: PSDL_Window;
  { สถานะที่โปรแกรมหลักตั้งให้ก่อนวาด }
  UiPlaying, UiRecording, UiLoop, UiModified: Boolean;
  UiTime: Single;
  UiStatus, UiDocName: string;
  { สถานะของแผง }
  Sel: Integer = -1;        // แถวคำสั่งที่เลือก
  ScrubT: Single = 0;       // เวลาที่คลิกบน timeline (ใช้กับ uaScrub)
  { แถบเครื่องมือ belt (โปรแกรมหลักตั้งค่าให้ก่อนวาด) }
  UiBeltRun, UiPaint: Boolean;
  UiSpeed, UiThick, UiBrush: Single;
  UiColor: Integer = 1;
  UiBeltColor: TRgb;
  { แผง PULLEY }
  UiNodeCount, UiMaxNodes: Integer;
  UiSelNode: Integer = -1;
  UiSelX, UiSelY, UiSelR: Single;
  UiSelInBelt: Boolean;
  PulleyEditField: Integer;   // 0 = x, 1 = y, 2 = r (ใช้กับ uaPulleyEdit)
  PulleyEditValue: Single;
  { แผง IMAGE (โปรแกรมหลักตั้งให้) }
  UiImgName: string;
  UiImgW, UiImgH: Integer;
  UiImgMissing: Boolean;
  { แผงลอย GRID / IMAGE (เปิดจากเมนู Panel) }
  GridPanelOn: Boolean = False;
  ImagePanelOn: Boolean = False;
  PickedColor: Integer = 1;  // สีที่คลิก (ใช้กับ uaColor)

procedure DrawMenuBar;
procedure DrawBeltPanel;
procedure DrawPulleyPanel;
procedure DrawMenuDropdown;
procedure DrawFloatPanels;
function UiOverFloat(x, y: Single): Boolean;
procedure DrawAnimPanel;

{ คืน True ถ้าเหตุการณ์ถูกใช้โดยเมนู/แผง }
function UiMouseDown(x, y: Single; out act: TUiAction): Boolean;
function UiMouseMove(x, y: Single; leftDown: Boolean; out act: TUiAction): Boolean;
procedure UiMouseUp;
function UiWheel(x, y, dy: Single; shift: Boolean; out act: TUiAction): Boolean;
function UiKey(key: TSDL_Keycode; shift: Boolean; out act: TUiAction): Boolean;
procedure UiTextInput(const s: string);
function UiEditing: Boolean;
function UiMenuOpen: Boolean;
procedure UiCloseMenu;
procedure UiCancelEdit;
function UiCommitEdit: Boolean;
procedure EnsureSelVisible;

implementation

uses
  SysUtils, Math;

type
  TField = (fNone, fNode, fX, fY, fCenter, fTurns, fR, fDur);

const
  { เมนู }
  MENU_TITLE: array[0..1] of string = ('File', 'Panel');
  MENU_X: array[0..1] of Single = (4, 56);
  MENU_W: array[0..1] of Single = (48, 56);
  MENU_ITEMS: array[0..4] of string = ('New', 'Open...', 'Save', '', 'Exit');
  MENU_KEYS: array[0..4] of string = ('Ctrl+N', 'Ctrl+O', 'Ctrl+S', '', 'Alt+F4');
  MENU_ACT: array[0..4] of TUiAction = (uaNew, uaOpen, uaSave, uaNone, uaExit);
  PANEL_ITEMS: array[0..1] of string = ('Grid', 'Image');
  DD_W = 200;
  DD_ROW = 22;

  { แผง }
  TB_Y = AP_Y + 12;               // แถวปุ่ม
  TL_X = AP_X + 16;               // timeline
  TL_Y = AP_Y + 40;
  TL_W = AP_W - 32;
  TL_H = 22;
  LS_X = AP_X + 16;               // รายการคำสั่ง
  LS_Y = AP_Y + 74;
  LS_W = 860;
  ROW_H = 16;
  ROWS = 7;
  CELL_X0 = 112;                  // ช่องค่าเริ่มที่ระยะนี้จากซ้ายของแถว
  CELL_W = 150;
  VAL_OFS = 60;
  VAL_W = 80;
  BT_X = AP_X + 900;              // ปุ่มแก้ไข
  BT_Y = LS_Y;
  BT_W = 104;
  BT_H = 22;
  BT_GAP = 8;

  EDIT_BTN: array[0..9] of string = ('+LINE', '+MOVE', '+ORBIT', '+RADIUS', '+HOLD', 'DELETE',
                                     'UP', 'DOWN', 'SET POS', 'SET START');
  EDIT_ACT: array[0..9] of TUiAction = (uaAddLine, uaAddMove, uaAddOrbit, uaAddRadius, uaAddHold,
                                        uaDelete, uaUp, uaDown, uaSetPos, uaSetStart);

  { ปุ่มควบคุม: PLAY, STOP, REC, LOOP }
  TR_X: array[0..3] of Single = (AP_X + 124, AP_X + 160, AP_X + 196, AP_X + 254);
  TR_W: array[0..3] of Single = (30, 30, 52, 52);
  TR_ACT: array[0..3] of TUiAction = (uaPlay, uaStop, uaRec, uaLoop);

var
  MenuIdx: Integer = -1;        // เมนูที่เปิดอยู่ (-1 = ไม่มี)
  MenuHover: Integer = -1;
  MouseX, MouseY: Single;
  ListTop: Integer = 0;
  Scrubbing: Boolean = False;
  EditRow: Integer = -1;       // -1 = ไม่ได้แก้, PULLEY_ROW = แก้ค่าในแผง PULLEY
  CommitAct: TUiAction = uaEdited;
  EditField: TField = fNone;
  EditBuf: string = '';
  EditFresh: Boolean = False;   // ยังไม่ได้พิมพ์: ตัวแรกที่พิมพ์จะแทนค่าเดิม
  FS: TFormatSettings;

{ ---------- ช่วยเหลือ ---------- }

function InRect(x, y, rx, ry, rw, rh: Single): Boolean;
begin
  Result := (x >= rx) and (x < rx + rw) and (y >= ry) and (y < ry + rh);
end;

function Fields(kind: TPhaseKind; i: Integer): TField;
const
  F_LINE: array[0..3] of TField = (fNode, fX, fY, fDur);
  F_ORBIT: array[0..3] of TField = (fNode, fCenter, fTurns, fDur);
  F_RADIUS: array[0..3] of TField = (fNode, fR, fDur, fNone);
  F_HOLD: array[0..3] of TField = (fDur, fNone, fNone, fNone);
begin
  case kind of
    pkLine, pkMove: Result := F_LINE[i];
    pkOrbit: Result := F_ORBIT[i];
    pkRadius: Result := F_RADIUS[i];
  else
    Result := F_HOLD[i];
  end;
end;

function FieldName(f: TField): string;
begin
  case f of
    fNode: Result := 'node';
    fX: Result := 'x';
    fY: Result := 'y';
    fCenter: Result := 'center';
    fTurns: Result := 'turns';
    fR: Result := 'radius';
    fDur: Result := 'sec';
  else
    Result := '';
  end;
end;

function FieldText(const ph: TPhase; f: TField): string;
begin
  case f of
    fNode: Result := IntToStr(ph.node);
    fX: Result := FormatFloat('0.#', ph.x, FS);
    fY: Result := FormatFloat('0.#', ph.y, FS);
    fCenter: Result := IntToStr(ph.center);
    fTurns: Result := FormatFloat('0.##', ph.turns, FS);
    fR: Result := FormatFloat('0.#', ph.r, FS);
    fDur: Result := FormatFloat('0.00', ph.dur, FS);
  else
    Result := '';
  end;
end;

procedure SetField(var ph: TPhase; f: TField; v: Double);
begin
  case f of
    fNode: ph.node := Round(v);
    fX: ph.x := v;
    fY: ph.y := v;
    fCenter: ph.center := Round(v);
    fTurns: ph.turns := v;
    fR: ph.r := v;
    fDur: ph.dur := v;
  end;
  ClampPhase(ph);
end;

function GetField(const ph: TPhase; f: TField): Double;
begin
  case f of
    fNode: Result := ph.node;
    fX: Result := ph.x;
    fY: Result := ph.y;
    fCenter: Result := ph.center;
    fTurns: Result := ph.turns;
    fR: Result := ph.r;
    fDur: Result := ph.dur;
  else
    Result := 0;
  end;
end;

function FieldStep(f: TField; shift: Boolean): Double;
begin
  case f of
    fNode, fCenter: Result := 1;
    fX, fY: if shift then Result := 10 else Result := 1;
    fTurns: if shift then Result := 1 else Result := 0.25;
    fR: if shift then Result := 5 else Result := 1;
    fDur: if shift then Result := 0.5 else Result := 0.1;
  else
    Result := 0;
  end;
end;

function KindLabel(const ph: TPhase): string;
begin
  case ph.kind of
    pkLine: Result := 'L' + IntToStr(ph.node);
    pkMove: Result := 'M' + IntToStr(ph.node);
    pkOrbit: Result := 'O' + IntToStr(ph.node) + '>' + IntToStr(ph.center);
    pkRadius: Result := 'R' + IntToStr(ph.node);
  else
    Result := 'H';
  end;
end;

const
  PULLEY_ROW = -2;
  P_FIELDS: array[0..2] of TField = (fX, fY, fR);

function UiEditing: Boolean;
begin
  Result := EditRow <> -1;
end;

function PulleyFieldText(f: TField): string;
begin
  case f of
    fX: Result := FormatFloat('0.#', UiSelX, FS);
    fY: Result := FormatFloat('0.#', UiSelY, FS);
  else
    Result := FormatFloat('0.#', UiSelR, FS);
  end;
end;

function PulleyFieldIndex(f: TField): Integer;
begin
  case f of
    fX: Result := 0;
    fY: Result := 1;
  else
    Result := 2;
  end;
end;

procedure StartPulleyEdit(f: TField);
begin
  if UiSelNode < 0 then Exit;
  EditRow := PULLEY_ROW;
  EditField := f;
  EditBuf := PulleyFieldText(f);
  EditFresh := True;
  SDL_StartTextInput(UiWin);
end;

function UiMenuOpen: Boolean;
begin
  Result := MenuIdx >= 0;
end;

procedure UiCloseMenu;
begin
  MenuIdx := -1;
  MenuHover := -1;
end;

procedure EnsureSelVisible;
begin
  if Sel < 0 then Exit;
  if Sel < ListTop then ListTop := Sel;
  if Sel >= ListTop + ROWS then ListTop := Sel - ROWS + 1;
  ListTop := Max(0, Min(ListTop, Length(Phases) - ROWS));
end;

procedure StartEdit(row: Integer; f: TField);
begin
  if f = fNone then Exit;
  EditRow := row;
  EditField := f;
  EditBuf := FieldText(Phases[row], f);
  EditFresh := True;
  SDL_StartTextInput(UiWin);
end;

procedure UiCancelEdit;
begin
  if EditRow <> -1 then
    SDL_StopTextInput(UiWin);
  EditRow := -1;
  EditField := fNone;
end;

function UiCommitEdit: Boolean;
var
  v: Double;
begin
  Result := False;
  if EditRow = -1 then Exit;
  if EditRow = PULLEY_ROW then
  begin
    if TryStrToFloat(EditBuf, v, FS) then
    begin
      PulleyEditField := PulleyFieldIndex(EditField);
      PulleyEditValue := v;
      CommitAct := uaPulleyEdit;
      Result := True;
    end;
    UiCancelEdit;
    Exit;
  end;
  CommitAct := uaEdited;
  if (EditRow <= High(Phases)) and TryStrToFloat(EditBuf, v, FS) then
  begin
    SetField(Phases[EditRow], EditField, v);
    Recalc;
    Result := True;
  end;
  UiCancelEdit;
end;

procedure UiTextInput(const s: string);
var
  i: Integer;
begin
  if EditRow = -1 then Exit;
  if EditFresh then
  begin
    EditBuf := '';
    EditFresh := False;
  end;
  for i := 1 to Length(s) do
    if s[i] in ['0'..'9', '.', '-'] then
      EditBuf := EditBuf + s[i];
end;

{ ---------- เมนู ---------- }

type
  TTbItem = record
    x, w: Single;
    act: TUiAction;
    tag: Integer;
  end;

const
  TB_TOP = BP_Y + 6;
  TB_H = BP_H - 12;
  TB_ITEMS: array[0..21] of TTbItem = (
    (x: 88;  w: 62; act: uaBeltRun; tag: 0),       // 0
    (x: 156; w: 20; act: uaSpeedDn; tag: 0),       // 1
    (x: 252; w: 20; act: uaSpeedUp; tag: 0),       // 2
    (x: 346; w: 20; act: uaThickDn; tag: 0),       // 3
    (x: 400; w: 20; act: uaThickUp; tag: 0),       // 4
    (x: 498; w: 18; act: uaBeltColor; tag: 0),     // 5..10 สีพื้น belt
    (x: 520; w: 18; act: uaBeltColor; tag: 1),
    (x: 542; w: 18; act: uaBeltColor; tag: 2),
    (x: 564; w: 18; act: uaBeltColor; tag: 3),
    (x: 586; w: 18; act: uaBeltColor; tag: 4),
    (x: 608; w: 18; act: uaBeltColor; tag: 5),
    (x: 648; w: 58; act: uaPaintTool; tag: 0),     // 11
    (x: 714; w: 18; act: uaColor; tag: 0),         // 12..18 สีพู่กัน
    (x: 736; w: 18; act: uaColor; tag: 1),
    (x: 758; w: 18; act: uaColor; tag: 2),
    (x: 780; w: 18; act: uaColor; tag: 3),
    (x: 802; w: 18; act: uaColor; tag: 4),
    (x: 824; w: 18; act: uaColor; tag: 5),
    (x: 846; w: 18; act: uaColor; tag: 6),
    (x: 912; w: 20; act: uaBrushDn; tag: 0),       // 19
    (x: 964; w: 20; act: uaBrushUp; tag: 0),       // 20
    (x: 996; w: 52; act: uaClearPaint; tag: 0));   // 21

function ToolbarItemAt(x, y: Single): Integer;
var
  i: Integer;
begin
  Result := -1;
  for i := 0 to High(TB_ITEMS) do
    if InRect(x, y, TB_ITEMS[i].x, TB_TOP, TB_ITEMS[i].w, TB_H) then
      Exit(i);
end;

procedure SmallButton(const it: TTbItem; const s: string; active: Boolean);
var
  hover: Boolean;
begin
  hover := InRect(MouseX, MouseY, it.x, TB_TOP, it.w, TB_H);
  if active then
  begin
    Ink;
    FillRoundRect(it.x, TB_TOP, it.w, TB_H, 4);
    Paper;
  end
  else
  begin
    if hover then Col(222, 222, 216) else Paper;
    FillRoundRect(it.x, TB_TOP, it.w, TB_H, 4);
    Ink;
    StrokeRoundRect(it.x, TB_TOP, it.w, TB_H, 4);
  end;
  if s <> '' then
    Txt(it.x + (it.w - Length(s) * 8) / 2, TB_TOP + 5, s);
end;

procedure Swatch(const it: TTbItem; const c: TRgb; selected, eraser: Boolean);
begin
  if selected then
  begin
    Col(220, 90, 20);
    FillRoundRect(it.x - 2, TB_TOP - 2, it.w + 4, TB_H + 4, 4);
  end;
  Col(c.r, c.g, c.b);
  FillRoundRect(it.x, TB_TOP, it.w, TB_H, 3);
  Ink;
  StrokeRoundRect(it.x, TB_TOP, it.w, TB_H, 3);
  if eraser then
  begin
    Line(it.x + 4, TB_TOP + 4, it.x + it.w - 4, TB_TOP + TB_H - 4);
    Line(it.x + it.w - 4, TB_TOP + 4, it.x + 4, TB_TOP + TB_H - 4);
  end;
end;

function SameRgb(const a, b: TRgb): Boolean;
begin
  Result := (a.r = b.r) and (a.g = b.g) and (a.b = b.b);
end;

procedure DrawBeltPanel;
var
  i: Integer;
  it: TTbItem;
  cx, cy: Single;
begin
  Panel(BP_X, BP_Y, BP_W, BP_H);
  Pill(BP_X + 16, TB_TOP + 1, 'BELT', True);

  { วิ่ง/หยุด + ความเร็ว }
  it := TB_ITEMS[0];
  SmallButton(it, '', UiBeltRun);
  cx := it.x + 12;
  cy := TB_TOP + TB_H / 2;
  if UiBeltRun then
  begin
    Paper;
    FillRect(cx - 4, cy - 4, 8, 8);
    Txt(it.x + 22, TB_TOP + 5, 'STOP');
  end
  else
  begin
    Ink;
    Tri(cx - 4, cy - 5, cx - 4, cy + 5, cx + 5, cy);
    Flush;
    Txt(it.x + 22, TB_TOP + 5, 'RUN');
  end;
  SmallButton(TB_ITEMS[1], '-', False);
  Ink;
  Txt(180, TB_TOP + 5, Format('%4d px/s', [Round(UiSpeed)]));
  SmallButton(TB_ITEMS[2], '+', False);

  { ความหนา }
  Pill(288, TB_TOP + 1, 'THICK', False);
  SmallButton(TB_ITEMS[3], '-', False);
  Ink;
  Txt(374, TB_TOP + 5, Format('%2d', [Round(UiThick)]));
  SmallButton(TB_ITEMS[4], '+', False);

  { สีพื้น belt }
  Pill(436, TB_TOP + 1, 'COLOR', False);
  for i := 5 to 10 do
    Swatch(TB_ITEMS[i], BELT_COLORS[TB_ITEMS[i].tag], SameRgb(BELT_COLORS[TB_ITEMS[i].tag], UiBeltColor), False);

  { ทาสี }
  SmallButton(TB_ITEMS[11], 'PAINT', UiPaint);
  for i := 12 to 18 do
    Swatch(TB_ITEMS[i], PAINT_COLORS[TB_ITEMS[i].tag], UiPaint and (TB_ITEMS[i].tag = UiColor), TB_ITEMS[i].tag = 0);
  Col(110, 110, 105);
  Txt(876, TB_TOP + 5, 'size');
  SmallButton(TB_ITEMS[19], '-', False);
  Ink;
  Txt(936, TB_TOP + 5, Format('%3d', [Round(UiBrush)]));
  SmallButton(TB_ITEMS[20], '+', False);
  SmallButton(TB_ITEMS[21], 'CLEAR', False);

  Col(150, 150, 145);
  Txt(1062, TB_TOP + 5, 'B:run  P:paint');
end;

function MenuCount(m: Integer): Integer;
begin
  if m = 0 then Result := Length(MENU_ITEMS) else Result := Length(PANEL_ITEMS);
end;

function MenuText(m, i: Integer): string;
begin
  if m = 0 then Result := MENU_ITEMS[i] else Result := PANEL_ITEMS[i];
end;

function MenuKey(m, i: Integer): string;
begin
  Result := '';
  if m = 0 then Result := MENU_KEYS[i];
end;

{ รายการในเมนู Panel ที่ติ๊กอยู่ (แผงเปิดอยู่) }
function MenuChecked(m, i: Integer): Boolean;
begin
  Result := (m = 1) and (((i = 0) and GridPanelOn) or ((i = 1) and ImagePanelOn));
end;

function MenuTitleAt(x, y: Single): Integer;
var
  m: Integer;
begin
  Result := -1;
  for m := 0 to High(MENU_TITLE) do
    if InRect(x, y, MENU_X[m], 2, MENU_W[m], MENU_H - 4) then
      Exit(m);
end;

procedure DrawMenuBar;
var
  s: string;
  m: Integer;
begin
  Col(238, 238, 233);
  FillRect(0, 0, 1280, MENU_H);
  Col(170, 170, 165);
  Line(0, MENU_H - 0.5, 1280, MENU_H - 0.5);
  for m := 0 to High(MENU_TITLE) do
  begin
    if (MenuIdx = m) or InRect(MouseX, MouseY, MENU_X[m], 2, MENU_W[m], MENU_H - 4) then
    begin
      Ink;
      FillRoundRect(MENU_X[m], 3, MENU_W[m], MENU_H - 6, 4);
      Paper;
    end
    else
      Ink;
    Txt(MENU_X[m] + (MENU_W[m] - Length(MENU_TITLE[m]) * 8) / 2, 8, MENU_TITLE[m]);
  end;
  s := UiDocName;
  if s = '' then s := 'untitled';
  if UiModified then s := s + ' *';
  Col(110, 110, 105);
  Txt(1280 - 12 - Length(s) * 8, 8, s);
end;

procedure DrawMenuDropdown;
var
  i, n: Integer;
  x, y, h: Single;
  t: string;
begin
  if MenuIdx < 0 then Exit;
  x := MENU_X[MenuIdx];
  n := MenuCount(MenuIdx);
  h := n * DD_ROW + 8;
  Col(200, 200, 195);
  FillRoundRect(x + 3, MENU_H + 3, DD_W, h, 6);     // เงา
  Paper;
  FillRoundRect(x, MENU_H, DD_W, h, 6);
  Ink;
  StrokeRoundRect(x, MENU_H, DD_W, h, 6);
  for i := 0 to n - 1 do
  begin
    y := MENU_H + 4 + i * DD_ROW;
    t := MenuText(MenuIdx, i);
    if t = '' then
    begin
      Col(190, 190, 185);
      Line(x + 8, y + DD_ROW / 2, x + DD_W - 8, y + DD_ROW / 2);
      Continue;
    end;
    if i = MenuHover then
    begin
      Ink;
      FillRoundRect(x + 4, y, DD_W - 8, DD_ROW, 4);
      Paper;
    end
    else
      Ink;
    if MenuIdx = 1 then
    begin
      { ช่องติ๊ก }
      StrokeRect(x + 12, y + 6, 10, 10);
      if MenuChecked(MenuIdx, i) then
      begin
        Line(x + 14, y + 11, x + 17, y + 14);
        Line(x + 17, y + 14, x + 21, y + 7);
      end;
      Txt(x + 30, y + 7, t);
    end
    else
      Txt(x + 14, y + 7, t);
    if i <> MenuHover then Col(130, 130, 125);
    Txt(x + DD_W - 14 - Length(MenuKey(MenuIdx, i)) * 8, y + 7, MenuKey(MenuIdx, i));
  end;
end;

function MenuItemAt(x, y: Single): Integer;
var
  i, n: Integer;
  mx: Single;
begin
  Result := -1;
  if MenuIdx < 0 then Exit;
  mx := MENU_X[MenuIdx];
  n := MenuCount(MenuIdx);
  if not InRect(x, y, mx, MENU_H, DD_W, n * DD_ROW + 8) then Exit;
  i := Floor((y - MENU_H - 4) / DD_ROW);
  if (i >= 0) and (i < n) and (MenuText(MenuIdx, i) <> '') then
    Result := i;
end;

{ ---------- แผง ---------- }

procedure Button(x, y, w, h: Single; const s: string; active, enabled: Boolean);
var
  hover: Boolean;
begin
  hover := enabled and InRect(MouseX, MouseY, x, y, w, h);
  if active then
  begin
    Ink;
    FillRoundRect(x, y, w, h, 5);
    Paper;
  end
  else
  begin
    if hover then Col(228, 228, 222) else Paper;
    FillRoundRect(x, y, w, h, 5);
    if enabled then Ink else Col(185, 185, 180);
    StrokeRoundRect(x, y, w, h, 5);
  end;
  if s <> '' then
    Txt(x + (w - Length(s) * 8) / 2, y + (h - 8) / 2, s);
end;

procedure DrawTransport;
var
  i: Integer;
  x, y, w, h, cx, cy: Single;
  active, enabled: Boolean;
begin
  y := TB_Y - 2;
  h := 20;
  for i := 0 to 3 do
  begin
    x := TR_X[i];
    w := TR_W[i];
    case i of
      0: active := UiPlaying;
      2: active := UiRecording;
      3: active := UiLoop;
    else
      active := False;
    end;
    enabled := (i <> 0) or not UiRecording;
    if i = 3 then
    begin
      Button(x, y, w, h, 'LOOP', active, True);
      Continue;
    end;
    Button(x, y, w, h, '', active, enabled);
    cx := x + w / 2;
    cy := y + h / 2;
    if active then Paper else if enabled then Ink else Col(185, 185, 180);
    case i of
      0:
        if UiPlaying then
        begin
          FillRect(cx - 5, cy - 5, 3.5, 10);    // pause
          FillRect(cx + 1.5, cy - 5, 3.5, 10);
        end
        else
        begin
          Tri(cx - 4, cy - 6, cx - 4, cy + 6, cx + 6, cy);   // play
          Flush;
        end;
      1: FillRect(cx - 5, cy - 5, 10, 10);                  // stop
      2:
        begin
          Col(215, 45, 35);                                  // rec
          Disc(x + 12, cy, 4.5);
          if active then Paper else Ink;
          Txt(x + 21, cy - 4, 'REC');
        end;
    end;
  end;
end;

procedure DrawTimeline;
var
  total, x0, x1, t, px: Single;
  i: Integer;
  s: string;
begin
  total := Max(ScriptLen, UiTime);
  if total < 1 then total := 1;
  Col(244, 244, 240);
  FillRect(TL_X, TL_Y, TL_W, TL_H);
  t := 0;
  for i := 0 to High(Phases) do
  begin
    x0 := TL_X + t / total * TL_W;
    t := t + Phases[i].dur;
    x1 := TL_X + t / total * TL_W;
    if i = Sel then Ink
    else if Phases[i].kind = pkHold then Col(236, 236, 231)
    else if Odd(i) then Col(214, 214, 208)
    else Col(226, 226, 220);
    FillRect(x0, TL_Y, Max(1, x1 - x0), TL_H);
    Col(160, 160, 155);
    Line(x1, TL_Y, x1, TL_Y + TL_H);
    s := KindLabel(Phases[i]);
    if x1 - x0 >= Length(s) * 8 + 6 then
    begin
      if i = Sel then Paper else Col(60, 60, 55);
      Txt(x0 + (x1 - x0 - Length(s) * 8) / 2, TL_Y + 7, s);
    end;
  end;
  Col(70, 70, 70);
  StrokeRect(TL_X, TL_Y, TL_W, TL_H);
  { หัวเล่น }
  px := TL_X + EnsureRange(UiTime / total, 0, 1) * TL_W;
  if UiRecording then Col(215, 45, 35) else Col(220, 90, 20);
  FillRect(px - 1, TL_Y - 3, 2, TL_H + 6);
  Tri(px - 5, TL_Y - 7, px + 5, TL_Y - 7, px, TL_Y - 1);
  Flush;
end;

procedure DrawList;
var
  r, i, c: Integer;
  y, cx: Single;
  ph: TPhase;
  f: TField;
  s: string;
begin
  Col(250, 250, 247);
  FillRect(LS_X, LS_Y, LS_W, ROWS * ROW_H + 2);
  Col(200, 200, 195);
  StrokeRect(LS_X, LS_Y, LS_W, ROWS * ROW_H + 2);
  if Length(Phases) = 0 then
  begin
    Col(150, 150, 145);
    Txt(LS_X + 10, LS_Y + 10, 'No commands. Press REC and drag pulleys, or use +LINE / +ORBIT ...');
    Exit;
  end;
  for r := 0 to ROWS - 1 do
  begin
    i := ListTop + r;
    if i > High(Phases) then Break;
    ph := Phases[i];
    y := LS_Y + 1 + r * ROW_H;
    if i = Sel then
    begin
      Col(228, 228, 220);
      FillRect(LS_X + 1, y, LS_W - 2, ROW_H);
    end;
    Col(150, 150, 145);
    Txt(LS_X + 6, y + 4, Format('%3d', [i]));
    Ink;
    Txt(LS_X + 44, y + 4, UpperCase(KIND_NAME[ph.kind]));
    for c := 0 to 3 do
    begin
      f := Fields(ph.kind, c);
      if f = fNone then Break;
      cx := LS_X + CELL_X0 + c * CELL_W;
      Col(140, 140, 135);
      Txt(cx, y + 4, FieldName(f));
      if (i = EditRow) and (f = EditField) then
      begin
        Paper;
        FillRect(cx + VAL_OFS - 3, y + 1, VAL_W, ROW_H - 2);
        Col(220, 90, 20);
        StrokeRect(cx + VAL_OFS - 3, y + 1, VAL_W, ROW_H - 2);
        s := EditBuf;
        if EditFresh then
        begin
          Col(220, 90, 20);                 // ค่าเดิมถูกเลือกไว้ พิมพ์แล้วแทนที่
          FillRect(cx + VAL_OFS - 1, y + 3, Length(s) * 8 + 2, 11);
          Paper;
        end
        else
        begin
          Ink;
          if (SDL_GetTicks div 500) mod 2 = 0 then s := s + '_';
        end;
        Txt(cx + VAL_OFS, y + 4, s);
      end
      else
      begin
        if InRect(MouseX, MouseY, cx + VAL_OFS - 3, y, VAL_W, ROW_H) and not UiRecording then
        begin
          Col(200, 200, 195);
          StrokeRect(cx + VAL_OFS - 3, y + 1, VAL_W, ROW_H - 2);
        end;
        Ink;
        Txt(cx + VAL_OFS, y + 4, FieldText(ph, f));
      end;
    end;
    Col(150, 150, 145);
    Txt(LS_X + LS_W - 80, y + 4, '@' + FormatFloat('0.00', PhaseStart(i), FS) + 's');
  end;
  { แถบเลื่อน }
  if Length(Phases) > ROWS then
  begin
    Col(200, 200, 195);
    FillRect(LS_X + LS_W - 5, LS_Y + 2 + ListTop / Length(Phases) * ROWS * ROW_H, 3,
             Max(6, ROWS / Length(Phases) * ROWS * ROW_H));
  end;
end;

procedure DrawEditButtons;
var
  i: Integer;
  x, y: Single;
  enabled: Boolean;
begin
  for i := 0 to High(EDIT_BTN) do
  begin
    x := BT_X + (i mod 3) * (BT_W + BT_GAP);
    y := BT_Y + (i div 3) * (BT_H + BT_GAP);
    enabled := not UiRecording;
    if (EDIT_ACT[i] in [uaDelete, uaUp, uaDown, uaSetPos]) and ((Sel < 0) or (Sel > High(Phases))) then
      enabled := False;
    Button(x, y, BT_W, BT_H, EDIT_BTN[i], False, enabled);
  end;
end;

const
  PF_Y = PP_Y + 38;                 // แถวช่องค่า
  PF_X: array[0..2] of Single = (PP_X + 16, PP_X + 126, PP_X + 236);
  PF_LABEL: array[0..2] of string = ('x', 'y', 'r');
  PF_BOX = 14;                      // ช่องค่าเริ่มหลังป้าย
  PF_W = 84;
  PB_Y = PP_Y + 68;                 // แถวปุ่ม
  PB_W = 80;
  PB_GAP = 7;
  PB_TEXT: array[0..3] of string = ('+ ADD', 'DELETE', 'HOOK', 'UNHOOK');
  PB_ACT: array[0..3] of TUiAction = (uaAddPulley, uaDelPulley, uaHook, uaUnhook);

function PulleyButtonEnabled(i: Integer): Boolean;
begin
  if UiRecording then Exit(False);
  case i of
    0: Result := UiNodeCount < UiMaxNodes;
    1: Result := UiSelNode >= 0;
    2: Result := (UiSelNode >= 0) and not UiSelInBelt and (UiNodeCount >= 2);
  else
    Result := (UiSelNode >= 0) and UiSelInBelt;
  end;
end;

procedure DrawPulleyPanel;
var
  i: Integer;
  bx, v: Single;
  s: string;
begin
  Panel(PP_X, PP_Y, PP_W, PP_H);
  Pill(PP_X + 16, PP_Y + 10, 'PULLEY', True);
  Ink;
  Txt(PP_X + 92, PP_Y + 14, Format('%d / %d', [UiNodeCount, UiMaxNodes]));
  if UiSelNode >= 0 then
  begin
    s := 'selected ' + IntToStr(UiSelNode);
    if UiSelInBelt then s := s + ' (on belt)';
    Col(220, 90, 20);
  end
  else
  begin
    s := 'click a pulley to select';
    Col(150, 150, 145);
  end;
  Txt(PP_X + PP_W - 16 - Length(s) * 8, PP_Y + 14, s);

  for i := 0 to 2 do
  begin
    bx := PF_X[i] + PF_BOX;
    Col(140, 140, 135);
    Txt(PF_X[i], PF_Y + 5, PF_LABEL[i]);
    if UiSelNode < 0 then
    begin
      Col(225, 225, 220);
      StrokeRect(bx, PF_Y, PF_W, 18);
      Continue;
    end;
    if (EditRow = PULLEY_ROW) and (EditField = P_FIELDS[i]) then
    begin
      Paper;
      FillRect(bx, PF_Y, PF_W, 18);
      Col(220, 90, 20);
      StrokeRect(bx, PF_Y, PF_W, 18);
      s := EditBuf;
      if EditFresh then
      begin
        FillRect(bx + 3, PF_Y + 4, Length(s) * 8 + 2, 11);
        Paper;
      end
      else
      begin
        Ink;
        if (SDL_GetTicks div 500) mod 2 = 0 then s := s + '_';
      end;
      Txt(bx + 4, PF_Y + 5, s);
    end
    else
    begin
      if InRect(MouseX, MouseY, bx, PF_Y, PF_W, 18) then Col(150, 150, 145) else Col(200, 200, 195);
      StrokeRect(bx, PF_Y, PF_W, 18);
      case i of
        0: v := UiSelX;
        1: v := UiSelY;
      else
        v := UiSelR;
      end;
      Ink;
      Txt(bx + 4, PF_Y + 5, FormatFloat('0.#', v, FS));
    end;
  end;

  for i := 0 to 3 do
    Button(PP_X + 16 + i * (PB_W + PB_GAP), PB_Y, PB_W, 22, PB_TEXT[i], False, PulleyButtonEnabled(i));
end;

function PulleyMouseDown(x, y: Single; var act: TUiAction): Boolean;
var
  i: Integer;
begin
  Result := InRect(x, y, PP_X, PP_Y, PP_W, PP_H);
  if not Result then Exit;
  if UiEditing then
    if UiCommitEdit then act := CommitAct;
  if UiRecording then Exit;
  for i := 0 to 3 do
    if InRect(x, y, PP_X + 16 + i * (PB_W + PB_GAP), PB_Y, PB_W, 22) then
    begin
      if PulleyButtonEnabled(i) then act := PB_ACT[i];
      Exit;
    end;
  for i := 0 to 2 do
    if InRect(x, y, PF_X[i] + PF_BOX, PF_Y, PF_W, 18) then
    begin
      StartPulleyEdit(P_FIELDS[i]);
      Exit;
    end;
end;

function PulleyWheel(x, y, dy: Single; shift: Boolean; var act: TUiAction): Boolean;
var
  i: Integer;
  v, stp: Single;
begin
  Result := InRect(x, y, PP_X, PP_Y, PP_W, PP_H);
  if not Result or (UiSelNode < 0) or UiRecording then Exit;
  for i := 0 to 2 do
    if InRect(x, y, PF_X[i] + PF_BOX, PF_Y, PF_W, 18) then
    begin
      UiCancelEdit;
      case i of
        0: v := UiSelX;
        1: v := UiSelY;
      else
        v := UiSelR;
      end;
      if shift then
        if i = 2 then stp := 5 else stp := 10
      else
        stp := 1;
      PulleyEditField := i;
      PulleyEditValue := v + Sign(dy) * stp;
      act := uaPulleyEdit;
      Exit;
    end;
end;

{ ---------- แผงลอย GRID / IMAGE ---------- }

const
  FP_W = 310;
  FP_H = 146;
  FP_GRID = 0;
  FP_IMAGE = 1;
  GRID_COLORS: array[0..5] of TRgb = (
    (r: 170; g: 170; b: 165), (r: 120; g: 120; b: 115), (r: 210; g: 210; b: 205),
    (r: 120; g: 160; b: 210), (r: 215; g: 130; b: 110), (r: 120; g: 180; b: 130));
  GRID_STYLE_NAME: array[0..3] of string = ('DASH', 'LINE', 'DOT', 'CROSS');
  IMG_MODE_BTN: array[0..3] of string = ('FIT', 'FILL', 'STRETCH', 'CENTER');

var
  FpX: array[0..1] of Single = (531, 531);      // มุมขวาบนของ View ไม่บังป้าย VIEW/NODE
  FpY: array[0..1] of Single = (SCENE_TOP + 70, SCENE_TOP + 230);
  FpDrag: Integer = -1;
  FpDragDX, FpDragDY: Single;

function FpVisible(i: Integer): Boolean;
begin
  if i = FP_GRID then Result := GridPanelOn else Result := ImagePanelOn;
end;

function FpAt(x, y: Single): Integer;
var
  i: Integer;
begin
  Result := -1;
  for i := 1 downto 0 do      // IMAGE วาดทีหลัง = อยู่บน
    if FpVisible(i) and InRect(x, y, FpX[i], FpY[i], FP_W, FP_H) then
      Exit(i);
end;

procedure FpClose(i: Integer);
begin
  if i = FP_GRID then GridPanelOn := False else ImagePanelOn := False;
end;

procedure FpHeader(i: Integer; const title: string);
var
  x, y: Single;
begin
  x := FpX[i];
  y := FpY[i];
  Col(200, 200, 195);
  FillRoundRect(x + 4, y + 4, FP_W, FP_H, 7);     // เงา
  Panel(x, y, FP_W, FP_H);
  Pill(x + 12, y + 10, title, True);
  Col(150, 150, 145);
  Txt(x + 30 + Length(title) * 8, y + 14, 'drag here');
  Button(x + FP_W - 30, y + 8, 20, 18, 'x', False, True);
end;

function GridColorIdx: Integer;
var
  i: Integer;
begin
  Result := -1;
  for i := 0 to High(GRID_COLORS) do
    if (GRID_COLORS[i].r = GridColor.r) and (GRID_COLORS[i].g = GridColor.g) and (GRID_COLORS[i].b = GridColor.b) then
      Exit(i);
end;

procedure DrawGridPanel;
var
  x, y: Single;
  i: Integer;
begin
  x := FpX[FP_GRID];
  y := FpY[FP_GRID];
  FpHeader(FP_GRID, 'GRID');
  Button(x + 12, y + 38, 60, 20, 'SHOW', GridOn, True);
  Button(x + 80, y + 38, 60, 20, 'SNAP', GridSnap, True);
  Col(110, 110, 105);
  Txt(x + 150, y + 44, 'snap = drag on grid');
  Col(110, 110, 105);
  Txt(x + 12, y + 70, 'step');
  Button(x + 60, y + 64, 20, 20, '-', False, True);
  Ink;
  Txt(x + 88, y + 70, Format('%3d px', [Round(GridStep)]));
  Button(x + 148, y + 64, 20, 20, '+', False, True);
  Col(110, 110, 105);
  Txt(x + 12, y + 96, 'style');
  for i := 0 to 3 do
    Button(x + 60 + i * 60, y + 90, 56, 20, GRID_STYLE_NAME[i], GridStyle = i, True);
  Col(110, 110, 105);
  Txt(x + 12, y + 122, 'color');
  for i := 0 to High(GRID_COLORS) do
  begin
    if GridColorIdx = i then
    begin
      Col(220, 90, 20);
      FillRoundRect(x + 58 + i * 26, y + 114, 24, 22, 4);
    end;
    Col(GRID_COLORS[i].r, GRID_COLORS[i].g, GRID_COLORS[i].b);
    FillRoundRect(x + 60 + i * 26, y + 116, 20, 18, 3);
    Ink;
    StrokeRoundRect(x + 60 + i * 26, y + 116, 20, 18, 3);
  end;
end;

procedure DrawImagePanel;
var
  x, y: Single;
  i: Integer;
  s: string;
begin
  x := FpX[FP_IMAGE];
  y := FpY[FP_IMAGE];
  FpHeader(FP_IMAGE, 'IMAGE');
  Button(x + 12, y + 38, 76, 20, 'OPEN...', False, True);
  Button(x + 94, y + 38, 60, 20, 'CLEAR', False, UiImgName <> '');
  s := UiImgName;
  if s = '' then s := 'no image';
  if Length(s) > 17 then s := Copy(s, 1, 15) + '..';
  if UiImgMissing then Col(215, 45, 35) else Ink;
  Txt(x + 162, y + 44, s);
  Col(110, 110, 105);
  Txt(x + 12, y + 70, 'fit');
  for i := 0 to 3 do
    Button(x + 60 + i * 60, y + 64, 58, 20, IMG_MODE_BTN[i], ImageMode = i, True);
  Col(110, 110, 105);
  Txt(x + 12, y + 96, 'opacity');
  Button(x + 84, y + 90, 20, 20, '-', False, True);
  Ink;
  Txt(x + 112, y + 96, Format('%3d %%', [ImageOpacity]));
  Button(x + 164, y + 90, 20, 20, '+', False, True);
  Col(110, 110, 105);
  if UiImgMissing then
    Txt(x + 12, y + 122, 'file not found')
  else if UiImgW > 0 then
    Txt(x + 12, y + 122, Format('%d x %d px  - shown behind the grid', [UiImgW, UiImgH]))
  else
    Txt(x + 12, y + 122, 'PNG / JPG / BMP ... as View background');
end;

function UiOverFloat(x, y: Single): Boolean;
begin
  Result := FpAt(x, y) >= 0;
end;

procedure DrawFloatPanels;
begin
  if GridPanelOn then DrawGridPanel;
  if ImagePanelOn then DrawImagePanel;
end;

{ คลิกในแผงลอย: คืน True ถ้าใช้เหตุการณ์ }
function FpMouseDown(x, y: Single; var act: TUiAction): Boolean;
var
  i, k: Integer;
  px, py: Single;
begin
  i := FpAt(x, y);
  Result := i >= 0;
  if not Result then Exit;
  px := FpX[i];
  py := FpY[i];
  if InRect(x, y, px + FP_W - 30, py + 8, 20, 18) then
  begin
    FpClose(i);
    Exit;
  end;
  if y < py + 32 then
  begin
    FpDrag := i;                         // ลากหัวแผงเพื่อย้าย
    FpDragDX := x - px;
    FpDragDY := y - py;
    Exit;
  end;
  if i = FP_GRID then
  begin
    if InRect(x, y, px + 12, py + 38, 60, 20) then GridOn := not GridOn
    else if InRect(x, y, px + 80, py + 38, 60, 20) then GridSnap := not GridSnap
    else if InRect(x, y, px + 60, py + 64, 20, 20) then GridStep := Max(10, GridStep - 5)
    else if InRect(x, y, px + 148, py + 64, 20, 20) then GridStep := Min(200, GridStep + 5)
    else
    begin
      for k := 0 to 3 do
        if InRect(x, y, px + 60 + k * 60, py + 90, 56, 20) then
        begin
          GridStyle := k;
          act := uaGridChanged;
        end;
      for k := 0 to High(GRID_COLORS) do
        if InRect(x, y, px + 60 + k * 26, py + 116, 20, 18) then
        begin
          GridColor := GRID_COLORS[k];
          act := uaGridChanged;
        end;
      Exit;
    end;
    act := uaGridChanged;
  end
  else
  begin
    if InRect(x, y, px + 12, py + 38, 76, 20) then act := uaImageOpen
    else if InRect(x, y, px + 94, py + 38, 60, 20) then
    begin
      if UiImgName <> '' then act := uaImageClear;
    end
    else if InRect(x, y, px + 84, py + 90, 20, 20) then
    begin
      ImageOpacity := Max(0, ImageOpacity - 10);
      act := uaImageChanged;
    end
    else if InRect(x, y, px + 164, py + 90, 20, 20) then
    begin
      ImageOpacity := Min(100, ImageOpacity + 10);
      act := uaImageChanged;
    end
    else
      for k := 0 to 3 do
        if InRect(x, y, px + 60 + k * 60, py + 64, 58, 20) then
        begin
          ImageMode := k;
          act := uaImageChanged;
        end;
  end;
end;

procedure DrawAnimPanel;
begin
  Panel(AP_X, AP_Y, AP_W, AP_H);
  Pill(AP_X + 16, TB_Y, 'ANIMATION', True);
  DrawTransport;
  Ink;
  Txt(AP_X + 322, TB_Y + 4, Format('%6.2f / %.2f s', [UiTime, ScriptLen], FS));
  if UiRecording then Col(215, 45, 35) else Col(220, 90, 20);
  Txt(AP_X + 470, TB_Y + 4, UiStatus);
  Col(150, 150, 145);
  Txt(AP_X + 620, TB_Y + 4, 'click value to type (Enter) - wheel adjusts, Shift x10');
  DrawTimeline;
  DrawList;
  DrawEditButtons;
end;

{ ---------- เมาส์ / คีย์บอร์ด ---------- }

function UiMouseDown(x, y: Single; out act: TUiAction): Boolean;
var
  i, r, c: Integer;
  total, bx, by, cx, ry: Single;
  f: TField;
begin
  act := uaNone;
  Result := False;
  MouseX := x;
  MouseY := y;

  { เมนู }
  if MenuIdx >= 0 then
  begin
    c := MenuIdx;
    i := MenuItemAt(x, y);
    UiCloseMenu;
    if i >= 0 then
      if c = 0 then
        act := MENU_ACT[i]
      else if i = 0 then
        GridPanelOn := not GridPanelOn
      else
        ImagePanelOn := not ImagePanelOn
    else if MenuTitleAt(x, y) >= 0 then
    begin
      if MenuTitleAt(x, y) <> c then MenuIdx := MenuTitleAt(x, y);
    end;
    Exit(True);
  end;
  if InRect(x, y, 0, 0, 1280, MENU_H) then
  begin
    if MenuTitleAt(x, y) >= 0 then
    begin
      UiCommitEdit;
      MenuIdx := MenuTitleAt(x, y);
      MenuHover := -1;
    end;
    Exit(True);
  end;

  { แผงลอย GRID / IMAGE อยู่บนสุดของฉาก }
  if FpMouseDown(x, y, act) then Exit(True);

  { แผง BELT }
  if InRect(x, y, BP_X, BP_Y, BP_W, BP_H) then
  begin
    i := ToolbarItemAt(x, y);
    if i >= 0 then
    begin
      act := TB_ITEMS[i].act;
      PickedColor := TB_ITEMS[i].tag;
    end;
    Exit(True);
  end;

  { แผง PULLEY }
  if PulleyMouseDown(x, y, act) then Exit(True);

  if not InRect(x, y, AP_X, AP_Y, AP_W, AP_H) then
  begin
    if UiCommitEdit then act := CommitAct;
    Exit(False);
  end;
  Result := True;

  { คลิกที่อื่นในแผง = ยืนยันค่าที่กำลังพิมพ์ก่อน }
  if UiEditing then
    if UiCommitEdit then act := CommitAct;

  { ปุ่มควบคุม }
  for i := 0 to 3 do
    if InRect(x, y, TR_X[i], TB_Y - 2, TR_W[i], 20) then
    begin
      if (i = 0) and UiRecording then Exit;
      act := TR_ACT[i];
      Exit;
    end;

  { timeline }
  if InRect(x, y, TL_X, TL_Y - 6, TL_W, TL_H + 8) then
  begin
    if UiRecording then Exit;
    total := Max(ScriptLen, 1);
    ScrubT := EnsureRange((x - TL_X) / TL_W, 0, 1) * total;
    Sel := PhaseAt(Min(ScrubT, ScriptLen - 1e-4));
    EnsureSelVisible;
    Scrubbing := True;
    act := uaScrub;
    Exit;
  end;

  { ปุ่มแก้ไข }
  for i := 0 to High(EDIT_BTN) do
  begin
    bx := BT_X + (i mod 3) * (BT_W + BT_GAP);
    by := BT_Y + (i div 3) * (BT_H + BT_GAP);
    if InRect(x, y, bx, by, BT_W, BT_H) then
    begin
      if UiRecording then Exit;
      if (EDIT_ACT[i] in [uaDelete, uaUp, uaDown, uaSetPos]) and ((Sel < 0) or (Sel > High(Phases))) then
        Exit;
      act := EDIT_ACT[i];
      Exit;
    end;
  end;

  { รายการ }
  if InRect(x, y, LS_X, LS_Y, LS_W, ROWS * ROW_H + 2) and not UiRecording then
  begin
    r := Floor((y - LS_Y - 1) / ROW_H);
    i := ListTop + r;
    if (r < 0) or (r >= ROWS) or (i > High(Phases)) then Exit;
    Sel := i;
    if act = uaNone then act := uaSelect;
    ry := LS_Y + 1 + r * ROW_H;
    for c := 0 to 3 do
    begin
      f := Fields(Phases[i].kind, c);
      if f = fNone then Break;
      cx := LS_X + CELL_X0 + c * CELL_W;
      if InRect(x, y, cx + VAL_OFS - 3, ry, VAL_W, ROW_H) then
      begin
        StartEdit(i, f);
        Break;
      end;
    end;
  end;
end;

function UiMouseMove(x, y: Single; leftDown: Boolean; out act: TUiAction): Boolean;
var
  total: Single;
begin
  act := uaNone;
  MouseX := x;
  MouseY := y;
  Result := False;
  if MenuIdx >= 0 then
  begin
    MenuHover := MenuItemAt(x, y);
    if (MenuTitleAt(x, y) >= 0) and (MenuTitleAt(x, y) <> MenuIdx) then
    begin
      MenuIdx := MenuTitleAt(x, y);            // เลื่อนไปอีกเมนูโดยไม่ต้องคลิก
      MenuHover := -1;
    end;
    Exit(True);
  end;
  if (FpDrag >= 0) and leftDown then
  begin
    FpX[FpDrag] := EnsureRange(x - FpDragDX, 0, 1280 - FP_W);
    FpY[FpDrag] := EnsureRange(y - FpDragDY, MENU_H, AP_Y + AP_H - FP_H);
    Exit(True);
  end;
  if Scrubbing and leftDown then
  begin
    total := Max(ScriptLen, 1);
    ScrubT := EnsureRange((x - TL_X) / TL_W, 0, 1) * total;
    Sel := PhaseAt(Min(ScrubT, ScriptLen - 1e-4));
    EnsureSelVisible;
    act := uaScrub;
    Result := True;
  end;
end;

procedure UiMouseUp;
begin
  Scrubbing := False;
  FpDrag := -1;
end;

function UiWheel(x, y, dy: Single; shift: Boolean; out act: TUiAction): Boolean;
var
  r, i, c: Integer;
  cx, ry: Single;
  f: TField;
begin
  act := uaNone;
  if MenuIdx >= 0 then Exit(True);
  if FpAt(x, y) >= 0 then Exit(True);       // ไม่ให้ล้อทะลุแผงลอยไปปรับรัศมี pulley
  if PulleyWheel(x, y, dy, shift, act) then Exit(True);
  Result := InRect(x, y, AP_X, AP_Y, AP_W, AP_H);
  if not Result or UiRecording then Exit;
  if not InRect(x, y, LS_X, LS_Y, LS_W, ROWS * ROW_H + 2) then Exit;

  r := Floor((y - LS_Y - 1) / ROW_H);
  i := ListTop + r;
  if (r >= 0) and (r < ROWS) and (i <= High(Phases)) then
  begin
    ry := LS_Y + 1 + r * ROW_H;
    for c := 0 to 3 do
    begin
      f := Fields(Phases[i].kind, c);
      if f = fNone then Break;
      cx := LS_X + CELL_X0 + c * CELL_W;
      if InRect(x, y, cx + VAL_OFS - 3, ry, VAL_W, ROW_H) then
      begin
        UiCancelEdit;
        SetField(Phases[i], f, GetField(Phases[i], f) + Sign(dy) * FieldStep(f, shift));
        Recalc;
        Sel := i;
        act := uaEdited;
        Exit;
      end;
    end;
  end;
  { เลื่อนรายการ }
  ListTop := ListTop - Round(Sign(dy));
  ListTop := Max(0, Min(ListTop, Length(Phases) - ROWS));
end;

function NextField(dir: Integer): Boolean;
var
  c, k: Integer;
begin
  Result := False;
  if EditRow = PULLEY_ROW then
  begin
    k := PulleyFieldIndex(EditField) + dir;
    if (k >= 0) and (k <= 2) then
    begin
      StartPulleyEdit(P_FIELDS[k]);
      Result := True;
    end;
    Exit;
  end;
  if EditRow < 0 then Exit;
  for c := 0 to 3 do
    if Fields(Phases[EditRow].kind, c) = EditField then
    begin
      k := c + dir;
      if (k >= 0) and (k <= 3) and (Fields(Phases[EditRow].kind, k) <> fNone) then
      begin
        StartEdit(EditRow, Fields(Phases[EditRow].kind, k));
        Result := True;
      end;
      Exit;
    end;
end;

function UiKey(key: TSDL_Keycode; shift: Boolean; out act: TUiAction): Boolean;
var
  row: Integer;
  f: TField;
begin
  act := uaNone;
  Result := False;
  if MenuIdx >= 0 then
  begin
    if key = SDLK_ESCAPE then UiCloseMenu;
    Exit(True);
  end;
  if EditRow <> -1 then
  begin
    Result := True;
    case key of
      SDLK_ESCAPE: UiCancelEdit;
      SDLK_BACKSPACE:
        begin
          if EditFresh then EditBuf := ''
          else if EditBuf <> '' then SetLength(EditBuf, Length(EditBuf) - 1);
          EditFresh := False;
        end;
      SDLK_RETURN, SDLK_KP_ENTER:
        if UiCommitEdit then act := CommitAct;
      SDLK_TAB:
        begin
          row := EditRow;
          f := EditField;
          if UiCommitEdit then act := CommitAct;
          EditRow := row;
          EditField := f;
          if shift then
            NextField(-1)
          else
            NextField(1);
          if EditField = f then UiCancelEdit;   // ไม่มีช่องถัดไป
        end;
    end;
    Exit;
  end;
  if UiRecording then Exit;
  case key of
    SDLK_DELETE:
      if (Sel >= 0) and (Sel <= High(Phases)) then
      begin
        act := uaDelete;
        Result := True;
      end;
    SDLK_UP, SDLK_DOWN:
      if Length(Phases) > 0 then
      begin
        if key = SDLK_UP then Sel := Max(0, Sel - 1) else Sel := Min(High(Phases), Sel + 1);
        EnsureSelVisible;
        act := uaSelect;
        Result := True;
      end;
  end;
end;

initialization
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
end.
